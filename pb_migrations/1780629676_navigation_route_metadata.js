/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");

  collection.fields.add(new Field({
    name: "display_name",
    type: "text",
  }));

  collection.fields.add(new Field({
    name: "notes",
    type: "text",
  }));

  app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");

  collection.fields.removeByName("display_name");
  collection.fields.removeByName("notes");

  app.save(collection);
});
