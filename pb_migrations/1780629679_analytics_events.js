/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const placeSearchEvents = new Collection({
    name: "place_search_events",
    type: "base",
    fields: [
      {
        name: "user",
        type: "relation",
        collectionId: "_pb_users_auth_",
        cascadeDelete: false,
        maxSelect: 1,
      },
      {
        name: "source",
        type: "text",
        required: true,
      },
      {
        name: "target",
        type: "text",
      },
      {
        name: "query",
        type: "text",
        required: true,
      },
      {
        name: "normalized_query",
        type: "text",
      },
      {
        name: "limit",
        type: "number",
      },
      {
        name: "result_count",
        type: "number",
      },
      {
        name: "selected_place_id",
        type: "text",
      },
      {
        name: "selected_place_name",
        type: "text",
      },
      {
        name: "metadata",
        type: "json",
      },
      {
        name: "client_session_id",
        type: "text",
      },
      {
        name: "client_event_id",
        type: "text",
      },
      {
        name: "occurred_at",
        type: "date",
        required: true,
      }
    ],
    indexes: [
      "CREATE INDEX idx_place_search_events_created ON place_search_events (created)",
      "CREATE INDEX idx_place_search_events_query ON place_search_events (normalized_query)",
      "CREATE INDEX idx_place_search_events_user ON place_search_events (user)"
    ],
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: null,
    deleteRule: null,
  });

  app.save(placeSearchEvents);

  const routeAnalyticsEvents = new Collection({
    name: "route_analytics_events",
    type: "base",
    fields: [
      {
        name: "user",
        type: "relation",
        collectionId: "_pb_users_auth_",
        cascadeDelete: false,
        maxSelect: 1,
      },
      {
        name: "source",
        type: "text",
        required: true,
      },
      {
        name: "event_type",
        type: "text",
        required: true,
      },
      {
        name: "route_type",
        type: "text",
      },
      {
        name: "route_id",
        type: "text",
      },
      {
        name: "start_lat",
        type: "number",
      },
      {
        name: "start_lon",
        type: "number",
      },
      {
        name: "end_lat",
        type: "number",
      },
      {
        name: "end_lon",
        type: "number",
      },
      {
        name: "waypoint_count",
        type: "number",
      },
      {
        name: "total_length_meters",
        type: "number",
      },
      {
        name: "total_weight",
        type: "number",
      },
      {
        name: "segment_count",
        type: "number",
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
        name: "weights",
        type: "json",
      },
      {
        name: "offsets",
        type: "json",
      },
      {
        name: "metadata",
        type: "json",
      },
      {
        name: "client_session_id",
        type: "text",
      },
      {
        name: "client_event_id",
        type: "text",
      },
      {
        name: "occurred_at",
        type: "date",
        required: true,
      }
    ],
    indexes: [
      "CREATE INDEX idx_route_analytics_events_created ON route_analytics_events (created)",
      "CREATE INDEX idx_route_analytics_events_type ON route_analytics_events (event_type)",
      "CREATE INDEX idx_route_analytics_events_route_type ON route_analytics_events (route_type)",
      "CREATE INDEX idx_route_analytics_events_user ON route_analytics_events (user)"
    ],
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: null,
    deleteRule: null,
  });

  app.save(routeAnalyticsEvents);
}, (app) => {
  try {
    const routeAnalyticsEvents = app.findCollectionByNameOrId("route_analytics_events");
    app.delete(routeAnalyticsEvents);
  } catch (e) {}

  try {
    const placeSearchEvents = app.findCollectionByNameOrId("place_search_events");
    app.delete(placeSearchEvents);
  } catch (e) {}
});
