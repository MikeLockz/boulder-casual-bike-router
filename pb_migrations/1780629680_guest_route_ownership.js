/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("navigation_routes");

  collection.fields.add(new Field({
    name: "guest_owner_hash",
    type: "text",
    max: 64,
  }));
  collection.indexes.push(
    "CREATE INDEX idx_navigation_routes_guest_owner_hash ON navigation_routes (guest_owner_hash)"
  );
  app.save(collection);

  for (const collectionName of ["place_search_events", "route_analytics_events"]) {
    const analyticsCollection = app.findCollectionByNameOrId(collectionName);
    analyticsCollection.fields.add(new Field({
      name: "guest_owner_hash",
      type: "text",
      max: 64,
    }));
    analyticsCollection.indexes.push(
      `CREATE INDEX idx_${collectionName}_guest_owner_hash ON ${collectionName} (guest_owner_hash)`
    );
    app.save(analyticsCollection);
  }
}, (app) => {
  for (const collectionName of ["place_search_events", "route_analytics_events"]) {
    const analyticsCollection = app.findCollectionByNameOrId(collectionName);
    analyticsCollection.indexes = analyticsCollection.indexes.filter(
      (index) => !index.includes(`idx_${collectionName}_guest_owner_hash`)
    );
    analyticsCollection.fields.removeByName("guest_owner_hash");
    app.save(analyticsCollection);
  }

  const collection = app.findCollectionByNameOrId("navigation_routes");
  collection.indexes = collection.indexes.filter(
    (index) => !index.includes("idx_navigation_routes_guest_owner_hash")
  );
  collection.fields.removeByName("guest_owner_hash");
  app.save(collection);
});
