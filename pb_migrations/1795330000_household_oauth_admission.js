migrate((app) => {
    const users = app.findCollectionByNameOrId("users");
    // PocketBase 0.39 dispatches OAuth provisioning through its internal record
    // creation API. A locked (null) rule also rejects legitimate first sign-in.
    // This context is assigned by the server, not by caller headers or JSON.
    users.createRule = '@request.context = "oauth2"';
    app.save(users);
}, () => {
    // Never reopen public password registration during an image rollback.
});
