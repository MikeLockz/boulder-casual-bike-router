/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  // Create navigation_routes collection
  const navigationRoutes = new Collection({
    name: "navigation_routes",
    type: "base",
    fields: [
      {
        name: "user",
        type: "relation",
        collectionId: "_pb_users_auth_",
        cascadeDelete: true,
        maxSelect: 1,
      },
      {
        name: "start_lat",
        type: "number",
        required: true,
      },
      {
        name: "start_lon",
        type: "number",
        required: true,
      },
      {
        name: "end_lat",
        type: "number",
        required: true,
      },
      {
        name: "end_lon",
        type: "number",
        required: true,
      },
      {
        name: "start_point_name",
        type: "text",
      },
      {
        name: "end_point_name",
        type: "text",
      },
      {
        name: "route_geojson",
        type: "json",
        required: true,
      },
      {
        name: "total_length_meters",
        type: "number",
        required: true,
      },
      {
        name: "total_estimated_time_seconds",
        type: "number",
        required: true,
      },
      {
        name: "status",
        type: "text",
        required: true,
      },
      {
        name: "started_at",
        type: "date",
        required: true,
      },
      {
        name: "ended_at",
        type: "date",
      },
      {
        name: "ended_lat",
        type: "number",
      },
      {
        name: "ended_lon",
        type: "number",
      },
      {
        name: "actual_distance_meters",
        type: "number",
      },
      {
        name: "actual_duration_seconds",
        type: "number",
      },
      {
        name: "average_speed",
        type: "number",
      },
      {
        name: "device_type",
        type: "text",
      },
      {
        name: "weights",
        type: "json",
      }
    ],
    indexes: [
      "CREATE INDEX idx_navigation_routes_user ON navigation_routes (user)"
    ],
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
  });

  app.save(navigationRoutes);

  // Retrieve resolved collection to get its auto-generated ID
  const resolvedRoutes = app.findCollectionByNameOrId("navigation_routes");

  // Create navigation_ticks collection
  const navigationTicks = new Collection({
    name: "navigation_ticks",
    type: "base",
    fields: [
      {
        name: "route",
        type: "relation",
        required: true,
        collectionId: resolvedRoutes.id,
        cascadeDelete: true,
        maxSelect: 1,
      },
      {
        name: "lat",
        type: "number",
        required: true,
      },
      {
        name: "lon",
        type: "number",
        required: true,
      },
      {
        name: "speed",
        type: "number",
      },
      {
        name: "direction",
        type: "number",
      },
      {
        name: "accuracy",
        type: "number",
      },
      {
        name: "altitude",
        type: "number",
      },
      {
        name: "timestamp",
        type: "date",
        required: true,
      },
      {
        name: "battery_level",
        type: "number",
      }
    ],
    indexes: [
      "CREATE INDEX idx_navigation_ticks_route ON navigation_ticks (route)",
      "CREATE INDEX idx_navigation_ticks_route_timestamp ON navigation_ticks (route, timestamp)"
    ],
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
  });

  app.save(navigationTicks);
}, (app) => {
  try {
    const nt = app.findCollectionByNameOrId("navigation_ticks");
    app.delete(nt);
  } catch (e) {}

  try {
    const nr = app.findCollectionByNameOrId("navigation_routes");
    app.delete(nr);
  } catch (e) {}
});
