/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const places = new Collection({
    name: "places",
    type: "base",
    fields: [
      {
        name: "osm_type",
        type: "text",
        required: true,
      },
      {
        name: "osm_id",
        type: "text",
        required: true,
      },
      {
        name: "name",
        type: "text",
        required: true,
      },
      {
        name: "search_name",
        type: "text",
        required: true,
      },
      {
        name: "type",
        type: "text",
      },
      {
        name: "lat",
        type: "number",
        required: true,
      },
      {
        name: "lng",
        type: "number",
        required: true,
      },
      {
        name: "source",
        type: "text",
      },
      {
        name: "tags",
        type: "json",
      }
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_places_osm_ref ON places (osm_type, osm_id)",
      "CREATE INDEX idx_places_search_name ON places (search_name)",
      "CREATE INDEX idx_places_type ON places (type)"
    ],
    listRule: "",
    viewRule: "",
    createRule: null,
    updateRule: null,
    deleteRule: null,
  });

  app.save(places);
}, (app) => {
  try {
    const places = app.findCollectionByNameOrId("places");
    app.delete(places);
  } catch (e) {}
});
