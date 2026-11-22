/// <reference path="../pb_data/types.d.ts" />
onRealtimeSubscribeRequest((e) => {
    // The web SDK needs only its OAuth callback channel. Legacy collection
    // rules are intentionally used by the private Flask API; never expose
    // their record streams through the public realtime subscription endpoint.
    if (e.subscriptions.length > 1 || e.subscriptions.some(topic => topic !== "@oauth2")) {
        throw new ForbiddenError("Only the household sign-in callback channel is available");
    }
    e.next();
});

onBootstrap((e) => {
    e.next();
    if ($os.getenv("BOULDER_HOUSEHOLD_OIDC") !== "1") return;
    const config = JSON.parse(toString($os.readFile("/run/secrets/boulder-oidc.json")));
    if (config.client_id !== "boulder-lockdev" || typeof config.client_secret !== "string" || config.client_secret.length < 32) {
        throw new Error("Invalid protected Boulder OIDC configuration");
    }
    const users = e.app.findCollectionByNameOrId("users");
    const oauth = {
        enabled: true,
        providers: [{
            name: "oidc", clientId: config.client_id, clientSecret: config.client_secret,
            authURL: "https://authelia.lockdev.com/api/oidc/authorization",
            tokenURL: "https://authelia.lockdev.com/api/oidc/token",
            userInfoURL: "https://authelia.lockdev.com/api/oidc/userinfo",
            extra: {}
        }]
    };
    const provider = users.oauth2.providers.find(p => p.name === "oidc");
    if (!users.oauth2.enabled || !provider ||
        Object.keys(oauth.providers[0]).some(key => key !== "extra" && provider[key] !== oauth.providers[0][key])) {
        users.oauth2 = oauth;
        e.app.save(users);
    }
    if ($os.getenv("BOULDER_HOUSEHOLD_PASSWORD_RECOVERY") === "0" && users.passwordAuth.enabled) {
        // Administrator-only acceptance switch. Never re-enable passwords on a
        // rerun; invalidate retained password sessions when this switch closes.
        users.passwordAuth.enabled = false;
        users.authToken.secret = $security.randomString(50);
        e.app.save(users);
    }
});

onRecordAuthWithOAuth2Request((e) => {
    if (e.providerName !== "oidc" || !e.oAuth2User) throw new ForbiddenError("Unsupported sign-in provider");
    const user = e.oAuth2User;
    const groups = user.rawUser.groups || [];
    if (!Array.isArray(groups) || !groups.some(group => ["family", "kids", "admins"].includes(group)) ||
        user.rawUser.email_verified !== true || !user.email || !user.id) {
        throw new ForbiddenError("Household membership and verified email required");
    }
    if (e.record) {
        if (e.auth && e.auth.collection().name === "users" && e.auth.id !== e.record.id) {
            throw new ForbiddenError("This LockDev identity belongs to another Boulder profile");
        }
        const subject = e.record.getString("household_subject");
        if (subject && subject !== user.id) throw new ForbiddenError("This profile is linked to another identity");
        // PocketBase's email fallback alone is not consent to link an old profile.
        if (!subject && (!e.auth || e.auth.collection().name !== "users" || e.auth.id !== e.record.id)) {
            throw new ForbiddenError("Sign in to the existing Boulder profile before linking LockDev");
        }
    }
    // New household profiles come only from verified provider data. Do not let
    // an admitted caller preclaim another email, choose a local password, or
    // assign hidden identity/role fields through the optional createData payload.
    e.createData = {};
    // Assign the authenticated profile explicitly when the directory email has
    // changed and PocketBase has no email/provider match. Never create a second
    // profile while the user is asking to link their signed-in profile.
    if (!e.record && e.auth && e.auth.collection().name === "users") {
        e.record = e.auth;
        e.isNewRecord = false;
        const subject = e.record.getString("household_subject");
        if (subject && subject !== user.id) throw new ForbiddenError("This profile is linked to another identity");
    }
    e.set("boulder_household_subject", user.id);
    e.set("boulder_household_profile", e.record ? e.record.id : "");
    e.next();
}, "users");

onRecordAuthRequest((e) => {
    if (e.authMethod === "password" && $os.getenv("BOULDER_HOUSEHOLD_PASSWORD_RECOVERY") === "1" &&
        e.record.getString("household_subject")) {
        e.record.set("household_recovery_authenticated_at", new Date().toISOString());
        e.app.save(e.record);
    }
    if (e.authMethod !== "oauth2") return e.next();
    const subject = e.get("boulder_household_subject");
    const profile = e.get("boulder_household_profile");
    if (typeof subject !== "string" || !subject || !e.record || (profile && profile !== e.record.id)) {
        throw new UnauthorizedError("Household authentication context is missing or changed");
    }
    // Persist admission metadata before the token response is written. A failed
    // save must not yield a usable session with no revocation/renewal boundary.
    e.record.set("household_subject", subject);
    e.record.set("household_authenticated_at", new Date().toISOString());
    e.app.save(e.record);
    e.next();
}, "users");

onRecordUpdateRequest((e) => {
    const body = e.requestInfo().body;
    if (typeof body.household_subject !== "undefined" || typeof body.household_authenticated_at !== "undefined" ||
        typeof body.household_recovery_authenticated_at !== "undefined" ||
        e.record.getString("household_subject") !== e.record.original().getString("household_subject") ||
        e.record.getString("household_authenticated_at") !== e.record.original().getString("household_authenticated_at") ||
        e.record.getString("household_recovery_authenticated_at") !== e.record.original().getString("household_recovery_authenticated_at")) {
        throw new ForbiddenError("Identity metadata is managed by household sign-in");
    }
    e.next();
}, "users");

onRecordAuthRefreshRequest((e) => {
    const subject = e.record.getString("household_subject");
    const linked = e.app.findAllExternalAuthsByRecord(e.record).some(auth => auth.provider() === "oidc");
    if (subject || linked) {
        if (!subject) throw new UnauthorizedError("Please complete LockDev sign-in again");
        let last = Date.parse(e.record.getString("household_authenticated_at").replace(" ", "T"));
        if ($os.getenv("BOULDER_HOUSEHOLD_PASSWORD_RECOVERY") === "1") {
            const recovery = Date.parse(e.record.getString("household_recovery_authenticated_at").replace(" ", "T"));
            if (Number.isFinite(recovery) && (!Number.isFinite(last) || recovery > last)) last = recovery;
        }
        const age = Date.now() - last;
        if (!Number.isFinite(age) || age < 0 || age >= 900000) {
            throw new UnauthorizedError("Please sign in with LockDev again");
        }
    }
    e.next();
}, "users");
