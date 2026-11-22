# Boulder hosting and recovery

Implementation in progress, **2026-11-21 America/Denver**. Production remains on
VM 100, source `cc02768d6f4739f173ad7e7416fcbe19e57e31e7`. VM 110 has a restricted staging deployment from signed release
`9b9f68a4ef86a8f3921d18f149f5bc6e7d5e6e8a`; neither real-client SSO nor cutover
is accepted. Keep the old
writers, route and database until the shared apps-host plan's cutover window.

## Placement and source

The new host is `lockdev-apps`, Proxmox VM 110, LAN `192.168.1.46`, Tailscale
`100.97.153.78`. `lockdev-infra/guests/apps-host/` owns provisioning, shared
Traefik, network policy, backup controller and host telemetry. This repository
owns the application code, immutable images, production Compose and Boulder
route in `config/traefik/rules/boulder.yml`. The service catalog explicitly
records both route locations during staging, keeping production DNS on VM 100.

`compose.production.yml` publishes no host ports. Only the static frontend joins
the ingress network; PocketBase and Flask remain on the per-app private network.
The backend also joins the internal collector network. Databases never use SMB.
No source checkout, Docker socket or writable host configuration is mounted in
an application. Frontend/backend run as UID 101/10001 with read-only root filesystems,
dropped capabilities, memory/CPU limits and bounded host Docker logs.

