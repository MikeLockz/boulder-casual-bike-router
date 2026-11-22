migrate((app) => {
    const users = app.findCollectionByNameOrId("users");
    users.fields.add(new DateField({name: "household_recovery_authenticated_at", hidden: true}));
    // Old, longer-lived password tokens must not bypass the staged 15-minute
    // session boundary. Existing passwords and stable profile IDs are retained.
    users.authToken.secret = $security.randomString(50);
    app.save(users);
}, () => {
    // Retain hidden server-managed metadata and never resurrect revoked tokens.
});
