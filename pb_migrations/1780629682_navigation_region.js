/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");
  collection.fields.add(new Field({
    name: "region",
    type: "select",
    required: false,
    maxSelect: 1,
    values: ["boulder", "broomfield"],
  }));
  collection.indexes.push("CREATE INDEX idx_navigation_routes_region ON navigation_routes (region)");
  app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");
  collection.fields.removeByName("region");
  collection.indexes = collection.indexes.filter((index) => !index.includes("idx_navigation_routes_region"));
  app.save(collection);
});
