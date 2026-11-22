/// <reference path="../pb_data/types.d.ts" />
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
        const subject = e.record.getString("household_subject");
        if (subject && subject !== user.id) throw new ForbiddenError("This profile is linked to another identity");
        // PocketBase's email fallback alone is not consent to link an old profile.
        if (!subject && (!e.auth || e.auth.collection().name !== "users" || e.auth.id !== e.record.id)) {
            throw new ForbiddenError("Sign in to the existing Boulder profile before linking LockDev");
        }
    }
    // Do not accept caller-selected hidden identity metadata during OAuth signup.
    if (e.createData) {
        delete e.createData.household_subject;
        delete e.createData.household_authenticated_at;
    }
    e.next();
    e.record.set("household_subject", user.id);
    e.record.set("household_authenticated_at", new Date().toISOString());
    e.app.save(e.record);
}, "users");

onRecordUpdateRequest((e) => {
    const body = e.requestInfo().body;
    if (typeof body.household_subject !== "undefined" || typeof body.household_authenticated_at !== "undefined" ||
        e.record.getString("household_subject") !== e.record.original().getString("household_subject") ||
        e.record.getString("household_authenticated_at") !== e.record.original().getString("household_authenticated_at")) {
        throw new ForbiddenError("Identity metadata is managed by household sign-in");
    }
    e.next();
}, "users");

onRecordAuthRefreshRequest((e) => {
    if (e.record.getString("household_subject")) {
        const last = Date.parse(e.record.getString("household_authenticated_at").replace(" ", "T"));
        const age = Date.now() - last;
        if (!Number.isFinite(age) || age < 0 || age >= 900000) {
            throw new UnauthorizedError("Please sign in with LockDev again");
        }
    }
    e.next();
}, "users");
