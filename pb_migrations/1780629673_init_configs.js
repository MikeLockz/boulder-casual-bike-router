/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  // Create global_configs collection
  const globalConfigs = new Collection({
    name: "global_configs",
    type: "base",
    fields: [
      {
        name: "key",
        type: "text",
        required: true,
      },
      {
        name: "value",
        type: "json",
        required: true,
      },
      {
        name: "description",
        type: "text",
      }
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_global_configs_key ON global_configs (key)"
    ],
    listRule: "",
    viewRule: "",
    createRule: null,
    updateRule: null,
    deleteRule: null,
  });

  // Create user_configs collection
  const userConfigs = new Collection({
    name: "user_configs",
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
        name: "key",
        type: "text",
        required: true,
      },
      {
        name: "value",
        type: "json",
        required: true,
      }
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_user_configs_user_key ON user_configs (user, key)"
    ],
    listRule: "user = @request.auth.id",
    viewRule: "user = @request.auth.id",
    createRule: "@request.auth.id != '' && user = @request.auth.id",
    updateRule: "@request.auth.id != '' && user = @request.auth.id",
    deleteRule: "@request.auth.id != '' && user = @request.auth.id",
  });

  app.save(globalConfigs);
  app.save(userConfigs);

  // Seed default configurations
  const weightsMetadata = [
    {
      "key": "separated_path",
      "name": "Separated Paths",
      "description": "Multi-use paths, greenways, cycletracks",
      "web_icon": "fa-leaf",
      "ios_icon": "leaf.fill",
      "min": 0.1, "max": 2.0, "step": 0.1,
      "default": 0.5
    },
    {
      "key": "sharrow_minor",
      "name": "Quiet Streets (Sharrows)",
      "description": "Quiet streets with shared lane markings",
      "web_icon": "fa-shield",
      "ios_icon": "shield.fill",
      "min": 0.5, "max": 5.0, "step": 0.1,
      "default": 1.5
    },
    {
      "key": "residential",
      "name": "Residential Streets",
      "description": "Quiet side streets without designations",
      "web_icon": "fa-house",
      "ios_icon": "house.fill",
      "min": 0.5, "max": 5.0, "step": 0.1,
      "default": 0.7
    },
    {
      "key": "sidewalk",
      "name": "Sidewalk Routing",
      "description": "Separate sidewalks, pedestrian ways, slow speed",
      "web_icon": "fa-walking",
      "ios_icon": "figure.walk",
      "min": 1.0, "max": 10.0, "step": 0.5,
      "default": 2.0
    },
    {
      "key": "busy_with_lane",
      "name": "Busy Roads w/ Bike Lane",
      "description": "Secondary/tertiary roads with painted lanes",
      "web_icon": "fa-road",
      "ios_icon": "road.lanes",
      "min": 2.0, "max": 15.0, "step": 0.5,
      "default": 5.0
    },
    {
      "key": "busy_with_sharrow",
      "name": "Busy Roads w/ Sharrows",
      "description": "Busy arterials with sharrows",
      "web_icon": "fa-triangle-exclamation",
      "ios_icon": "exclamationmark.triangle.fill",
      "min": 3.0, "max": 25.0, "step": 1.0,
      "default": 8.0
    },
    {
      "key": "busy_undesignated",
      "name": "Busy Roads (Undesignated)",
      "description": "Arterials without bike infrastructure (feeder-only)",
      "web_icon": "fa-skull-crossbones",
      "ios_icon": "skull.fill",
      "min": 5.0, "max": 50.0, "step": 1.0,
      "default": 15.0
    },
    {
      "key": "sidewalk_forced",
      "name": "Sidewalk on 4+ Lanes",
      "description": "Forced sidewalk walk on 4+ lane roads",
      "web_icon": "fa-ban",
      "ios_icon": "nosign",
      "min": 2.0, "max": 20.0, "step": 1.0,
      "default": 6.0
    },
    {
      "key": "crossing_safe",
      "name": "Safe Crossings",
      "description": "Signalized, beacon-flashing, or bike crossings",
      "web_icon": "fa-traffic-light",
      "ios_icon": "trafficlight.fill",
      "min": 0.5, "max": 3.0, "step": 0.1,
      "default": 1.0
    },
    {
      "key": "crossing_unsafe",
      "name": "Unsignalized Crossings",
      "description": "Unmarked or non-signalized busy street crossings",
      "web_icon": "fa-triangle-exclamation",
      "ios_icon": "exclamationmark.triangle.fill",
      "min": 1.0, "max": 10.0, "step": 0.5,
      "default": 6.0
    },
    {
      "key": "stress_low",
      "name": "Low Stress Modifier",
      "description": "Additional multiplier applied to streets matching Low Traffic Stress overlay",
      "web_icon": "fa-heart-circle-check",
      "ios_icon": "heart.text.square.fill",
      "min": 0.1, "max": 1.5, "step": 0.1,
      "default": 0.7
    },
    {
      "key": "stress_high",
      "name": "High Stress Modifier",
      "description": "Additional penalty applied to streets matching High Traffic Stress overlay",
      "web_icon": "fa-circle-exclamation",
      "ios_icon": "exclamationmark.circle.fill",
      "min": 1.0, "max": 10.0, "step": 0.5,
      "default": 2.0
    },
    {
      "key": "offstreet_multiuse",
      "name": "Multi-Use Path Modifier",
      "description": "Additional multiplier applied to off-street Multi-Use Paths",
      "web_icon": "fa-tree-city",
      "ios_icon": "tree.fill",
      "min": 0.1, "max": 1.5, "step": 0.1,
      "default": 0.8
    },
    {
      "key": "ebike_restricted",
      "name": "E-Bike Prohibited Penalty",
      "description": "Additional penalty applied if e-bikes are prohibited on the path",
      "web_icon": "fa-bolt-lightning",
      "ios_icon": "bolt.fill",
      "min": 1.0, "max": 10.0, "step": 0.5,
      "default": 1.0
    }
  ];

  const routePresets = [
    {
      "name": "North Boulder ➔ Iris Ave",
      "desc": "Cedar Ave to 28th St & Iris",
      "start": [40.028446, -105.281088],
      "end": [40.038662, -105.263851],
      "waypoints": [],
      "route_type": null
    },
    {
      "name": "CU Campus ➔ North Park",
      "desc": "Broadway Path & residential streets",
      "start": [40.007, -105.263],
      "end": [40.028, -105.283],
      "waypoints": [],
      "route_type": null
    },
    {
      "name": "Valmont Park ➔ Pearl Street Mall",
      "desc": "Using off-street multi-use paths",
      "start": [40.030, -105.234],
      "end": [40.018, -105.279],
      "waypoints": [],
      "route_type": null
    },
    {
      "name": "Table Mesa ➔ CU Campus",
      "desc": "Safe commuting corridors",
      "start": [39.986, -105.262],
      "end": [40.007, -105.263],
      "waypoints": [],
      "route_type": null
    },
    {
      "name": "Boulder B-180 Loop",
      "desc": "12 mi scenic loop (Valmont Park)",
      "start": [40.030, -105.234],
      "end": [40.030, -105.234],
      "waypoints": [
        [40.033, -105.253],
        [40.038, -105.263],
        [40.028, -105.281],
        [40.028, -105.283],
        [40.021, -105.291],
        [40.015, -105.292],
        [40.014, -105.275],
        [40.015, -105.253]
      ],
      "route_type": "b180"
    },
    {
      "name": "Boulder B-360 Loop",
      "desc": "24 mi grand loop (Valmont Park)",
      "start": [40.030, -105.234],
      "end": [40.030, -105.234],
      "waypoints": [
        [40.034, -105.225],
        [40.052, -105.207],
        [40.054, -105.228],
        [40.040, -105.249],
        [40.046, -105.265],
        [40.060, -105.275],
        [40.039, -105.289],
        [40.028, -105.289],
        [40.015, -105.292],
        [39.998, -105.283],
        [39.991, -105.263],
        [39.986, -105.238],
        [39.981, -105.233],
        [39.998, -105.228],
        [40.030, -105.210]
      ],
      "route_type": "b360"
    }
  ];

  const gcRecord1 = new Record(globalConfigs, {
    key: "weights",
    value: weightsMetadata,
    description: "Routing Weights Metadata"
  });

  const gcRecord2 = new Record(globalConfigs, {
    key: "presets",
    value: routePresets,
    description: "Dynamic Route Presets"
  });

  app.save(gcRecord1);
  app.save(gcRecord2);
}, (app) => {
  try {
    const gc = app.findCollectionByNameOrId("global_configs");
    app.delete(gc);
  } catch (e) {}

  try {
    const uc = app.findCollectionByNameOrId("user_configs");
    app.delete(uc);
  } catch (e) {}
});
