/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");

  collection.fields.add(new Field({
    name: "display_distance_meters",
    type: "number",
  }));

  collection.fields.add(new Field({
    name: "display_duration_seconds",
    type: "number",
  }));

  collection.fields.add(new Field({
    name: "display_average_speed",
    type: "number",
  }));

  app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");

  collection.fields.removeByName("display_distance_meters");
  collection.fields.removeByName("display_duration_seconds");
  collection.fields.removeByName("display_average_speed");

  app.save(collection);
});
