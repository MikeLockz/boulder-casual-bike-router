/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");

  collection.fields.add(new Field({
    name: "start_near_name",
    type: "text",
  }));

  collection.fields.add(new Field({
    name: "end_near_name",
    type: "text",
  }));

  app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");

  collection.fields.removeByName("start_near_name");
  collection.fields.removeByName("end_near_name");

  app.save(collection);
});
