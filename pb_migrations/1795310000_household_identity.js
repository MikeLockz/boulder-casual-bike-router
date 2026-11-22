/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
    const users = app.findCollectionByNameOrId("users");
    users.fields.add(new TextField({name: "household_subject", hidden: true, max: 255}));
    users.fields.add(new DateField({name: "household_authenticated_at", hidden: true}));
    // OAuth may provision authorized household users internally. Public password
    // registration stays closed; existing password login is retained for verification.
    users.createRule = null;
    users.authToken.duration = 900;
    app.save(users);
}, (app) => {
    // Do not erase subject bindings or reopen registration as an image rollback.
    // Recover the compatible DB/config checkpoint if schema rollback is required.
});