Production image bases are digest-pinned. `requirements.production.txt` is a
hash-pinned Python 3.11 lock generated from `requirements.in`; Flask 3.1.3,
NetworkX 3.6.1 and Requests 2.34.2 match the inspected live backend. Build contexts
are an explicit code-only allowlist; `.env`, databases, keys, PEM files, local
venvs and graph caches are excluded. Build and publish in CI, never on VM 110.
The public GHCR images and source attestations are verified by the root-owned
dispatcher before deployment. A real main-branch CI deployment succeeded at
[run 44992914382](https://github.com/MikeLockz/boulder-casual-bike-router/actions/runs/44992914382).
Its federated runner reached only the new host’s forced deployment SSH account;
the checked HTTPS, metrics and other-host SSH destinations were denied.

## Household identity and linking

PocketBase remains **0.39.1**. Its native `oidc` provider uses Authelia backed by
LLDAP; no browser challenge is inserted in front of bearer-token APIs. Admission
must allow `family`, `kids` and `admins` explicitly as ordinary application users.
Directory administrators receive no PocketBase superuser session. `_superusers`
remains SSH-assisted recovery only, blocked at the application frontend.

Protected provider configuration is JSON at
`/etc/lockdev-apps/boulder/oidc.json`, mounted read-only only into PocketBase as
`/run/secrets/boulder-oidc.json`:

```json
{"client_id":"boulder-lockdev","client_secret":"PROTECTED_RUNTIME_VALUE"}
```

Never commit that file. Register the confidential Authelia client with PKCE S256,
authorization code flow, scopes `openid profile email groups` and only these exact
redirects:

- Web: `https://boulder.lockdev.com/pb/api/oauth2-redirect`
- Native: `com.lockdev.boulder:/oauth2redirect`

The web uses integrity-verified, vendored PocketBase SDK 0.29.0 for state/PKCE and
the realtime callback, then the existing `pocketbase_auth` session abstraction.
iOS uses `ASWebAuthenticationSession`, cryptographic per-attempt state/verifier,
S256, exact callback validation and a server-side code exchange through PocketBase.
The resulting token goes through the existing Keychain-backed `AuthSessionStore`.
The client secret is never sent to browser/iPhone code.

**Existing profile linking requires an authenticated Boulder session.** Sign in
to the existing profile first, then choose **Link LockDev to this profile** in
Settings from that same session (web or iOS). The
hook rejects PocketBase's email-only fallback when no matching authenticated
profile is present. Once linked, a different OIDC subject cannot take over the
profile. Verify the unchanged profile ID, home setting, tuning profiles, routes
and ticks before removing household password access. Guest possession tokens
remain separate from directory identities.

The staged schema closes arbitrary password registration, leaves existing
password login available and adds hidden server-managed identity fields. Hidden
fields are filtered by PocketBase's normal record API; the hook also rejects
identity metadata when presented to it. Isolated tests showed a forged timestamp
cannot renew an expired household session. Recovery must use trusted SSH and
PocketBase administrative tools, never expose its admin endpoint publicly.

Initial staged token lifetime and maximum household renewal age are 15 minutes.
After that a new OIDC authorization is required; a removed group cannot acquire
a new session. The staged `BOULDER_HOUSEHOLD_PASSWORD_RECOVERY=1` retains password recovery
until client acceptance. A successful password sign-in starts its own 15-minute
recovery window; an old SSO timestamp cannot make the retained password unusable.
This is a temporary admission/revocation exception: a removed directory member
who still knows the retained password can use that recovery path. After real
linking, recovery and mobile checks pass, an administrator sets the flag to `0`.
The hook disables password authentication and rotates the token secret once,
revoking retained sessions. Reruns never re-enable passwords. A schema migration
also revokes older long-lived tokens when first installed. This
short policy still needs real iPhone/background-navigation verification before
acceptance or disabling passwords; unit tests do not prove native lifecycle or
group-removal behavior against the live identity provider.

## Runtime and maintenance

Root-owned definitions: `/etc/lockdev-apps/boulder/{compose.yml,release.env,oidc.json}`.
Data: `/srv/lockdev-apps/data/boulder/pocketbase/` (entire PocketBase directory,
including uploads and SQLite files), and `/srv/lockdev-apps/data/boulder/graphs/`
(regenerable caches). Release manifests/checkpoints belong under
`/srv/lockdev-apps/releases/boulder/RELEASE/`. Only the reviewed fixed dispatcher
may execute a CI deployment; no Docker-group membership or arbitrary Compose uploads.
Provenance enforcement and the forced-command deployment are active on staging.
The GitHub environment accepts only main, and main requires policy, application,
image/runtime and native-auth checks.

`GET /api/health?region=boulder` and `?region=broomfield` must both become ready.
Flask runs one Gunicorn worker with eight threads; that worker owns both graphs.
`GET /internal/metrics` is private to the collector; nginx explicitly returns
404 for `/internal/`. Route metrics contain only known region/status labels,
never user IDs, coordinates or request tokens. Production has no backend/PB ports.

The independent backup controller stops only Boulder backend/PocketBase, cold
copies all PB files, restarts in a finally path, checks SQLite copies, verifies a
complete checksum-manifest archive, encrypts with the public recovery certificate,
then sends directly from VM 110 to Tower LAN SSH. Only a separate remote ciphertext
read-back permits success status/retention. One operations lock serializes backup,
migration and deployment. A failed predeploy backup must block schema changes.

Target: `/mnt/user/backup/Apps/LockDev-Apps/{scheduled,baseline,predeploy}/` on Tower.
Local: `/var/backups/lockdev-apps/`. Schedule: 00:30 America/Denver, seven completed
local scheduled archives and thirty completed Tower scheduled archives. Baselines
are not pruned. Predeploy checkpoints stay through at least the 14-day rollback
window and the last two releases. The timer remains disabled during preparation.
The VM 100 rehearsal cold copy was encrypted, decrypted on the Mac, verified
file by file, sent directly from VM 110 to Tower, and restored into staging.
All stable user/ownership fingerprints matched after PocketBase startup: one
user/config, 37 routes, 7,627 ticks and two tuning profiles. The cold pause was
22.074 seconds and the old writers resumed. A VM 110 baseline guest backup was
restored as network-isolated VM 111, checked and removed. A newer VM 110
application-archive restore and interruption/failure tests remain pending.

## Recovery and migration gates

Recreate/configure the guest from infra, recover secrets through the independently
held encrypted key kit, decrypt a compatible app archive on a recovery machine,
verify every manifest file/SQLite database, and restore the whole PB directory
with writers stopped. Use recorded compatible image digests. Do not boot cloned
Tailscale state on a recovery guest's network. Rehearse without production writes
or guest-network exposure before changing the canonical route.

At cutover pause the old deployment workflow and writers, take a final verified
cold copy, compare ownership/counts, restore to VM 110 and switch generated DNS
and routes. Enable only one production writer. Retain stopped VM 100 Boulder data
and its release for at least 14 days. Never restore an old database over newer
writes; preserve/export new writes and reconcile them before any database rollback.
Image rollback alone does not reverse schema migrations.

The confidential Authelia client is registered. Monitoring reaches the private
central ingestion endpoint; all five collection jobs report up, and all three
Boulder containers have resource metrics. The restricted notification publisher
passed publish/read/other-topic boundaries; phone receipt remains pending.

Pending: real profile linking, browser/iPhone SSO, live denied-group/cross-user
checks, token revocation/recovery, the full client network matrix (home off/on,
away on/off), native transitions, newer application restore, interruption/failure
alerts and media-VM outage verification. Backup and external-check timers remain
disabled during preparation. Production DNS and old writers remain on VM 100.
The user requested preparation with unavailable human checks explicitly pending.
No migration-complete claim is justified yet. Eldorado Fly/Pages and stopped
LXC 902 remain unchanged.
