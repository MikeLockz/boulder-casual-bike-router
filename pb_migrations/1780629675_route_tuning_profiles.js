/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const profiles = new Collection({
    name: "route_tuning_profiles",
    type: "base",
    fields: [
      {
        name: "user",
        type: "relation",
        required: true,
        collectionId: "_pb_users_auth_",
        cascadeDelete: true,
        maxSelect: 1,
      },
      {
        name: "name",
        type: "text",
        required: true,
      },
      {
        name: "weights",
        type: "json",
        required: true,
      },
      {
        name: "offsets",
        type: "json",
      },
      {
        name: "is_default",
        type: "bool",
      }
    ],
    indexes: [
      "CREATE INDEX idx_route_tuning_profiles_user ON route_tuning_profiles (user)",
      "CREATE INDEX idx_route_tuning_profiles_user_default ON route_tuning_profiles (user, is_default)"
    ],
    listRule: "user = @request.auth.id",
    viewRule: "user = @request.auth.id",
    createRule: "@request.auth.id != '' && user = @request.auth.id",
    updateRule: "@request.auth.id != '' && user = @request.auth.id",
    deleteRule: "@request.auth.id != '' && user = @request.auth.id",
  });

  app.save(profiles);
}, (app) => {
  try {
    const profiles = app.findCollectionByNameOrId("route_tuning_profiles");
    app.delete(profiles);
  } catch (e) {}
});
