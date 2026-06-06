// Boulder Casual Bike Router
// Frontend logic using Leaflet.js

// Determine the API base URL dynamically based on dev vs prod environment
const API_BASE = (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1")
    ? "http://localhost:3001"
    : "";

// Initial Map Settings
const BOULDER_CO = [40.015, -105.270];
const ZOOM_LEVEL = 13;

let map;
let startMarker = null;
let endMarker = null;
let routeSegments = [];
let waypointMarkers = [];
let currentWaypoints = [];
let allCrossings = [];
let activeCrossingMarkers = [];
let bikeRoutesLayer = null;
let cachedBikeRoutesGeoJSON = null;
let inspectModeActive = false;
let inspectHighlightLayer = null;

const OFFICIAL_ROUTE_COLORS = {
    "Multi-Use Path": "#00e676",
    "Bike Park Path": "#00e676",
    "Protected Bike Lane": "#00e5ff",
    "Separated Bike Lane": "#00e5ff",
    "Contra Flow Bike Lane": "#00e5ff",
    "On-Street Bike Lane": "#2979ff",
    "Designated Bike Route": "#b388ff",
    "Bikeable Shoulder": "#90a4ae"
};

// Infrastructure type to color mapping
const INFRA_COLORS = {
    "separated_path": "#00e676",      // Emerald Green
    "residential": "#81c784",         // Muted Light Green
    "sharrow_minor": "#ffb300",       // Amber
    "sidewalk": "#00e5ff",            // Cyan
    "busy_with_lane": "#ff5722",      // Deep Orange
    "busy_with_sharrow": "#ff1744",   // Crimson/Red
    "busy_undesignated": "#9c27b0",   // Purple
    "sidewalk_forced": "#e91e63",     // Magenta
    "crossing_safe": "#00bfa5",       // Emerald Teal
    "crossing_unsafe": "#ff9100"      // Coral Orange
};

const OFFICIAL_CUES = {
    b180: [
        "Start at Valmont Bike Park (home base).",
        "Head west on Valmont Road path.",
        "Turn north on 30th St path, then west on Glenwood Drive.",
        "Turn north on Folsom St path to Iris Ave.",
        "Head west on Iris Ave path to Broadway.",
        "Turn south on Broadway path to Cedar Ave.",
        "Head west on Cedar Ave (residential street) to North Boulder Park.",
        "Turn south on 9th St to Mapleton Ave, then head west.",
        "Turn south on 4th St / 5th St to Pine St, then west to 3rd St.",
        "Head south on 3rd St to Canyon Blvd (Canyon path).",
        "Go west on Canyon path to Eben G. Fine Park.",
        "Route east along the scenic Boulder Creek Path back to 30th St.",
        "Turn north on 30th St path to Valmont Road.",
        "Head east on Valmont Road path to finish back at Valmont Bike Park."
    ],
    b360: [
        "Start at Valmont Bike Park.",
        "Head east on Valmont Road path to the Cottonwood Trail.",
        "Take Cottonwood Trail heading northeast under Foothills Parkway.",
        "Follow Cottonwood Trail west along the creek all the way to Jay Road.",
        "Head west on Jay Road bike lanes to Diagonal Highway Path.",
        "Turn southwest on Diagonal Highway Path to 47th St / Kalmia Ave.",
        "Go west on Kalmia Ave to 26th St, then north to Elks Club Rd.",
        "Take the Foothills Trail heading west/north around Wonderland Lake.",
        "Ride south from Wonderland Lake along the Foothills Trail to Linden Ave.",
        "Head south on 4th St (residential greenstreet corridor) to Cedar Ave.",
        "Go west on Cedar Ave to 3rd St, then south to Mapleton Ave.",
        "Turn west on Mapleton Ave to 1st St, then south to Canyon Blvd.",
        "Take Canyon path west to Eben G. Fine Park.",
        "Head south from Eben G. Fine Park on 9th St / 12th St to Chautauqua Park.",
        "Go east from Chautauqua on Baseline Rd path / 20th St to Moorhead Ave.",
        "Head south on Moorhead Ave to Martin Park / Bear Creek Path.",
        "Take Bear Creek Path heading east under US 36 to Foothills Parkway Path.",
        "Go south along Foothills Parkway Path to Bobolink Trailhead.",
        "Take South Boulder Creek Trail north through East Boulder Community Park.",
        "Continue north along South Boulder Creek Trail to Valmont Road.",
        "Head west on Valmont Road path to finish back at Valmont Bike Park."
    ]
};

let DEFAULT_WEIGHTS = {
    "separated_path": 0.5,
    "sharrow_minor": 1.5,
    "sidewalk": 2.0,
    "residential": 0.7,
    "busy_with_lane": 5.0,
    "busy_with_sharrow": 8.0,
    "busy_undesignated": 15.0,
    "sidewalk_forced": 6.0,
    "crossing_safe": 1.0,
    "crossing_unsafe": 6.0,
    "stress_low": 0.7,
    "stress_high": 2.0,
    "offstreet_multiuse": 0.8,
    "ebike_restricted": 1.0
};

let SYSTEM_DEFAULT_WEIGHTS = {};
const ROUTE_TUNING_PROFILES_KEY = "boulder_route_tuning_profiles";
const ACTIVE_ROUTE_TUNING_PROFILE_KEY = "boulder_active_route_tuning_profile_id";
let routeTuningProfiles = [];
let activeRouteTuningProfileId = localStorage.getItem(ACTIVE_ROUTE_TUNING_PROFILE_KEY) || "";


// Initialize app when DOM loads
document.addEventListener("DOMContentLoaded", async () => {
    initMap();
    await loadBackendConfig();
    initDebugMode();
    initWelcomeModal();
    initializeHistoryDetailControls();
    loadCrossings();
    loadPlaygrounds();
    initAuth();
    updateLocateButtonVisuals();
});

// Load dynamic presets and weight metadata from backend configuration API
async function loadBackendConfig() {
    try {
        const response = await fetch(`${API_BASE}/api/config`);
        const config = await response.json();
        
        // 1. Populate weights metadata and override defaults
        config.weights.forEach(w => {
            DEFAULT_WEIGHTS[w.key] = w.default;
            SYSTEM_DEFAULT_WEIGHTS[w.key] = w.default;
        });

        // 2. Render sliders dynamically
        const slidersContainer = document.getElementById("sliders-container");
        if (slidersContainer) {
            slidersContainer.innerHTML = "";
            config.weights.forEach(w => {
                const group = document.createElement("div");
                group.className = "weight-group";
                
                // Keep class colors aligned with INFRA_COLORS keys
                const colorClass = w.key.replace(/_/g, "-");
                
                group.innerHTML = `
                    <div class="weight-label">
                        <span><i class="fa-solid ${w.web_icon} text-${colorClass}"></i> ${w.name}</span>
                        <span id="val-${w.key}" class="weight-value">${w.default.toFixed(1)}x</span>
                    </div>
                    <input type="range" id="weight-${w.key}" min="${w.min}" max="${w.max}" step="${w.step}" value="${w.default}">
                    <span class="subtext">${w.description}</span>
                `;
                slidersContainer.appendChild(group);
            });
        }

        // 3. Render presets dynamically
        const presetList = document.getElementById("preset-list");
        if (presetList) {
            presetList.innerHTML = "";
            config.presets.forEach(p => {
                const btn = document.createElement("button");
                btn.className = "preset-item";
                btn.setAttribute("data-start", p.start.join(","));
                btn.setAttribute("data-end", p.end.join(","));
                if (p.waypoints && p.waypoints.length > 0) {
                    btn.setAttribute("data-waypoints", p.waypoints.map(wp => wp.join(",")).join(";"));
                }
                if (p.route_type) {
                    btn.setAttribute("data-route-type", p.route_type);
                }

                btn.innerHTML = `
                    <span class="preset-name">${p.route_type ? '<i class="fa-solid fa-arrows-spin"></i> ' : ''}${p.name}</span>
                    <span class="preset-desc">${p.desc}</span>
                `;
                presetList.appendChild(btn);
            });
        }
        
        // Initialize sliders and listeners
        initSliders();
        initEventListeners();
        await loadRouteTuningProfiles();
        console.log("Successfully loaded backend dynamic configurations.");
        
    } catch (err) {
        console.warn("Failed to load dynamic backend configurations. Using hardcoded web fallbacks:", err);
        // Fallback to local rendering of original layout if server is down
        fallbackLocalRendering();
    }
}

// Fallback in case python backend is offline on startup
function fallbackLocalRendering() {
    // 1. Render default sliders locally
    const slidersContainer = document.getElementById("sliders-container");
    if (slidersContainer) {
        const fallbacks = [
            { key: "separated_path", name: "Separated Paths", desc: "Multi-use paths, greenways, cycletracks", icon: "fa-leaf", min: 0.1, max: 2.0, step: 0.1, val: 0.5 },
            { key: "sharrow_minor", name: "Quiet Streets (Sharrows)", desc: "Quiet streets with shared lane markings", icon: "fa-shield", min: 0.5, max: 5.0, step: 0.1, val: 1.5 },
            { key: "residential", name: "Residential Streets", desc: "Quiet side streets without designations", icon: "fa-house", min: 0.5, max: 5.0, step: 0.1, val: 0.7 },
            { key: "sidewalk", name: "Sidewalk Routing", desc: "Separate sidewalks, pedestrian ways, slow speed", icon: "fa-walking", min: 1.0, max: 10.0, step: 0.5, val: 2.0 },
            { key: "busy_with_lane", name: "Busy Roads w/ Bike Lane", desc: "Secondary/tertiary roads with painted lanes", icon: "fa-road", min: 2.0, max: 15.0, step: 0.5, val: 5.0 },
            { key: "busy_with_sharrow", name: "Busy Roads w/ Sharrows", desc: "Busy arterials with sharrows", icon: "fa-triangle-exclamation", min: 3.0, max: 25.0, step: 1.0, val: 8.0 },
            { key: "busy_undesignated", name: "Busy Roads (Undesignated)", desc: "Arterials without bike infrastructure (feeder-only)", icon: "fa-skull-crossbones", min: 5.0, max: 50.0, step: 1.0, val: 15.0 },
            { key: "sidewalk_forced", name: "Sidewalk on 4+ Lanes", desc: "Forced sidewalk walk on 4+ lane roads", icon: "fa-ban", min: 2.0, max: 20.0, step: 1.0, val: 6.0 },
            { key: "crossing_safe", name: "Safe Crossings", desc: "Signalized, beacon-flashing, or bike crossings", icon: "fa-traffic-light", min: 0.5, max: 3.0, step: 0.1, val: 1.0 },
            { key: "crossing_unsafe", name: "Unsignalized Crossings", desc: "Unmarked or non-signalized busy street crossings", icon: "fa-triangle-exclamation", min: 1.0, max: 10.0, step: 0.5, val: 6.0 },
            { key: "stress_low", name: "Low Stress Modifier", desc: "Additional multiplier applied to low stress roads", icon: "fa-heart-circle-check", min: 0.1, max: 1.5, step: 0.1, val: 0.7 },
            { key: "stress_high", name: "High Stress Modifier", desc: "Additional penalty applied to high stress roads", icon: "fa-circle-exclamation", min: 1.0, max: 10.0, step: 0.5, val: 2.0 },
            { key: "offstreet_multiuse", name: "Multi-Use Path Modifier", desc: "Additional multiplier applied to off-street paths", icon: "fa-tree-city", min: 0.1, max: 1.5, step: 0.1, val: 0.8 },
            { key: "ebike_restricted", name: "E-Bike Prohibited Penalty", desc: "Additional penalty applied if e-bikes are prohibited", icon: "fa-bolt-lightning", min: 1.0, max: 10.0, step: 0.5, val: 1.0 }
        ];
        slidersContainer.innerHTML = "";
        fallbacks.forEach(w => {
            DEFAULT_WEIGHTS[w.key] = w.val;
            SYSTEM_DEFAULT_WEIGHTS[w.key] = w.val;
            const group = document.createElement("div");
            group.className = "weight-group";
            const colorClass = w.key.replace(/_/g, "-");
            group.innerHTML = `
                <div class="weight-label">
                    <span><i class="fa-solid ${w.icon} text-${colorClass}"></i> ${w.name}</span>
                    <span id="val-${w.key}" class="weight-value">${w.val.toFixed(1)}x</span>
                </div>
                <input type="range" id="weight-${w.key}" min="${w.min}" max="${w.max}" step="${w.step}" value="${w.val}">
                <span class="subtext">${w.desc}</span>
            `;
            slidersContainer.appendChild(group);
        });
    }

    // 2. Render default presets locally
    const presetList = document.getElementById("preset-list");
    if (presetList) {
        const presets = [
            { name: "North Boulder ➔ Iris Ave", desc: "Cedar Ave to 28th St & Iris", start: [40.028446, -105.281088], end: [40.038662, -105.263851], waypoints: [], route_type: null },
            { name: "CU Campus ➔ North Park", desc: "Broadway Path & residential streets", start: [40.007, -105.263], end: [40.028, -105.283], waypoints: [], route_type: null },
            { name: "Valmont Park ➔ Pearl Street Mall", desc: "Using off-street paths", start: [40.030, -105.234], end: [40.018, -105.279], waypoints: [], route_type: null },
            { name: "Table Mesa ➔ CU Campus", desc: "Safe commuting corridors", start: [39.986, -105.262], end: [40.007, -105.263], waypoints: [], route_type: null },
            { name: "Boulder B-180 Loop", desc: "12 mi scenic loop (Valmont Park)", start: [40.030, -105.234], end: [40.030, -105.234], waypoints: [[40.033,-105.253],[40.038,-105.263],[40.028,-105.281],[40.028,-105.283],[40.021,-105.291],[40.015,-105.292],[40.014,-105.275],[40.015,-105.253]], route_type: "b180" },
            { name: "Boulder B-360 Loop", desc: "24 mi grand loop (Valmont Park)", start: [40.030, -105.234], end: [40.030, -105.234], waypoints: [[40.034,-105.225],[40.052,-105.207],[40.054,-105.228],[40.040,-105.249],[40.046,-105.265],[40.060,-105.275],[40.039,-105.289],[40.028,-105.289],[40.015,-105.292],[39.998,-105.283],[39.991,-105.263],[39.986,-105.238],[39.981,-105.233],[39.998,-105.228],[40.030,-105.210]], route_type: "b360" }
        ];
        presetList.innerHTML = "";
        presets.forEach(p => {
            const btn = document.createElement("button");
            btn.className = "preset-item";
            btn.setAttribute("data-start", p.start.join(","));
            btn.setAttribute("data-end", p.end.join(","));
            if (p.waypoints.length > 0) btn.setAttribute("data-waypoints", p.waypoints.map(wp => wp.join(",")).join(";"));
            if (p.route_type) btn.setAttribute("data-route-type", p.route_type);
            btn.innerHTML = `
                <span class="preset-name">${p.route_type ? '<i class="fa-solid fa-arrows-spin"></i> ' : ''}${p.name}</span>
                <span class="preset-desc">${p.desc}</span>
            `;
            presetList.appendChild(btn);
        });
    }
    initSliders();
    initEventListeners();
    loadRouteTuningProfiles();
}

// Initialize Leaflet Map
function initMap() {
    map = L.map("map").setView(BOULDER_CO, ZOOM_LEVEL);

    // CartoDB Dark Matter tile layer for premium dark aesthetics
    L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
        subdomains: "abcd",
        maxZoom: 20
    }).addTo(map);

    // Map Click Listener
    map.on("click", onMapClick);
}

// Map Click Handler: Set Start / Destination
function onMapClick(e) {
    const latlng = e.latlng;

    // Inspector intercepts: toggle mode OR shift+click (always available)
    if (inspectModeActive || (e.originalEvent && e.originalEvent.shiftKey)) {
        inspectEdge(latlng);
        return;
    }

    if (!startMarker) {
        // Set Start marker
        startMarker = L.marker(latlng, {
            draggable: true,
            icon: createCustomIcon("green")
        }).addTo(map);
        
        startMarker.bindPopup("<strong>Start Point</strong><br>Drag to move").openPopup();
        startMarker.on("dragend", calculateRoute);
        updatePlaygroundStartText("Custom Start");
        
    } else if (!endMarker) {
        // Set Destination marker
        endMarker = L.marker(latlng, {
            draggable: true,
            icon: createCustomIcon("red")
        }).addTo(map);
        
        endMarker.bindPopup("<strong>Destination</strong><br>Drag to move").openPopup();
        endMarker.on("dragend", calculateRoute);
        
        // Calculate route once both are set
        calculateRoute();
    } else {
        // Reset and set new start
        clearRoute();
        startMarker = L.marker(latlng, {
            draggable: true,
            icon: createCustomIcon("green")
        }).addTo(map);
        startMarker.bindPopup("<strong>Start Point</strong>").openPopup();
        startMarker.on("dragend", calculateRoute);
        updatePlaygroundStartText("Custom Start");
    }
}

// Create customized SVG markers for premium UI
function createCustomIcon(color) {
    const hexColor = color === "green" ? "#00e676" : "#ff1744";
    const svgHtml = `
        <svg width="30" height="42" viewBox="0 0 30 42" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M15 0C6.71573 0 0 6.71573 0 15C0 26.25 15 42 15 42C15 42 30 26.25 30 15C30 6.71573 23.2843 0 15 0ZM15 22C11.134 22 8 18.866 8 15C8 11.134 11.134 8 15 8C18.866 8 22 11.134 22 15C22 18.866 18.866 22 15 22Z" 
                  fill="${hexColor}" 
                  stroke="#ffffff" 
                  stroke-width="1.5"
                  filter="drop-shadow(0px 2px 5px rgba(0,0,0,0.5))"/>
            <circle cx="15" cy="15" r="5" fill="#ffffff" />
        </svg>
    `;
    return L.divIcon({
        html: svgHtml,
        iconSize: [30, 42],
        iconAnchor: [15, 42],
        popupAnchor: color === "green" ? [-30, -35] : [30, -35],
        className: "custom-marker-icon"
    });
}

// Initialize sliders to show values and trigger live routing recalculation
function initSliders() {
    Object.keys(DEFAULT_WEIGHTS).forEach(key => {
        const slider = document.getElementById(`weight-${key}`);
        const valueSpan = document.getElementById(`val-${key}`);
        
        if (slider && valueSpan) {
            slider.addEventListener("input", (e) => {
                const val = parseFloat(e.target.value).toFixed(1);
                valueSpan.textContent = `${val}x`;
                
                // Recalculate route on the fly when sliders are adjusted
                if (startMarker && endMarker) {
                    debouncedCalculateRoute();
                }
            });
        }
    });

}

// Event Listeners for action buttons, presets, and toggle panels
function initEventListeners() {
    // Reset weights
    document.getElementById("btn-reset").addEventListener("click", resetUserWeights);

    // Save to Profile
    const saveProfileBtn = document.getElementById("btn-save-profile");
    if (saveProfileBtn) {
        saveProfileBtn.addEventListener("click", saveActiveRouteTuningProfile);
    }

    const profileSelect = document.getElementById("route-profile-select");
    if (profileSelect) {
        profileSelect.addEventListener("change", () => {
            activeRouteTuningProfileId = profileSelect.value;
            localStorage.setItem(ACTIVE_ROUTE_TUNING_PROFILE_KEY, activeRouteTuningProfileId);
            const profile = routeTuningProfiles.find(item => item.local_id === activeRouteTuningProfileId && !item.deleted);
            applyRouteTuningProfile(profile);
            if (startMarker && endMarker) {
                calculateRoute();
            }
        });
    }

    const newProfileBtn = document.getElementById("btn-new-route-profile");
    if (newProfileBtn) {
        newProfileBtn.addEventListener("click", createRouteTuningProfile);
    }

    const deleteProfileBtn = document.getElementById("btn-delete-route-profile");
    if (deleteProfileBtn) {
        deleteProfileBtn.addEventListener("click", deleteActiveRouteTuningProfile);
    }

    const defaultProfileBtn = document.getElementById("btn-set-default-route-profile");
    if (defaultProfileBtn) {
        defaultProfileBtn.addEventListener("click", setActiveRouteTuningProfileDefault);
    }

    // Panel toggle button floating
    const panelToggle = document.getElementById("panel-toggle");
    const controlPanel = document.getElementById("control-panel");
    const closeBtn = document.getElementById("btn-close-panel");
    const grabBar = document.getElementById("grab-bar");
    const panelHeader = document.querySelector(".panel-header");

    // Set initial toggle button visibility based on panel state
    if (controlPanel.classList.contains("collapsed")) {
        panelToggle.classList.remove("hidden");
    } else {
        panelToggle.classList.add("hidden");
    }

    function togglePanel() {
        controlPanel.classList.toggle("collapsed");
        if (controlPanel.classList.contains("collapsed")) {
            panelToggle.classList.remove("hidden");
        } else {
            panelToggle.classList.add("hidden");
        }
        // Force Leaflet map resize layout update
        setTimeout(() => {
            map.invalidateSize();
            if (routeSegments.length > 0) {
                const group = new L.featureGroup(routeSegments);
                map.fitBounds(group.getBounds(), getFitBoundsOptions());
            }
        }, 300);
    }

    panelToggle.addEventListener("click", togglePanel);
    closeBtn.addEventListener("click", togglePanel);

    // Grab bar & header tap to expand on mobile
    const expandPanel = () => {
        if (controlPanel.classList.contains("collapsed")) {
            togglePanel();
        }
    };
    grabBar.addEventListener("click", expandPanel);
    panelHeader.addEventListener("click", (e) => {
        // Only trigger if we click the header itself, not the close button inside it
        if (!e.target.closest(".close-panel-btn")) {
            expandPanel();
        }
    });

    // Preset route selections
    const presets = document.querySelectorAll(".preset-item");
    const playgroundSelect = document.getElementById("playground-select");

    presets.forEach(preset => {
        preset.addEventListener("click", () => {
            presets.forEach(p => p.classList.remove("active"));
            preset.classList.add("active");

            // Reset playground select when a preset is chosen
            if (playgroundSelect) {
                playgroundSelect.selectedIndex = 0;
            }

            // Update playground section title and description to match preset's starting location
            const presetName = preset.querySelector(".preset-name").textContent;
            let startName = "Cedar Ave";
            if (presetName.includes("➔")) {
                startName = presetName.split("➔")[0].trim();
            } else if (presetName.includes("Loop")) {
                startName = "Valmont Park";
            }
            updatePlaygroundStartText(startName);

            const startStr = preset.getAttribute("data-start");
            const endStr = preset.getAttribute("data-end");
            const waypointsStr = preset.getAttribute("data-waypoints");
            
            const startCoords = startStr.split(",").map(Number);
            const endCoords = endStr.split(",").map(Number);
            
            let waypoints = [];
            if (waypointsStr) {
                waypoints = waypointsStr.split(";").map(wp => wp.split(",").map(Number));
            }

            const routeType = preset.getAttribute("data-route-type");
            loadPresetRoute(startCoords, endCoords, waypoints, routeType);
        });
    });

    // Playground dropdown selection
    if (playgroundSelect) {
        playgroundSelect.addEventListener("change", (e) => {
            // Remove active highlight from presets when a playground is selected
            presets.forEach(p => p.classList.remove("active"));

            // Route from startMarker if set, otherwise default to Cedar Ave
            let startCoords = [40.028446, -105.281088]; // Default Cedar Ave location
            if (startMarker) {
                const latlng = startMarker.getLatLng();
                startCoords = [latlng.lat, latlng.lng];
            }
            const endStr = e.target.value;
            const endCoords = endStr.split(",").map(Number);

            loadPresetRoute(startCoords, endCoords);
        });
    }

    // Start Navigation button
    const navBtn = document.getElementById("btn-start-nav");
    if (navBtn) {
        navBtn.addEventListener("click", () => {
            if (window.lastRouteSegments && window.lastRouteSegments.length > 0) {
                Navigation.start(window.lastRouteSegments, map);
            } else {
                alert("No route to navigate. Compute a route first.");
            }
        });
    }

    // Layer toggles
    const officialRoutesToggle = document.getElementById("toggle-official-routes");
    if (officialRoutesToggle) {
        officialRoutesToggle.addEventListener("change", handleOfficialRoutesToggle);
    }

    // Floating Locate Me Button
    const locateBtn = document.getElementById("btn-locate-map");
    if (locateBtn) {
        locateBtn.addEventListener("click", () => {
            onDemandLocate();
        });
    }

    // Location Settings Help Modal Tabs
    const tabBtns = document.querySelectorAll("#location-settings-modal .tab-btn");
    tabBtns.forEach(btn => {
        btn.addEventListener("click", () => {
            tabBtns.forEach(b => b.classList.remove("active"));
            document.querySelectorAll("#location-settings-modal .tab-content").forEach(c => c.classList.remove("active"));
            
            btn.classList.add("active");
            const targetTab = btn.getAttribute("data-tab");
            const content = document.getElementById(`tab-content-${targetTab}`);
            if (content) content.classList.add("active");
        });
    });

    // Location Settings Help Modal Actions
    const retryBtn = document.getElementById("btn-settings-retry");
    if (retryBtn) {
        retryBtn.addEventListener("click", () => {
            onDemandLocate(true);
        });
    }

    const settingsCloseBtn = document.getElementById("btn-settings-close");
    if (settingsCloseBtn) {
        settingsCloseBtn.addEventListener("click", () => {
            document.getElementById("location-settings-modal").classList.add("hidden");
        });
    }
}

// Get current weights from sliders
function getWeightsFromSliders() {
    const weights = {};
    Object.keys(DEFAULT_WEIGHTS).forEach(key => {
        const slider = document.getElementById(`weight-${key}`);
        if (slider) {
            weights[key] = parseFloat(slider.value);
        } else {
            weights[key] = DEFAULT_WEIGHTS[key];
        }
    });
    return weights;
}

function getRouteOffsetsFromEditor() {
    const profile = routeTuningProfiles.find(item => item.local_id === activeRouteTuningProfileId && !item.deleted);
    return profile?.offsets || {};
}

function setRouteOffsetsEditor(offsets = {}) {
    void offsets;
}

function getAuthSession() {
    const storedAuth = localStorage.getItem("pocketbase_auth");
    if (!storedAuth) return null;
    try {
        const authData = JSON.parse(storedAuth);
        if (authData && authData.token && authData.record) return authData;
    } catch (e) {}
    return null;
}

function getCurrentUserId() {
    const authData = getAuthSession();
    return authData?.record?.id || null;
}

function isCloudSyncActiveForProfiles() {
    const authData = getAuthSession();
    const syncSetting = localStorage.getItem("cloud_sync_enabled");
    return Boolean(authData && (syncSetting === null || syncSetting === "true"));
}

function getLocalRouteTuningProfiles(includeDeleted = false) {
    try {
        const profiles = JSON.parse(localStorage.getItem(ROUTE_TUNING_PROFILES_KEY) || "[]");
        return Array.isArray(profiles)
            ? profiles.filter(profile => includeDeleted || !profile.deleted)
            : [];
    } catch (e) {
        return [];
    }
}

function saveLocalRouteTuningProfiles(profiles) {
    localStorage.setItem(ROUTE_TUNING_PROFILES_KEY, JSON.stringify(profiles));
}

function normalizeRouteTuningProfile(profile, userId = getCurrentUserId()) {
    const id = profile.local_id || profile.localId || profile.id || `local-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    return {
        local_id: id,
        id,
        server_id: profile.server_id || (profile.id && !String(profile.id).startsWith("local-") ? profile.id : null),
        name: profile.name || "Routing Profile",
        weights: profile.weights || {},
        offsets: profile.offsets || {},
        is_default: Boolean(profile.is_default ?? profile.isDefault),
        userId: profile.userId ?? profile.user ?? userId ?? null,
        synced: Boolean(profile.synced),
        deleted: Boolean(profile.deleted),
        updated_at: profile.updated_at || profile.updated || new Date().toISOString()
    };
}

function getVisibleRouteTuningProfiles() {
    const userId = getCurrentUserId();
    return routeTuningProfiles.filter(profile => {
        if (profile.deleted) return false;
        if (userId) return profile.userId === userId || profile.userId === null;
        return profile.userId === null;
    });
}

function applyWeightsToSliders(weights = {}) {
    Object.keys(DEFAULT_WEIGHTS).forEach(key => {
        const value = weights[key] ?? SYSTEM_DEFAULT_WEIGHTS[key] ?? DEFAULT_WEIGHTS[key];
        const slider = document.getElementById(`weight-${key}`);
        const valueSpan = document.getElementById(`val-${key}`);
        if (slider) slider.value = value;
        if (valueSpan) valueSpan.textContent = `${Number(value).toFixed(1)}x`;
    });
}

function applyRouteTuningProfile(profile) {
    if (!profile) {
        applyWeightsToSliders(SYSTEM_DEFAULT_WEIGHTS);
        setRouteOffsetsEditor({});
        return;
    }
    applyWeightsToSliders(profile.weights || {});
    setRouteOffsetsEditor(profile.offsets || {});
}

function renderRouteTuningProfiles() {
    const select = document.getElementById("route-profile-select");
    if (!select) return;
    const visibleProfiles = getVisibleRouteTuningProfiles();
    select.innerHTML = '<option value="">System Defaults</option>';
    visibleProfiles.forEach(profile => {
        const option = document.createElement("option");
        option.value = profile.local_id;
        option.textContent = `${profile.is_default ? "★ " : ""}${profile.name}${profile.synced ? "" : " • local"}`;
        select.appendChild(option);
    });
    const hasActive = visibleProfiles.some(profile => profile.local_id === activeRouteTuningProfileId);
    if (!hasActive) {
        const defaultProfile = visibleProfiles.find(profile => profile.is_default);
        activeRouteTuningProfileId = defaultProfile?.local_id || "";
        localStorage.setItem(ACTIVE_ROUTE_TUNING_PROFILE_KEY, activeRouteTuningProfileId);
    }
    select.value = activeRouteTuningProfileId;
}

async function loadRouteTuningProfiles() {
    const userId = getCurrentUserId();
    const localProfiles = getLocalRouteTuningProfiles(true).map(profile => normalizeRouteTuningProfile(profile, profile.userId ?? userId));
    let merged = localProfiles;

    if (isCloudSyncActiveForProfiles()) {
        await syncPendingRouteTuningProfiles();
        const authData = getAuthSession();
        try {
            const resp = await fetch(`${API_BASE}/api/route-tuning-profiles`, {
                headers: { "Authorization": `Bearer ${authData.token}` }
            });
            if (resp.ok) {
                const serverProfiles = await resp.json();
                const byKey = new Map(localProfiles.map(profile => [profile.server_id || profile.local_id, profile]));
                serverProfiles.forEach(serverProfile => {
                    const localMatch = byKey.get(serverProfile.id);
                    const normalized = normalizeRouteTuningProfile({
                        ...serverProfile,
                        local_id: localMatch?.local_id || serverProfile.id,
                        server_id: serverProfile.id,
                        userId,
                        synced: true
                    }, userId);
                    byKey.set(serverProfile.id, normalized);
                });
                merged = Array.from(byKey.values());
                saveLocalRouteTuningProfiles(merged);
            }
        } catch (err) {
            console.error("[RouteProfiles] Failed to load profiles from server:", err);
        }
    }

    routeTuningProfiles = merged;
    renderRouteTuningProfiles();
    const active = routeTuningProfiles.find(profile => profile.local_id === activeRouteTuningProfileId && !profile.deleted);
    applyRouteTuningProfile(active);
}

async function persistRouteTuningProfile(profile) {
    const profiles = getLocalRouteTuningProfiles(true);
    const idx = profiles.findIndex(item => (item.local_id || item.id) === profile.local_id);
    if (idx >= 0) profiles[idx] = profile;
    else profiles.unshift(profile);
    saveLocalRouteTuningProfiles(profiles);
    routeTuningProfiles = profiles;

    if (isCloudSyncActiveForProfiles()) {
        await syncPendingRouteTuningProfiles();
    }
    renderRouteTuningProfiles();
}

async function createRouteTuningProfile() {
    const name = prompt("Profile name", "Custom Routing Profile");
    if (!name || !name.trim()) return;
    const userId = getCurrentUserId();
    const profile = normalizeRouteTuningProfile({
        local_id: `local-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        name: name.trim(),
        weights: getWeightsFromSliders(),
        offsets: {},
        is_default: getVisibleRouteTuningProfiles().length === 0,
        userId,
        synced: false
    }, userId);
    activeRouteTuningProfileId = profile.local_id;
    localStorage.setItem(ACTIVE_ROUTE_TUNING_PROFILE_KEY, activeRouteTuningProfileId);
    await persistRouteTuningProfile(profile);
    showToast("Routing profile created.");
}

async function saveActiveRouteTuningProfile() {
    let profile = routeTuningProfiles.find(item => item.local_id === activeRouteTuningProfileId && !item.deleted);
    if (!profile) {
        await createRouteTuningProfile();
        return;
    }
    profile = {
        ...profile,
        weights: getWeightsFromSliders(),
        offsets: profile.offsets || {},
        synced: false,
        updated_at: new Date().toISOString()
    };
    await persistRouteTuningProfile(profile);
    showToast(isCloudSyncActiveForProfiles() ? "Routing profile saved and synced." : "Routing profile saved locally.");
}

async function deleteActiveRouteTuningProfile() {
    const profile = routeTuningProfiles.find(item => item.local_id === activeRouteTuningProfileId && !item.deleted);
    if (!profile) return;
    if (!confirm(`Delete routing profile "${profile.name}"?`)) return;

    const profiles = getLocalRouteTuningProfiles(true);
    const idx = profiles.findIndex(item => (item.local_id || item.id) === profile.local_id);
    if (idx >= 0) {
        if (profile.server_id && !isCloudSyncActiveForProfiles()) {
            profiles[idx] = { ...profile, deleted: true, synced: false, operation: "delete" };
        } else {
            profiles.splice(idx, 1);
        }
    }
    saveLocalRouteTuningProfiles(profiles);
    routeTuningProfiles = profiles;

    if (isCloudSyncActiveForProfiles() && profile.server_id) {
        await fetch(`${API_BASE}/api/route-tuning-profiles/${profile.server_id}`, {
            method: "DELETE",
            headers: { "Authorization": `Bearer ${getAuthSession().token}` }
        });
    }

    activeRouteTuningProfileId = "";
    localStorage.setItem(ACTIVE_ROUTE_TUNING_PROFILE_KEY, "");
    renderRouteTuningProfiles();
    applyRouteTuningProfile(null);
    showToast("Routing profile deleted.");
}

async function setActiveRouteTuningProfileDefault() {
    const active = routeTuningProfiles.find(item => item.local_id === activeRouteTuningProfileId && !item.deleted);
    if (!active) return;
    routeTuningProfiles = routeTuningProfiles.map(profile => ({
        ...profile,
        is_default: profile.local_id === active.local_id,
        synced: profile.local_id === active.local_id ? false : profile.synced
    }));
    saveLocalRouteTuningProfiles(routeTuningProfiles);
    if (isCloudSyncActiveForProfiles()) await syncPendingRouteTuningProfiles();
    renderRouteTuningProfiles();
    showToast("Default routing profile updated.");
}

async function syncPendingRouteTuningProfiles() {
    if (!isCloudSyncActiveForProfiles()) return;
    const authData = getAuthSession();
    const userId = authData.record.id;
    const profiles = getLocalRouteTuningProfiles(true).map(profile => normalizeRouteTuningProfile(profile, profile.userId ?? userId));
    const pending = profiles.filter(profile => profile.userId === userId || profile.userId === null).filter(profile => !profile.synced || profile.deleted);
    if (pending.length === 0) return;

    const payload = {
        profiles: pending.map(profile => ({
            local_id: profile.local_id,
            server_id: profile.server_id,
            name: profile.name,
            weights: profile.weights || {},
            offsets: profile.offsets || {},
            is_default: profile.is_default,
            operation: profile.deleted ? "delete" : "upsert"
        }))
    };

    try {
        const resp = await fetch(`${API_BASE}/api/route-tuning-profiles/sync`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${authData.token}`
            },
            body: JSON.stringify(payload)
        });
        if (!resp.ok) {
            console.error("[RouteProfiles] Sync failed with status:", resp.status);
            return;
        }
        const data = await resp.json();
        const syncedMap = {};
        (data.synced_profiles || []).forEach(item => {
            syncedMap[item.local_id] = item.server_id;
        });
        const deletedIds = new Set((data.deleted_profiles || []).map(item => item.local_id));
        const updatedProfiles = profiles
            .filter(profile => !deletedIds.has(profile.local_id))
            .map(profile => {
                if (syncedMap[profile.local_id]) {
                    return {
                        ...profile,
                        server_id: syncedMap[profile.local_id],
                        userId,
                        synced: true,
                        deleted: false
                    };
                }
                return profile;
            });
        saveLocalRouteTuningProfiles(updatedProfiles);
        routeTuningProfiles = updatedProfiles;
    } catch (err) {
        console.error("[RouteProfiles] Sync error:", err);
    }
}

// Clear drawn routes and markers
function clearRoute() {
    if (startMarker) {
        map.removeLayer(startMarker);
        startMarker = null;
    }
    if (endMarker) {
        map.removeLayer(endMarker);
        endMarker = null;
    }
    clearPolylines();
    clearWaypoints();
    clearActiveCrossings();
    lockWeights(false);
    document.getElementById("route-info").classList.add("hidden");
    
    const tbtContainer = document.getElementById("turn-by-turn-container");
    if (tbtContainer) {
        tbtContainer.classList.add("hidden");
        document.getElementById("turn-by-turn-list").innerHTML = "";
    }
    updatePlaygroundStartText("Cedar Ave");
    clearInspectHighlight();

    // Reset history states
    if (typeof clearHistoryMapLayers === "function") {
        clearHistoryMapLayers();
    }
    const costContainer = document.getElementById("info-cost-container");
    if (costContainer) {
        costContainer.style.display = "";
    }
    const startNavBtn = document.getElementById("btn-start-nav");
    if (startNavBtn) {
        startNavBtn.style.display = "";
    }
    document.querySelectorAll(".history-item").forEach(x => x.classList.remove("active"));
}

function clearWaypoints() {
    waypointMarkers.forEach(marker => map.removeLayer(marker));
    waypointMarkers = [];
    currentWaypoints = [];
}

function clearPolylines() {
    routeSegments.forEach(seg => map.removeLayer(seg));
    routeSegments = [];
}

// Debounce helper to avoid flooding API requests on rapid slider movements
let debounceTimeout;
function debouncedCalculateRoute() {
    clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(calculateRoute, 150);
}

// Call backend API to compute route and render path on map
async function calculateRoute() {
    if (!startMarker || !endMarker) return;

    const startLatLng = startMarker.getLatLng();
    const endLatLng = endMarker.getLatLng();
    const weights = getWeightsFromSliders();

    const requestBody = {
        start_lat: startLatLng.lat,
        start_lon: startLatLng.lng,
        end_lat: endLatLng.lat,
        end_lon: endLatLng.lng,
        waypoints: currentWaypoints,
        weights: weights,
        offsets: getRouteOffsetsFromEditor()
    };

    try {
        const response = await fetch(`${API_BASE}/api/route`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(requestBody)
        });

        const data = await response.json();

        if (data.error) {
            alert("Routing error: " + data.error);
            clearPolylines();
            return;
        }

        // Draw path segments
        drawRoute(data.segments);

        // Store segments for navigation module
        window.lastRouteSegments = data.segments;

        // Update Route Info Panel
        const distanceMiles = (data.total_length_meters / 1609.34).toFixed(2);
        const costScore = data.total_weight.toFixed(0);
        
        document.getElementById("info-distance").textContent = `${distanceMiles} mi`;
        document.getElementById("info-cost").textContent = costScore;
        document.getElementById("route-info").classList.remove("hidden");

        // Render turn-by-turn directions dynamically
        renderTurnByTurn(null, data.segments);

    } catch (err) {
        console.error("Failed to fetch route:", err);
        alert("Unable to connect to routing server. Make sure the backend routing service is running.");
    }
}

// Draw route segments on the Leaflet map with type-specific color styling
function drawRoute(segments) {
    clearPolylines();

    segments.forEach(segment => {
        const color = INFRA_COLORS[segment.type] || "#ffffff";
        const isCrossing = segment.type === "crossing_safe" || segment.type === "crossing_unsafe";
        const polylineOptions = {
            color: color,
            weight: 6,
            opacity: 0.85,
            lineCap: "round",
            lineJoin: "round",
            className: "path-glow"
        };
        if (isCrossing) {
            polylineOptions.dashArray = "8, 8";
        }
        const polyline = L.polyline(segment.coords, polylineOptions).addTo(map);

        // Simple interactive tooltip for each segment
        const formattedType = segment.type.replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase());
        const lengthMeters = segment.length.toFixed(0);
        
        let stressBadge = "";
        if (segment.bikestress === "Low") {
            stressBadge = `<br><span style="color: #64ffda; font-weight: bold;"><i class="fa-solid fa-heart-circle-check"></i> Low Stress Overlay Match</span>`;
        } else if (segment.bikestress === "High") {
            stressBadge = `<br><span style="color: #e040fb; font-weight: bold;"><i class="fa-solid fa-circle-exclamation"></i> High Stress Overlay Match</span>`;
        }
        
        let offstreetBadge = "";
        if (segment.offstreet_type === "Multi-Use Path") {
            offstreetBadge = `<br><span style="color: #00b0ff; font-weight: bold;"><i class="fa-solid fa-tree-city"></i> Off-Street Multi-Use Path</span>`;
        }
        
        let restrictionBadge = "";
        if (segment.bicycles_allowed === "No") {
            restrictionBadge = `<br><span style="color: #ff1744; font-weight: bold;"><i class="fa-solid fa-ban"></i> Bicycles Forbidden!</span>`;
        } else if (segment.ebike_allowed === "No") {
            restrictionBadge = `<br><span style="color: #ff9100; font-weight: bold;"><i class="fa-solid fa-bolt-lightning"></i> E-Bikes Prohibited</span>`;
        }
        
        polyline.bindTooltip(`
            <strong>${segment.name}</strong><br>
            Type: ${formattedType}${stressBadge}${offstreetBadge}${restrictionBadge}<br>
            Length: ${lengthMeters}m (Cost Mult: ${segment.multiplier.toFixed(1)}x)
        `, {
            sticky: true,
            opacity: 0.9
        });

        // Highlight segment on hover
        polyline.on("mouseover", function() {
            polyline.setStyle({
                weight: 9,
                opacity: 1.0
            });
        });
        polyline.on("mouseout", function() {
            polyline.setStyle({
                weight: 6,
                opacity: 0.85
            });
        });

        routeSegments.push(polyline);
    });

    // Automatically fit map bounds to the route
    if (routeSegments.length > 0) {
        const group = new L.featureGroup(routeSegments);
        map.fitBounds(group.getBounds(), getFitBoundsOptions());
    }
    
    // Show crossing signals near the route path
    showCrossingsNearRoute(segments);
}

// Load a preset route by coordinates
async function loadPresetRoute(startCoords, endCoords, waypoints = [], routeType = null) {
    // Clear existing route markers and waypoints
    if (startMarker) map.removeLayer(startMarker);
    if (endMarker) map.removeLayer(endMarker);
    clearPolylines();
    clearWaypoints();

    // Check if this is an official exact route
    if (routeType === "b180" || routeType === "b360") {
        lockWeights(true);
        
        try {
            const response = await fetch(`official_${routeType}.json`);
            const data = await response.json();
            
            drawOfficialGeoJSON(data, routeType);
            
            // Set Start marker statically (non-draggable)
            startMarker = L.marker([40.030, -105.234], {
                draggable: false,
                icon: createCustomIcon("green")
            }).addTo(map);
            startMarker.bindPopup("<strong>Valmont Bike Park</strong><br>Start of Official Tour");
            
            // Set Destination marker statically (non-draggable)
            endMarker = L.marker([40.030, -105.234], {
                draggable: false,
                icon: createCustomIcon("red")
            }).addTo(map);
            endMarker.bindPopup("<strong>Valmont Bike Park</strong><br>End of Official Tour");
            
            // Render turn-by-turn directions
            renderTurnByTurn(routeType);
            
            // Display official distance
            const distanceMiles = routeType === "b180" ? 13.66 : 29.29;
            document.getElementById("info-distance").textContent = `${distanceMiles} mi`;
            document.getElementById("info-cost").textContent = "N/A (Official Track)";
            document.getElementById("route-info").classList.remove("hidden");
            
        } catch (err) {
            console.error("Failed to load official route GeoJSON:", err);
            alert("Error loading official route file from public sources.");
        }
        return;
    }

    // Otherwise, unlock weights and use dynamic router
    lockWeights(false);
    currentWaypoints = waypoints;

    const startLatLng = L.latLng(startCoords[0], startCoords[1]);
    const endLatLng = L.latLng(endCoords[0], endCoords[1]);

    // Set Start
    startMarker = L.marker(startLatLng, {
        draggable: true,
        icon: createCustomIcon("green")
    }).addTo(map);
    startMarker.bindPopup("<strong>Start Point</strong><br>Drag to move");
    startMarker.on("dragend", calculateRoute);

    // Set Destination
    endMarker = L.marker(endLatLng, {
        draggable: true,
        icon: createCustomIcon("red")
    }).addTo(map);
    endMarker.bindPopup("<strong>Destination</strong><br>Drag to move");
    endMarker.on("dragend", calculateRoute);

    // Draw waypoints as small, semi-transparent circles
    waypoints.forEach((wp, index) => {
        const marker = L.circleMarker([wp[0], wp[1]], {
            radius: 6,
            fillColor: "#ffb300", // Amber highlight
            color: "#ffffff",
            weight: 2,
            opacity: 0.9,
            fillOpacity: 0.6
        }).addTo(map);
        marker.bindTooltip(`Waypoint ${index + 1}: ${wp[0].toFixed(3)}, ${wp[1].toFixed(3)}`, {
            direction: "top",
            offset: [0, -5]
        });
        waypointMarkers.push(marker);
    });

    // Render official turn-by-turn directions if applicable
    renderTurnByTurn(routeType);

    // Trigger path calculation
    calculateRoute();
}

function drawOfficialGeoJSON(data, routeType) {
    clearPolylines();
    
    const geojsonLayer = L.geoJSON(data, {
        style: function (feature) {
            return {
                color: "#64ffda", // Neon teal accent highlight for official routes
                weight: 6,
                opacity: 0.85,
                lineCap: "round",
                lineJoin: "round",
                className: "path-glow"
            };
        }
    }).addTo(map);

    geojsonLayer.eachLayer(layer => {
        const name = routeType === "b180" ? "B-180 Official Loop" : "B-360 Official Loop";
        layer.bindTooltip(`
            <strong>${name}</strong><br>
            Exact path from public GIS sources
        `, {
            sticky: true,
            opacity: 0.9
        });

        // Highlight segment on hover
        layer.on("mouseover", function() {
            layer.setStyle({
                weight: 9,
                opacity: 1.0
            });
        });
        layer.on("mouseout", function() {
            layer.setStyle({
                weight: 6,
                opacity: 0.85
            });
        });

        routeSegments.push(layer);
    });

    // Fit map bounds to the exact route
    if (routeSegments.length > 0) {
        const group = new L.featureGroup(routeSegments);
        map.fitBounds(group.getBounds(), getFitBoundsOptions());
    }
}

function lockWeights(lock) {
    const sliders = document.querySelectorAll("#sec-weights input[type='range']");
    const resetButton = document.getElementById("btn-reset");
    const weightsSection = document.getElementById("sec-weights");
    
    sliders.forEach(slider => {
        slider.disabled = lock;
    });
    if (resetButton) {
        resetButton.disabled = lock;
    }
    
    if (lock) {
        weightsSection.classList.add("weights-locked");
        if (!document.getElementById("weights-lock-msg")) {
            const msg = document.createElement("div");
            msg.id = "weights-lock-msg";
            msg.className = "lock-message";
            msg.innerHTML = `<i class="fa-solid fa-lock"></i> Sliders locked to official route paths`;
            weightsSection.querySelector(".section-content").prepend(msg);
        }
    } else {
        weightsSection.classList.remove("weights-locked");
        const msg = document.getElementById("weights-lock-msg");
        if (msg) msg.remove();
    }
}

function renderTurnByTurn(routeType, segments = null) {
    const tbtContainer = document.getElementById("turn-by-turn-container");
    const tbtList = document.getElementById("turn-by-turn-list");
    
    if (!tbtContainer || !tbtList) return;
    
    let cues = [];
    if (routeType && OFFICIAL_CUES[routeType]) {
        cues = OFFICIAL_CUES[routeType];
    } else if (segments && segments.length > 0) {
        cues = generateDynamicCues(segments);
    }
    
    if (cues.length > 0) {
        tbtList.innerHTML = "";
        cues.forEach((cue, index) => {
            const li = document.createElement("li");
            li.className = "cue-item";
            li.innerHTML = `
                <span class="cue-number">${index + 1}</span>
                <span class="cue-text">${cue}</span>
            `;
            tbtList.appendChild(li);
        });
        tbtContainer.classList.remove("hidden");
    } else {
        tbtContainer.classList.add("hidden");
        tbtList.innerHTML = "";
    }
}

// Calculate bearing in degrees between two coordinates
function getBearing(pt1, pt2) {
    if (!pt1 || !pt2) return 0;
    const lat1 = pt1[0] * Math.PI / 180;
    const lat2 = pt2[0] * Math.PI / 180;
    const dLon = (pt2[1] - pt1[1]) * Math.PI / 180;

    const y = Math.sin(dLon) * Math.cos(lat2);
    const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
    return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
}

// Format distance in a human-readable way (feet if < 0.1 mi, otherwise miles)
function formatDistance(meters) {
    const miles = meters / 1609.34;
    if (miles < 0.1) {
        const feet = Math.round(meters * 3.28084);
        const roundedFeet = Math.round(feet / 10) * 10;
        return `${roundedFeet > 0 ? roundedFeet : 10} ft`;
    } else {
        return `${miles.toFixed(2)} mi`;
    }
}

// Generate dynamic cues from route segments
function generateDynamicCues(segments) {
    if (!segments || segments.length === 0) return [];

    // 1. Group segments by street name
    const grouped = [];
    segments.forEach(seg => {
        const last = grouped[grouped.length - 1];
        if (last && last.name === seg.name) {
            last.length += seg.length;
            if (seg.coords && seg.coords.length > 1) {
                last.coords.push(seg.coords[1]);
            }
        } else {
            grouped.push({
                name: seg.name || "Unnamed Path",
                length: seg.length,
                coords: seg.coords ? [...seg.coords] : []
            });
        }
    });

    const cues = [];
    cues.push(`Start your route heading on ${grouped[0].name}.`);

    // 2. Generate turn actions between grouped legs
    for (let i = 0; i < grouped.length - 1; i++) {
        const legA = grouped[i];
        const legB = grouped[i + 1];

        // Get final bearing of Leg A
        const coordsA = legA.coords;
        const ptA1 = coordsA[coordsA.length - 2] || coordsA[0];
        const ptA2 = coordsA[coordsA.length - 1];
        const bearingA = getBearing(ptA1, ptA2);

        // Get initial bearing of Leg B
        const coordsB = legB.coords;
        const ptB1 = coordsB[0];
        const ptB2 = coordsB[1] || coordsB[0];
        const bearingB = getBearing(ptB1, ptB2);

        // Calculate turn angle difference
        let diff = bearingB - bearingA;
        if (diff > 180) diff -= 360;
        if (diff < -180) diff += 360;

        // Classify turn direction
        let action = "Continue onto";
        if (diff > 45 && diff <= 135) action = "Turn right onto";
        else if (diff > 135) action = "Make a sharp right onto";
        else if (diff > 15 && diff <= 45) action = "Slight right onto";
        else if (diff < -45 && diff >= -135) action = "Turn left onto";
        else if (diff < -135) action = "Make a sharp left onto";
        else if (diff < -15 && diff >= -45) action = "Slight left onto";
        else action = "Go straight onto";

        const distStr = formatDistance(legA.length);
        cues.push(`Go for ${distStr}, then ${action} ${legB.name}.`);
    }

    const lastLeg = grouped[grouped.length - 1];
    const lastDistStr = formatDistance(lastLeg.length);
    cues.push(`Go for ${lastDistStr} to arrive at your destination.`);

    return cues;
}

let userGPSMarker = null;

// Boulder bounding box definitions
const BOULDER_BOUNDS = {
    minLat: 39.95,
    maxLat: 40.15,
    minLon: -105.35,
    maxLon: -105.15
};

// Check if coordinates are in/near Boulder
function isWithinBoulder(lat, lon) {
    return lat >= BOULDER_BOUNDS.minLat && lat <= BOULDER_BOUNDS.maxLat &&
           lon >= BOULDER_BOUNDS.minLon && lon <= BOULDER_BOUNDS.maxLon;
}

// Sleek Toast Notification
function showToast(message) {
    let toast = document.getElementById('nav-toast');
    if (!toast) {
        toast = document.createElement('div');
        toast.id = 'nav-toast';
        toast.className = 'nav-toast';
        document.body.appendChild(toast);
    }
    toast.textContent = message;
    toast.classList.add('visible');
    setTimeout(() => toast.classList.remove('visible'), 4000);
}

// Dynamic update of the playgrounds start location text
function updatePlaygroundStartText(text) {
    const titleEl = document.getElementById("playground-start-title");
    const descEl = document.getElementById("playground-start-desc");
    if (titleEl) titleEl.textContent = text;
    if (descEl) descEl.textContent = text;
}

// Show user GPS dot with pulsing animation on Leaflet map
function showUserGPSDot(lat, lon) {
    if (userGPSMarker) {
        map.removeLayer(userGPSMarker);
    }
    const dotHtml = `
        <div class="nav-user-dot-outer">
            <div class="nav-user-dot-inner"></div>
        </div>
    `;
    userGPSMarker = L.marker([lat, lon], {
        icon: L.divIcon({
            html: dotHtml,
            iconSize: [24, 24],
            iconAnchor: [12, 12],
            className: 'nav-user-marker'
        }),
        zIndexOffset: 9999,
        interactive: false
    }).addTo(map);
}

// Dismiss welcome modal with a smooth fade-out transition
function dismissWelcomeModal() {
    const overlay = document.getElementById("welcome-modal-overlay");
    if (!overlay) return;
    overlay.classList.add("fade-out");
    setTimeout(() => {
        overlay.classList.add("hidden");
    }, 400);
}

// Check if we should show the welcome modal based on permissions or localStorage
async function checkExistingPermission() {
    // If the user has explicitly denied/blocked location before, bypass modal and go to demo
    if (localStorage.getItem("geolocation_denied") === "true") {
        return false;
    }
    
    if (navigator.permissions && navigator.permissions.query) {
        try {
            const status = await navigator.permissions.query({ name: 'geolocation' });
            if (status.state === 'granted' || status.state === 'denied') {
                return false;
            }
        } catch (e) {
            console.warn("Permissions API query for geolocation is not supported or failed:", e);
        }
    }
    
    // Fallback to checking localStorage flag
    const hasGrantedBefore = localStorage.getItem("geolocation_granted") === "true";
    return !hasGrantedBefore;
}

// Automatically locate the user in the background (used when permission was already granted)
function autoLocateUser() {
    const mockState = localStorage.getItem("mock_geolocation_state") || "default";
    if (mockState === "default" && !window.isSecureContext) {
        prepopulatePoints();
        return;
    }
    showToast("Locating your starting position...");
    
    if ("geolocation" in navigator) {
        navigator.geolocation.getCurrentPosition(
            (position) => {
                const lat = position.coords.latitude;
                const lon = position.coords.longitude;
                
                // Keep the flag updated
                localStorage.setItem("geolocation_granted", "true");
                localStorage.removeItem("geolocation_denied");
                updateLocateButtonVisuals();

                if (isWithinBoulder(lat, lon)) {
                    map.setView([lat, lon], 15);
                    
                    if (startMarker) {
                        map.removeLayer(startMarker);
                    }
                    
                    startMarker = L.marker([lat, lon], {
                        draggable: true,
                        icon: createCustomIcon("green")
                    }).addTo(map);
                    
                    startMarker.bindPopup("<strong>Start Point (Your Location)</strong><br>Drag to adjust starting position").openPopup();
                    startMarker.on("dragend", calculateRoute);

                    showUserGPSDot(lat, lon);
                    updatePlaygroundStartText("Current Location");
                    showToast("Start point set to your location.");
                } else {
                    showToast("Your location is outside Boulder. Loading demo route instead.");
                    prepopulatePoints();
                }
            },
            (error) => {
                console.warn("Auto-location failed:", error.message);
                // Clear the granted flag if it failed due to permission revoking
                if (error.code === error.PERMISSION_DENIED) {
                    localStorage.removeItem("geolocation_granted");
                    localStorage.setItem("geolocation_denied", "true");
                    updateLocateButtonVisuals();
                }
                prepopulatePoints();
            },
            {
                enableHighAccuracy: true,
                maximumAge: 10000,
                timeout: 8000
            }
        );
    } else {
        prepopulatePoints();
    }
}

// Request location permission and center map (used when user interacts with modal)
function requestLocation() {
    const mockState = localStorage.getItem("mock_geolocation_state") || "default";
    if (mockState === "default" && !window.isSecureContext) {
        dismissWelcomeModal();
        showToast("Insecure Context: Geolocation is disabled on HTTP. Please use HTTPS.");
        prepopulatePoints();
        return;
    }
    const overlay = document.getElementById("welcome-modal-overlay");
    if ("geolocation" in navigator) {
        navigator.geolocation.getCurrentPosition(
            (position) => {
                const lat = position.coords.latitude;
                const lon = position.coords.longitude;

                dismissWelcomeModal();
                
                // Store success state in localStorage
                localStorage.setItem("geolocation_granted", "true");
                localStorage.removeItem("geolocation_denied");
                updateLocateButtonVisuals();

                if (isWithinBoulder(lat, lon)) {
                    map.setView([lat, lon], 15);
                    
                    if (startMarker) {
                        map.removeLayer(startMarker);
                    }
                    
                    startMarker = L.marker([lat, lon], {
                        draggable: true,
                        icon: createCustomIcon("green")
                    }).addTo(map);
                    
                    startMarker.bindPopup("<strong>Start Point (Your Location)</strong><br>Drag to adjust starting position").openPopup();
                    startMarker.on("dragend", calculateRoute);

                    showUserGPSDot(lat, lon);
                    updatePlaygroundStartText("Current Location");

                    showToast("Starting point set to your location. Click on the map to set a destination!");
                } else {
                    showToast("Your location is outside Boulder routing zone. Loading demo route instead.");
                    prepopulatePoints();
                }
            },
            (error) => {
                console.warn("Geolocation request failed:", error.message);
                dismissWelcomeModal();
                
                // Store denied state if blocked
                if (error.code === error.PERMISSION_DENIED) {
                    localStorage.setItem("geolocation_denied", "true");
                    localStorage.removeItem("geolocation_granted");
                    
                    // Show settings instructions helper modal
                    showLocationSettingsModal();
                }
                
                let errorMsg = "Location access denied. Loading demo route.";
                if (error.code === error.TIMEOUT) {
                    errorMsg = "Location request timed out. Loading demo route.";
                } else if (error.code === error.POSITION_UNAVAILABLE) {
                    errorMsg = "Location unavailable. Loading demo route.";
                }
                
                showToast(errorMsg);
                prepopulatePoints();
            },
            {
                enableHighAccuracy: true,
                maximumAge: 10000,
                timeout: 8000
            }
        );
    } else {
        dismissWelcomeModal();
        showToast("Geolocation is not supported by this browser. Loading demo route.");
        prepopulatePoints();
    }
}

// Show the custom location settings instructions modal and auto-select browser tab
function showLocationSettingsModal() {
    const settingsModal = document.getElementById("location-settings-modal");
    if (settingsModal) {
        // Detect mobile platform to preset correct tab
        const userAgent = navigator.userAgent || navigator.vendor || window.opera;
        const iosTab = document.querySelector("#location-settings-modal .tab-btn[data-tab='ios']");
        const androidTab = document.querySelector("#location-settings-modal .tab-btn[data-tab='android']");
        
        if (/iPad|iPhone|iPod/.test(userAgent) && !window.MSStream) {
            if (iosTab) iosTab.click();
        } else if (/Android/.test(userAgent)) {
            if (androidTab) androidTab.click();
        }
        
        settingsModal.classList.remove("hidden");
    }
}

// On-demand geolocation request flow
function onDemandLocate(isRetry = false) {
    const locateBtn = document.getElementById("btn-locate-map");
    const settingsModal = document.getElementById("location-settings-modal");
    
    if (locateBtn) {
        locateBtn.classList.add("locating");
    }
    
    const mockState = localStorage.getItem("mock_geolocation_state") || "default";
    if (mockState === "default" && !window.isSecureContext) {
        showToast("Insecure Context: Geolocation is disabled on HTTP. Please use HTTPS or localhost.");
        if (locateBtn) locateBtn.classList.remove("locating");
        return;
    }
    
    showToast(isRetry ? "Checking permissions..." : "Acquiring location...");

    if ("geolocation" in navigator) {
        navigator.geolocation.getCurrentPosition(
            (position) => {
                const lat = position.coords.latitude;
                const lon = position.coords.longitude;

                if (locateBtn) locateBtn.classList.remove("locating");
                if (settingsModal) settingsModal.classList.add("hidden");
                
                // Store success state
                localStorage.setItem("geolocation_granted", "true");
                localStorage.removeItem("geolocation_denied");
                updateLocateButtonVisuals();

                if (isWithinBoulder(lat, lon)) {
                    map.setView([lat, lon], 15);
                    
                    if (startMarker) {
                        map.removeLayer(startMarker);
                    }
                    
                    startMarker = L.marker([lat, lon], {
                        draggable: true,
                        icon: createCustomIcon("green")
                    }).addTo(map);
                    
                    startMarker.bindPopup("<strong>Start Point (Your Location)</strong><br>Drag to adjust starting position").openPopup();
                    startMarker.on("dragend", calculateRoute);

                    showUserGPSDot(lat, lon);
                    updatePlaygroundStartText("Current Location");
                    
                    // Re-calculate route if endMarker is set
                    if (endMarker) {
                        calculateRoute();
                    }

                    showToast("Start point set to your location.");
                } else {
                    showToast("Your location is outside Boulder. Location dot shown.");
                    showUserGPSDot(lat, lon);
                }
            },
            (error) => {
                if (locateBtn) locateBtn.classList.remove("locating");
                
                if (error.code === error.PERMISSION_DENIED) {
                    localStorage.setItem("geolocation_denied", "true");
                    localStorage.removeItem("geolocation_granted");
                    updateLocateButtonVisuals();
                    
                    // Show settings instructions helper modal
                    showLocationSettingsModal();
                    showToast("Location permission denied. Please allow in settings.");
                } else {
                    let errorMsg = "Could not acquire location.";
                    if (error.code === error.TIMEOUT) {
                        errorMsg = "Location request timed out.";
                    } else if (error.code === error.POSITION_UNAVAILABLE) {
                        errorMsg = "Location unavailable.";
                    }
                    showToast(errorMsg);
                }
            },
            {
                enableHighAccuracy: true,
                maximumAge: 10000,
                timeout: 8000
            }
        );
    } else {
        if (locateBtn) locateBtn.classList.remove("locating");
        showToast("Geolocation is not supported by your browser.");
    }
}

// Initialize welcome modal event listeners and display flow
function initWelcomeModal() {
    const overlay = document.getElementById("welcome-modal-overlay");
    const btnUseLocation = document.getElementById("btn-use-location");
    const btnUseDemo = document.getElementById("btn-use-demo");
    const loadingEl = document.getElementById("location-loading");
    const actionsEl = document.querySelector(".welcome-modal-actions");

    if (!overlay) return;

    // Check if we should bypass the welcome modal
    checkExistingPermission().then((shouldShow) => {
        if (shouldShow) {
            // Show welcome modal (starts hidden by default in HTML to prevent layouts flashing)
            overlay.classList.remove("hidden");
        } else {
            // Bypass modal: check if we should auto-locate or just load demo
            const hasGrantedBefore = localStorage.getItem("geolocation_granted") === "true";
            
            if (navigator.permissions && navigator.permissions.query) {
                navigator.permissions.query({ name: 'geolocation' }).then((status) => {
                    if (status.state === 'granted') {
                        autoLocateUser();
                    } else {
                        prepopulatePoints();
                    }
                }).catch(() => {
                    if (hasGrantedBefore) {
                        autoLocateUser();
                    } else {
                        prepopulatePoints();
                    }
                });
            } else {
                if (hasGrantedBefore) {
                    autoLocateUser();
                } else {
                    prepopulatePoints();
                }
            }
        }
    });

    // "Explore Demo Tour" click handler
    btnUseDemo.addEventListener("click", () => {
        dismissWelcomeModal();
        prepopulatePoints();
    });

    // "Use Current Location" click handler
    btnUseLocation.addEventListener("click", () => {
        // Toggle view to loading state
        if (actionsEl) actionsEl.classList.add("hidden");
        if (loadingEl) loadingEl.classList.remove("hidden");

        requestLocation();
    });
}

// Prepopulate map with specific start and end coordinates by loading the first preset
function prepopulatePoints() {
    // Automatically trigger click on the first preset item to load default coordinates
    const firstPreset = document.querySelector(".preset-item");
    if (firstPreset) {
        firstPreset.click();
    }
}

// Fetch crossings and cache them on load
async function loadCrossings() {
    try {
        const response = await fetch(`${API_BASE}/api/crossings`);
        allCrossings = await response.json();
        console.log(`Loaded ${allCrossings.length} crossing signals for dynamic route display.`);
    } catch (err) {
        console.error("Failed to load crossings:", err);
    }
}

// Fetch playgrounds and populate the dropdown dynamically on load
async function loadPlaygrounds() {
    const playgroundSelect = document.getElementById("playground-select");
    if (!playgroundSelect) return;
    
    try {
        const response = await fetch(`${API_BASE}/api/playgrounds`);
        const playgrounds = await response.json();
        
        playgrounds.forEach(pg => {
            const option = document.createElement("option");
            option.value = `${pg.lat},${pg.lon}`;
            option.textContent = pg.name;
            playgroundSelect.appendChild(option);
        });
        
        console.log(`Loaded ${playgrounds.length} playgrounds dynamically into the dropdown.`);
    } catch (err) {
        console.error("Failed to load playgrounds:", err);
    }
}

// Clear any crossings currently rendered on the map
function clearActiveCrossings() {
    activeCrossingMarkers.forEach(marker => map.removeLayer(marker));
    activeCrossingMarkers = [];
}

// Calculate the distance in meters between two lat/lon coordinates
function getLatLngDistance(lat1, lon1, lat2, lon2) {
    const dy = (lat2 - lat1) * 111000;
    const dx = (lon2 - lon1) * 111000 * Math.cos(lat1 * Math.PI / 180);
    return Math.sqrt(dx*dx + dy*dy);
}

// Filter and render crossings that are on or near the current route path
function showCrossingsNearRoute(segments) {
    clearActiveCrossings();
    
    // Collect all vertex coordinates of the route
    const routePoints = [];
    segments.forEach(seg => {
        if (seg.coords) {
            seg.coords.forEach(pt => {
                routePoints.push(pt);
            });
        }
    });
    
    if (routePoints.length === 0) return;
    
    // Render crossings within 40 meters of any route point
    allCrossings.forEach(c => {
        let isNear = false;
        for (const pt of routePoints) {
            const dist = getLatLngDistance(c.lat, c.lon, pt[0], pt[1]);
            if (dist <= 40.0) {
                isNear = true;
                break;
            }
        }
        
        if (isNear) {
            const marker = L.marker([c.lat, c.lon], {
                icon: createCrossingIcon(c.crossing_type)
            }).addTo(map);
            
            let tagsHtml = "";
            if (c.tags) {
                tagsHtml = `<div class="popup-tags">` + 
                    Object.entries(c.tags)
                        .map(([k, v]) => `<span class="popup-tag-badge"><strong>${k}</strong>: ${v}</span>`)
                        .join(" ") + 
                    `</div>`;
            }
            
            marker.bindPopup(`
                <div class="crossing-popup">
                    <h3>${c.description}</h3>
                    <p><strong>OSM ID:</strong> ${c.id}</p>
                    <p><strong>Coordinates:</strong> ${c.lat.toFixed(6)}, ${c.lon.toFixed(6)}</p>
                    ${tagsHtml}
                </div>
            `);
            
            activeCrossingMarkers.push(marker);
        }
    });
}

function createCrossingIcon(type) {
    let iconClass, color;
    if (type === "bike_signal") {
        iconClass = "fa-bicycle";
        color = "#00e676"; // Emerald green
    } else if (type === "stop_light") {
        iconClass = "fa-traffic-light";
        color = "#ffb300"; // Yellow/Amber
    } else {
        iconClass = "fa-person-walking";
        color = "#ff1744"; // Red/Coral warning
    }
    
    const html = `
        <div class="crossing-icon-wrapper" style="background-color: ${color};">
            <i class="fa-solid ${iconClass} crossing-fa-icon"></i>
        </div>
    `;
    
    return L.divIcon({
        html: html,
        iconSize: [26, 26],
        iconAnchor: [13, 13],
        className: "crossing-marker-icon"
    });
}

// Toggle logic for the official bike routes layer
async function handleOfficialRoutesToggle(e) {
    const isChecked = e.target.checked;
    const legend = document.getElementById("layer-legend-routes");
    
    if (isChecked) {
        if (legend) legend.classList.remove("hidden");
        await showOfficialRoutes();
    } else {
        if (legend) legend.classList.add("hidden");
        hideOfficialRoutes();
    }
}

// Fetch and draw official bike routes
async function showOfficialRoutes() {
    if (bikeRoutesLayer) {
        map.addLayer(bikeRoutesLayer);
        return;
    }
    
    // If not cached, fetch from API
    if (!cachedBikeRoutesGeoJSON) {
        try {
            console.log("Fetching official bike routes GeoJSON...");
            const response = await fetch(`${API_BASE}/api/bike-routes`);
            cachedBikeRoutesGeoJSON = await response.json();
        } catch (err) {
            console.error("Failed to fetch official bike routes:", err);
            alert("Failed to load official bike routes layer from backend.");
            // Reset toggle
            const toggle = document.getElementById("toggle-official-routes");
            if (toggle) toggle.checked = false;
            const legend = document.getElementById("layer-legend-routes");
            if (legend) legend.classList.add("hidden");
            return;
        }
    }
    
    // Draw GeoJSON layer
    bikeRoutesLayer = L.geoJSON(cachedBikeRoutesGeoJSON, {
        style: function (feature) {
            const type = feature.properties.FACILITYTYPE;
            const color = OFFICIAL_ROUTE_COLORS[type] || "#b0bec5";
            let weight = 3.5;
            
            // Paths get slightly thicker lines
            if (type === "Multi-Use Path" || type === "Bike Park Path") {
                weight = 4.5;
            }
            
            return {
                color: color,
                weight: weight,
                opacity: 0.75,
                lineCap: "round",
                lineJoin: "round"
            };
        },
        onEachFeature: function (feature, layer) {
            const props = feature.properties;
            const cleanType = props.FACILITYTYPE.replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase());
            
            layer.bindTooltip(`
                <strong>${props.name}</strong><br>
                Designation: ${cleanType}
            `, {
                sticky: true,
                opacity: 0.9
            });
            
            // Hover effect
            layer.on("mouseover", function () {
                layer.setStyle({
                    weight: (props.FACILITYTYPE === "Multi-Use Path" || props.FACILITYTYPE === "Bike Park Path") ? 6.5 : 5.5,
                    opacity: 1.0
                });
            });
            
            layer.on("mouseout", function () {
                const type = props.FACILITYTYPE;
                const baseWeight = (type === "Multi-Use Path" || type === "Bike Park Path") ? 4.5 : 3.5;
                layer.setStyle({
                    weight: baseWeight,
                    opacity: 0.75
                });
            });
        }
    });
    
    // Add to map
    bikeRoutesLayer.addTo(map);
}

// Remove official bike routes from map
function hideOfficialRoutes() {
    if (bikeRoutesLayer && map.hasLayer(bikeRoutesLayer)) {
        map.removeLayer(bikeRoutesLayer);
    }
}

// Initialize debug mode based on URL parameter
function initDebugMode() {
    const urlParams = new URLSearchParams(window.location.search);
    const isDebug = urlParams.has("debug");

    const presetInstruction = document.getElementById("preset-instruction");
    const presetList = document.querySelector(".preset-list");
    const weightsSection = document.getElementById("sec-weights");
    const costContainer = document.getElementById("info-cost-container");
    const infoGrid = document.querySelector(".info-grid");
    const wayfindingSubSection = document.querySelector(".wayfinding-sub-section");
    const debugInspectorTool = document.getElementById("debug-inspector-tool");
    const debugPermissionsTool = document.getElementById("debug-permissions-tool");
    const toggleStreetInspector = document.getElementById("toggle-street-inspector");

    if (isDebug) {
        // Show everything for debug mode
        if (presetInstruction) presetInstruction.classList.remove("hidden");
        if (presetList) presetList.classList.remove("hidden");
        if (weightsSection) weightsSection.classList.remove("hidden");
        if (costContainer) costContainer.classList.remove("hidden");
        if (infoGrid) infoGrid.classList.remove("single-column");
        if (debugInspectorTool) debugInspectorTool.classList.remove("hidden");
        if (debugPermissionsTool) debugPermissionsTool.classList.remove("hidden");
        if (wayfindingSubSection) {
            wayfindingSubSection.style.marginTop = "";
            wayfindingSubSection.style.paddingTop = "";
            wayfindingSubSection.style.borderTop = "";
        }
        
        // Listen to inspector switch
        if (toggleStreetInspector) {
            toggleStreetInspector.onchange = (e) => {
                inspectModeActive = e.target.checked;
                if (!inspectModeActive) {
                    clearInspectHighlight();
                } else {
                    showToast("Street Inspector Active. Click any street to inspect.");
                }
            };
        }
    } else {
        // Hide debug elements for normal mode
        if (presetInstruction) presetInstruction.classList.add("hidden");
        if (presetList) presetList.classList.add("hidden");
        if (weightsSection) weightsSection.classList.add("hidden");
        if (costContainer) costContainer.classList.add("hidden");
        if (infoGrid) infoGrid.classList.add("single-column");
        if (debugInspectorTool) debugInspectorTool.classList.add("hidden");
        if (debugPermissionsTool) debugPermissionsTool.classList.add("hidden");
        if (wayfindingSubSection) {
            wayfindingSubSection.style.marginTop = "0";
            wayfindingSubSection.style.paddingTop = "0";
            wayfindingSubSection.style.borderTop = "none";
        }
        inspectModeActive = false;
        if (toggleStreetInspector) toggleStreetInspector.checked = false;
        clearInspectHighlight();
    }

    // Initialize mock permissions selectors
    initMockPermissionsSelectors();
}

// Initialize mock permissions selectors and persist choice in localStorage
function initMockPermissionsSelectors() {
    const geoSelect = document.getElementById("mock-geolocation-state");
    const compassSelect = document.getElementById("mock-compass-state");
    const wakeSelect = document.getElementById("mock-wakelock-state");

    if (geoSelect) {
        geoSelect.value = localStorage.getItem("mock_geolocation_state") || "default";
        geoSelect.addEventListener("change", (e) => {
            localStorage.setItem("mock_geolocation_state", e.target.value);
            showToast("Geolocation mock updated. Reloading page...");
            setTimeout(() => window.location.reload(), 800);
        });
    }

    if (compassSelect) {
        compassSelect.value = localStorage.getItem("mock_compass_state") || "default";
        compassSelect.addEventListener("change", (e) => {
            localStorage.setItem("mock_compass_state", e.target.value);
            showToast("Device compass mock updated. Reloading page...");
            setTimeout(() => window.location.reload(), 800);
        });
    }

    if (wakeSelect) {
        wakeSelect.value = localStorage.getItem("mock_wakelock_state") || "default";
        wakeSelect.addEventListener("change", (e) => {
            localStorage.setItem("mock_wakelock_state", e.target.value);
            showToast("Wake lock mock updated.");
        });
    }
}

// Inspect an edge on the map at the given latlng
async function inspectEdge(latlng) {
    try {
        const response = await fetch(`${API_BASE}/api/inspect-edge?lat=${latlng.lat}&lon=${latlng.lng}`);
        if (!response.ok) {
            const err = await response.json();
            showToast(err.error || "Failed to inspect street segment.");
            return;
        }
        
        const edge = await response.json();
        
        // 1. Draw glowing highlight polyline over the clicked edge segment
        clearInspectHighlight();
        
        inspectHighlightLayer = L.polyline(edge.coords, {
            color: "#ff9100", // Bright amber neon
            weight: 8,
            opacity: 0.9,
            dashArray: "6, 6",
            className: "path-glow",
            lineCap: "round",
            lineJoin: "round"
        }).addTo(map);
        
        // 2. Format popup content
        const formattedType = edge.type.replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase());
        const lengthMeters = edge.length.toFixed(1);
        const osmLink = edge.way_id 
            ? `<a href="https://www.openstreetmap.org/way/${edge.way_id}" target="_blank" style="color: #ffb300; font-weight: bold; text-decoration: none;"><i class="fa-solid fa-arrow-up-right-from-square"></i> OSM Way ${edge.way_id}</a>`
            : `<span style="color: #94a3b8; font-style: italic;">No OSM Way (Connector/Intersection)</span>`;
            
        // Stress Badge
        let stressText = "None Matched";
        let stressColor = "#94a3b8";
        if (edge.bikestress === "Low") {
            stressText = "Low Stress";
            stressColor = "#64ffda";
        } else if (edge.bikestress === "High") {
            stressText = "High Stress";
            stressColor = "#e040fb";
        }
        const stressBadge = `<span style="color: ${stressColor}; font-weight: 600;">${stressText}</span>`;
        
        // Facility type (Boulder GIS)
        let facilityText = edge.facility_type || "None";
        let facilityColor = "#94a3b8";
        const FACILITY_COLORS = {
            "Designated Bike Route": "#00e676",
            "Protected Bike Lane":   "#00e676",
            "Separated Bike Lane":   "#00e676",
            "On-Street Bike Lane":   "#ffb300",
            "Contra Flow Bike Lane": "#ffb300",
            "Bikeable Shoulder":     "#ff9100",
        };
        if (facilityText in FACILITY_COLORS) facilityColor = FACILITY_COLORS[facilityText];
        const facilityBadge = `<span style="color: ${facilityColor}; font-weight: 600;">${facilityText}</span>`;
        
        // Off-street
        const isOffstreet = edge.offstreet_type === "Multi-Use Path";
        const offstreetBadge = `<span style="color: ${isOffstreet ? '#00b0ff' : '#94a3b8'}; font-weight: 600;">${edge.offstreet_type}</span>`;
        
        // Restrictions
        const isBikesAllowed = edge.bicycles_allowed !== "No";
        const isEbikeAllowed = edge.ebike_allowed !== "No";
        const bikesBadge = `<span style="color: ${isBikesAllowed ? '#64ffda' : '#ff1744'}; font-weight: 600;">${edge.bicycles_allowed}</span>`;
        const ebikeBadge = `<span style="color: ${isEbikeAllowed ? '#64ffda' : '#ff9100'}; font-weight: 600;">${edge.ebike_allowed}</span>`;
        
        // Raw OSM tags table
        let tagsHtml = `<div style="margin-top: 8px; font-size: 11px; max-height: 120px; overflow-y: auto; border: 1px solid rgba(255,255,255,0.08); border-radius: 4px; padding: 4px; background: rgba(0,0,0,0.2);">`;
        if (edge.tags && Object.keys(edge.tags).length > 0) {
            tagsHtml += `<table style="width: 100%; border-collapse: collapse; line-height: 1.3;">`;
            for (const [key, value] of Object.entries(edge.tags)) {
                tagsHtml += `
                    <tr style="border-bottom: 1px solid rgba(255,255,255,0.03);">
                        <td style="color: #64ffda; font-weight: 500; padding: 2px 4px; width: 45%; word-break: break-all;">${key}</td>
                        <td style="color: #f8fafc; padding: 2px 4px; word-break: break-all;">${value}</td>
                    </tr>
                `;
            }
            tagsHtml += `</table>`;
        } else {
            tagsHtml += `<span style="color: #94a3b8; font-style: italic; padding: 2px 4px;">No tags available</span>`;
        }
        tagsHtml += `</div>`;
        
        // 3. Open Popup
        L.popup()
            .setLatLng(latlng)
            .setContent(`
                <div class="crossing-popup" style="min-width: 250px;">
                    <h3 style="margin-bottom: 4px; color: #ffb300;"><i class="fa-solid fa-magnifying-glass-location"></i> Inspect Edge</h3>
                    <p style="margin-bottom: 8px; font-size: 12px; font-weight: bold; color: #fff;">${edge.name}</p>
                    <p style="margin-bottom: 8px;">${osmLink}</p>
                    <hr style="border: none; border-top: 1px solid rgba(255,255,255,0.08); margin: 6px 0;">
                    <div style="display: grid; grid-template-columns: auto 1fr; gap: 4px 10px; font-size: 11px;">
                        <span><strong>Base Type:</strong></span> <span style="color: #64ffda;">${formattedType}</span>
                        <span><strong>Boulder GIS:</strong></span> ${facilityBadge}
                        <span><strong>Length:</strong></span> <span>${lengthMeters} m</span>
                        <span><strong>Multiplier:</strong></span> <span style="font-weight: bold; color: #ffb300;">${edge.multiplier.toFixed(2)}x</span>
                        <span><strong>Stress Overlay:</strong></span> ${stressBadge}
                        <span><strong>Off-Street Overlay:</strong></span> ${offstreetBadge}
                        <span><strong>Bicycles Allowed:</strong></span> ${bikesBadge}
                        <span><strong>E-Bikes Allowed:</strong></span> ${ebikeBadge}
                    </div>
                    <hr style="border: none; border-top: 1px solid rgba(255,255,255,0.08); margin: 8px 0 4px 0;">
                    <span style="font-size: 10px; text-transform: uppercase; letter-spacing: 0.5px; color: #94a3b8; font-weight: 600;">OSM Tags:</span>
                    ${tagsHtml}
                </div>
            `)
            .openOn(map);
            
    } catch (err) {
        console.error("Inspector failed:", err);
        showToast("Error inspecting street segment.");
    }
}

// Clear the inspector highlight layer
function clearInspectHighlight() {
    if (inspectHighlightLayer) {
        map.removeLayer(inspectHighlightLayer);
        inspectHighlightLayer = null;
    }
}

// Get dynamic padding options for fitBounds depending on screen size and side panel state
function getFitBoundsOptions() {
    const options = {
        animate: true,
        duration: 0.5
    };
    
    const controlPanel = document.getElementById("control-panel");
    const isMobile = window.innerWidth < 768;
    const isPanelOpen = controlPanel && !controlPanel.classList.contains("collapsed");
    
    if (isPanelOpen) {
        if (isMobile) {
            // On mobile, the panel is at the bottom (max-height 60vh, height auto)
            const panelHeight = controlPanel.offsetHeight || 0;
            options.paddingBottomRight = [15, panelHeight + 15];
            options.paddingTopLeft = [15, 15];
        } else {
            // On laptop/desktop, the panel is on the left (width 380px + 20px offset + gap)
            // Left padding 430px leaves a beautiful view area on the right
            options.paddingTopLeft = [430, 30];
            options.paddingBottomRight = [30, 30];
        }
    } else {
        // If panel is closed/collapsed, use standard uniform padding
        options.padding = [40, 40];
    }
    
    return options;
}

// ====================================
// USER AUTHENTICATION INTEGRATION
// ====================================
let PB_URL = "/pb";
let currentUser = null;

async function initAuth() {
    await detectPocketBaseUrl();
    
    const storedAuth = localStorage.getItem("pocketbase_auth");
    if (storedAuth) {
        try {
            const authData = JSON.parse(storedAuth);
            if (authData && authData.token && authData.record) {
                currentUser = authData.record;
                
                // Set default Cloud Sync settings on load if not defined
                if (localStorage.getItem("cloud_sync_enabled") === null) {
                    localStorage.setItem("cloud_sync_enabled", "true");
                }
                // Auto sync pending local/guest routes on load
                setTimeout(() => syncPendingRoutes(), 500);
                setTimeout(() => loadRouteTuningProfiles(), 500);
            }
        } catch (e) {
            console.error("Failed to parse stored auth session:", e);
            localStorage.removeItem("pocketbase_auth");
        }
    }
    
    updateAuthUI();
    initAuthEventListeners();
}

async function detectPocketBaseUrl() {
    try {
        const resp = await fetch("/pb/api/health", { method: "GET" });
        if (resp.status === 200) {
            PB_URL = "/pb";
            console.log("[Auth] Using Nginx proxied PocketBase route (/pb)");
            return;
        }
    } catch (e) {
        // Failed
    }
    
    if (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1") {
        PB_URL = "http://localhost:8090";
        console.log("[Auth] Nginx proxy not detected. Falling back to direct PocketBase at " + PB_URL);
    }
}

function updateAuthUI() {
    const loggedOutDiv = document.getElementById("auth-logged-out");
    const loggedInDiv = document.getElementById("auth-logged-in");
    const userEmailSpan = document.getElementById("user-display-email");
    
    if (!loggedOutDiv || !loggedInDiv) return;
    
    if (currentUser) {
        loggedOutDiv.classList.add("hidden");
        loggedInDiv.classList.remove("hidden");
        if (userEmailSpan) {
            userEmailSpan.textContent = currentUser.email;
        }
        
        // Setup Cloud Sync Toggle checkbox state
        const syncToggle = document.getElementById("toggle-cloud-sync");
        if (syncToggle) {
            const syncSetting = localStorage.getItem("cloud_sync_enabled");
            syncToggle.checked = (syncSetting === null || syncSetting === "true");
            
            syncToggle.onchange = function() {
                localStorage.setItem("cloud_sync_enabled", this.checked ? "true" : "false");
                if (this.checked) {
                    syncPendingRoutes();
                    syncPendingRouteTuningProfiles().then(loadRouteTuningProfiles);
                } else {
                    loadHistory();
                    loadRouteTuningProfiles();
                }
            };
        }
    } else {
        loggedInDiv.classList.add("hidden");
        loggedOutDiv.classList.remove("hidden");
        if (userEmailSpan) {
            userEmailSpan.textContent = "-";
        }
        document.getElementById("auth-email").value = "";
        document.getElementById("auth-password").value = "";
        const confirmField = document.getElementById("auth-password-confirm");
        if (confirmField) confirmField.value = "";
        hideAuthMessages();
    }
    
    // Load navigation adventures history
    loadHistory();
}

function hideAuthMessages() {
    const errDiv = document.getElementById("auth-message");
    const succDiv = document.getElementById("auth-success-message");
    if (errDiv) {
        errDiv.classList.add("hidden");
        errDiv.textContent = "";
    }
    if (succDiv) {
        succDiv.classList.add("hidden");
        succDiv.textContent = "";
    }
}

function showAuthError(msg) {
    const errDiv = document.getElementById("auth-message");
    const succDiv = document.getElementById("auth-success-message");
    if (succDiv) succDiv.classList.add("hidden");
    if (errDiv) {
        errDiv.textContent = msg;
        errDiv.classList.remove("hidden");
    }
}

function showAuthSuccess(msg) {
    const errDiv = document.getElementById("auth-message");
    const succDiv = document.getElementById("auth-success-message");
    if (errDiv) errDiv.classList.add("hidden");
    if (succDiv) {
        succDiv.textContent = msg;
        succDiv.classList.remove("hidden");
    }
}

function initAuthEventListeners() {
    const tabLogin = document.getElementById("tab-btn-login");
    const tabSignup = document.getElementById("tab-btn-signup");
    const confirmGroup = document.getElementById("signup-confirm-group");
    const submitBtn = document.getElementById("auth-submit-btn");
    const authForm = document.getElementById("auth-form");
    const logoutBtn = document.getElementById("btn-logout");
    
    let activeTab = "login";
    
    if (tabLogin && tabSignup) {
        tabLogin.addEventListener("click", () => {
            if (activeTab === "login") return;
            activeTab = "login";
            tabLogin.classList.add("active");
            tabSignup.classList.remove("active");
            if (confirmGroup) confirmGroup.classList.add("hidden");
            document.getElementById("auth-password-confirm").removeAttribute("required");
            if (submitBtn) submitBtn.textContent = "Log In";
            hideAuthMessages();
        });
        
        tabSignup.addEventListener("click", () => {
            if (activeTab === "signup") return;
            activeTab = "signup";
            tabSignup.classList.add("active");
            tabLogin.classList.remove("active");
            if (confirmGroup) confirmGroup.classList.remove("hidden");
            document.getElementById("auth-password-confirm").setAttribute("required", "required");
            if (submitBtn) submitBtn.textContent = "Sign Up";
            hideAuthMessages();
        });
    }
    
    if (authForm) {
        authForm.addEventListener("submit", async (e) => {
            e.preventDefault();
            hideAuthMessages();
            
            const email = document.getElementById("auth-email").value.trim();
            const password = document.getElementById("auth-password").value;
            
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Processing...';
            }
            
            try {
                if (activeTab === "signup") {
                    const confirmPass = document.getElementById("auth-password-confirm").value;
                    if (password !== confirmPass) {
                        showAuthError("Passwords do not match.");
                        if (submitBtn) {
                            submitBtn.disabled = false;
                            submitBtn.textContent = "Sign Up";
                        }
                        return;
                    }
                    
                    const regResp = await fetch(`${PB_URL}/api/collections/users/records`, {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({
                            email: email,
                            password: password,
                            passwordConfirm: confirmPass,
                            emailVisibility: true
                        })
                    });
                    
                    const regData = await regResp.json();
                    if (!regResp.ok) {
                        const errorMsg = parsePocketBaseError(regData);
                        throw new Error(errorMsg || "Sign up failed.");
                    }
                    
                    showAuthSuccess("Account created! Logging in...");
                    await performLogin(email, password);
                } else {
                    await performLogin(email, password);
                }
            } catch (err) {
                console.error("[Auth Error]", err);
                showAuthError(err.message);
            } finally {
                if (submitBtn) {
                    submitBtn.disabled = false;
                    submitBtn.textContent = activeTab === "signup" ? "Sign Up" : "Log In";
                }
            }
        });
    }
    
    if (logoutBtn) {
        logoutBtn.addEventListener("click", () => {
            currentUser = null;
            localStorage.removeItem("pocketbase_auth");
            
            // Clear authenticated synced routes on logout
            let localRoutes = [];
            try {
                localRoutes = JSON.parse(localStorage.getItem("boulder_local_routes") || "[]");
            } catch (e) {}
            // Keep only unauthenticated (guest) routes (where userId is null) and unsynced ones
            localRoutes = localRoutes.filter(r => r.userId === null && !r.synced);
            localStorage.setItem("boulder_local_routes", JSON.stringify(localRoutes));
            const localProfiles = getLocalRouteTuningProfiles(true).filter(profile => profile.userId === null && !profile.synced);
            saveLocalRouteTuningProfiles(localProfiles);
            routeTuningProfiles = localProfiles;
            activeRouteTuningProfileId = "";
            localStorage.setItem(ACTIVE_ROUTE_TUNING_PROFILE_KEY, "");
            localStorage.removeItem("cloud_sync_enabled"); // Reset toggle settings
            
            // Reset weights to system defaults on logout
            Object.keys(SYSTEM_DEFAULT_WEIGHTS).forEach(key => {
                DEFAULT_WEIGHTS[key] = SYSTEM_DEFAULT_WEIGHTS[key];
                const slider = document.getElementById(`weight-${key}`);
                const valueSpan = document.getElementById(`val-${key}`);
                if (slider && valueSpan) {
                    slider.value = SYSTEM_DEFAULT_WEIGHTS[key];
                    valueSpan.textContent = `${SYSTEM_DEFAULT_WEIGHTS[key].toFixed(1)}x`;
                }
            });
            if (startMarker && endMarker) {
                calculateRoute();
            }
            
            updateAuthUI();
            loadRouteTuningProfiles();
            showToast("Logged out successfully.");
        });
    }
}

async function performLogin(email, password) {
    const resp = await fetch(`${PB_URL}/api/collections/users/auth-with-password`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            identity: email,
            password: password
        })
    });
    
    const data = await resp.json();
    if (!resp.ok) {
        const errorMsg = parsePocketBaseError(data);
        throw new Error(errorMsg || "Invalid email or password.");
    }
    
    localStorage.setItem("pocketbase_auth", JSON.stringify({
        token: data.token,
        record: data.record
    }));
    
    // Enable Cloud Sync by default on sign-in
    localStorage.setItem("cloud_sync_enabled", "true");
    
    currentUser = data.record;
    updateAuthUI();
    
    // Sync any pending routes immediately after login
    await syncPendingRoutes();
    await syncPendingRouteTuningProfiles();
    await loadRouteTuningProfiles();
}

function parsePocketBaseError(data) {
    if (!data) return null;
    if (data.message) {
        if (data.data) {
            const errors = [];
            for (const key of Object.keys(data.data)) {
                const errDetail = data.data[key];
                errors.push(`${key}: ${errDetail.message || JSON.stringify(errDetail)}`);
            }
            if (errors.length > 0) {
                return `${data.message} (${errors.join(", ")})`;
            }
        }
        return data.message;
    }
    return null;
}

// Update the locate button's icon and color based on current permission state
function updateLocateButtonVisuals() {
    const locateBtn = document.getElementById("btn-locate-map");
    if (!locateBtn) return;

    const isGranted = localStorage.getItem("geolocation_granted") === "true";
    const isDenied = localStorage.getItem("geolocation_denied") === "true";

    locateBtn.classList.remove("granted", "denied");
    
    if (isGranted) {
        locateBtn.classList.add("granted");
        locateBtn.innerHTML = '<i class="fa-solid fa-location-crosshairs"></i>';
        locateBtn.title = "Location Access Allowed";
    } else if (isDenied) {
        locateBtn.classList.add("denied");
        locateBtn.innerHTML = '<i class="fa-solid fa-location-pin-lock"></i>';
        locateBtn.title = "Location Access Blocked - Click to resolve";
    } else {
        locateBtn.innerHTML = '<i class="fa-solid fa-location-crosshairs"></i>';
        locateBtn.title = "Find my location";
    }
}

// ====================================
// USER PROFILE SETTINGS SYNC (OPTION A)
// ====================================

async function loadUserProfileConfig() {
    if (!currentUser) return;
    
    const storedAuth = localStorage.getItem("pocketbase_auth");
    if (!storedAuth) return;
    
    try {
        const authData = JSON.parse(storedAuth);
        const token = authData.token;
        
        const url = `${PB_URL}/api/collections/user_configs/records?filter=` + encodeURIComponent(`user='${currentUser.id}' && key='weights'`);
        const resp = await fetch(url, {
            headers: {
                "Authorization": `Bearer ${token}`
            }
        });
        
        if (resp.ok) {
            const data = await resp.json();
            const items = data.items || [];
            if (items.length > 0) {
                const overrideWeights = items[0].value;
                console.log("[Auth] Loaded custom user weights override from profile:", overrideWeights);
                
                // Apply overridden weights to the sliders
                for (const [key, val] of Object.entries(overrideWeights)) {
                    const slider = document.getElementById(`weight-${key}`);
                    const valDisplay = document.getElementById(`val-${key}`);
                    if (slider) {
                        slider.value = val;
                    }
                    if (valDisplay) {
                        valDisplay.textContent = `${val.toFixed(1)}x`;
                    }
                    DEFAULT_WEIGHTS[key] = val;
                }
                
                // Recalculate route if markers exist
                if (startMarker && endMarker) {
                    calculateRoute();
                }
            }
        }
    } catch (err) {
        console.error("[Auth] Failed to load user profile configs:", err);
    }
}

async function saveUserProfileConfig() {
    if (!currentUser) {
        showToast("Please log in to save settings.");
        return;
    }
    
    const storedAuth = localStorage.getItem("pocketbase_auth");
    if (!storedAuth) return;
    
    const saveBtn = document.getElementById("btn-save-profile");
    const originalHtml = saveBtn ? saveBtn.innerHTML : "";
    if (saveBtn) {
        saveBtn.disabled = true;
        saveBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Saving...';
    }
    
    try {
        const authData = JSON.parse(storedAuth);
        const token = authData.token;
        
        // Gather current slider weights
        const weights = getWeightsFromSliders();
        
        // Check if there is an existing override record
        const url = `${PB_URL}/api/collections/user_configs/records?filter=` + encodeURIComponent(`user='${currentUser.id}' && key='weights'`);
        const checkResp = await fetch(url, {
            headers: {
                "Authorization": `Bearer ${token}`
            }
        });
        
        if (!checkResp.ok) {
            throw new Error("Failed to check existing config.");
        }
        
        const checkData = await checkResp.json();
        const items = checkData.items || [];
        
        let resp;
        if (items.length > 0) {
            // Update existing record
            const recordId = items[0].id;
            resp = await fetch(`${PB_URL}/api/collections/user_configs/records/${recordId}`, {
                method: "PATCH",
                headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${token}`
                },
                body: JSON.stringify({
                    value: weights
                })
            });
        } else {
            // Create new record
            resp = await fetch(`${PB_URL}/api/collections/user_configs/records`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${token}`
                },
                body: JSON.stringify({
                    user: currentUser.id,
                    key: "weights",
                    value: weights
                })
            });
        }
        
        if (resp.ok) {
            showToast("Settings saved to your profile successfully!");
        } else {
            const errorData = await resp.json();
            throw new Error(errorData.message || "Failed to save settings.");
        }
    } catch (err) {
        console.error("[Auth] Save settings error:", err);
        showToast("Error saving settings: " + err.message);
    } finally {
        if (saveBtn) {
            saveBtn.disabled = false;
            saveBtn.innerHTML = originalHtml;
        }
    }
}

async function resetUserWeights() {
    // 1. Reset client-side weights to system defaults
    Object.keys(SYSTEM_DEFAULT_WEIGHTS).forEach(key => {
        DEFAULT_WEIGHTS[key] = SYSTEM_DEFAULT_WEIGHTS[key];
        const slider = document.getElementById(`weight-${key}`);
        const valueSpan = document.getElementById(`val-${key}`);
        if (slider && valueSpan) {
            slider.value = SYSTEM_DEFAULT_WEIGHTS[key];
            valueSpan.textContent = `${SYSTEM_DEFAULT_WEIGHTS[key].toFixed(1)}x`;
        }
    });
    
    // 2. If logged in, delete from database
    if (currentUser) {
        const storedAuth = localStorage.getItem("pocketbase_auth");
        if (storedAuth) {
            try {
                const authData = JSON.parse(storedAuth);
                const token = authData.token;
                
                const url = `${PB_URL}/api/collections/user_configs/records?filter=` + encodeURIComponent(`user='${currentUser.id}' && key='weights'`);
                const checkResp = await fetch(url, {
                    headers: {
                        "Authorization": `Bearer ${token}`
                    }
                });
                
                if (checkResp.ok) {
                    const checkData = await checkResp.json();
                    const items = checkData.items || [];
                    if (items.length > 0) {
                        const recordId = items[0].id;
                        const delResp = await fetch(`${PB_URL}/api/collections/user_configs/records/${recordId}`, {
                            method: "DELETE",
                            headers: {
                                "Authorization": `Bearer ${token}`
                            }
                        });
                        if (delResp.ok) {
                            showToast("Profile settings reset to system defaults.");
                        }
                    }
                }
            } catch (err) {
                console.error("[Auth] Reset settings error:", err);
            }
        }
    } else {
        showToast("Settings reset to defaults.");
    }
    
    // 3. Recalculate route if applicable
    if (startMarker && endMarker) {
        calculateRoute();
    }
}

// --- Adventure History Rendering & Telemetry ---
let historyMarkers = [];
let historyPolylines = [];
let currentHistoryItems = [];
let currentHistoryRoute = null;
let isHistoryDetailEditing = false;

function getStoredAuthSession() {
    const storedAuth = localStorage.getItem("pocketbase_auth");
    if (!storedAuth) return null;
    try {
        const authData = JSON.parse(storedAuth);
        if (authData && authData.token && authData.record) return authData;
    } catch (e) {}
    return null;
}

function getLocalHistoryRoutes() {
    try {
        return JSON.parse(localStorage.getItem("boulder_local_routes") || "[]");
    } catch (e) {
        return [];
    }
}

function saveLocalHistoryRoutes(routes) {
    localStorage.setItem("boulder_local_routes", JSON.stringify(routes));
}

function getHistoryRouteTitle(route) {
    const displayName = (route.display_name || "").trim();
    return displayName || (route.end_point_name ? `${route.end_point_name} Route` : "Custom Route");
}

function escapeHtml(value) {
    return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}

function formatHistoryDate(value) {
    if (!value) return "";
    return new Date(value).toLocaleDateString(undefined, {
        month: "long",
        day: "numeric",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit"
    });
}

function getRouteServerId(route) {
    return route.server_id || (route.synced ? route.id : null);
}

async function syncPendingRoutes() {
    const storedAuth = localStorage.getItem("pocketbase_auth");
    if (!storedAuth) return;
    
    const syncSetting = localStorage.getItem("cloud_sync_enabled");
    const isSyncEnabled = (syncSetting === null || syncSetting === "true");
    if (!isSyncEnabled) return;
    
    let localRoutes = getLocalHistoryRoutes();
    
    const unsynced = localRoutes.filter(r => !r.synced);
    if (unsynced.length === 0) return;
    
    console.log(`[Sync] Found ${unsynced.length} unsynced local routes. Syncing...`);
    
    try {
        const authData = JSON.parse(storedAuth);
        const token = authData.token;
        const userId = authData.record.id;
        
        const payload = {
            routes: unsynced.map(r => ({
                local_id: r.local_id || r.id,
                server_id: r.server_id || (r.id && !String(r.id).startsWith("local-") ? r.id : null),
                operation: r.deleted ? "delete" : "upsert",
                deleted: Boolean(r.deleted),
                display_name: r.display_name || "",
                notes: r.notes || "",
                start_lat: r.start_lat,
                start_lon: r.start_lon,
                end_lat: r.end_lat,
                end_lon: r.end_lon,
                start_point_name: r.start_point_name,
                end_point_name: r.end_point_name,
                route_geojson: r.route_geojson,
                total_length_meters: r.total_length_meters,
                total_estimated_time_seconds: r.total_estimated_time_seconds,
                status: r.status,
                started_at: r.started_at,
                ended_at: r.ended_at,
                ended_lat: r.ended_lat,
                ended_lon: r.ended_lon,
                actual_distance_meters: r.actual_distance_meters,
                actual_duration_seconds: r.actual_duration_seconds,
                average_speed: r.average_speed,
                device_type: "web",
                weights: r.weights || {},
                ticks: r.ticks || []
            }))
        };
        
        const base = typeof API_BASE !== "undefined" ? API_BASE : "";
        const resp = await fetch(`${base}/api/navigation/sync`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${token}`
            },
            body: JSON.stringify(payload)
        });
        
        if (resp.ok) {
            const data = await resp.json();
            const syncedMap = {};
            const syncedDeletes = new Set();
            data.synced_routes.forEach(item => {
                syncedMap[item.local_id] = item.server_id;
                if (item.operation === "delete") syncedDeletes.add(item.local_id);
            });
            
            localRoutes = localRoutes.filter(r => {
                const localId = r.local_id || r.id;
                const syncedDelete = r.deleted && (syncedMap[localId] || syncedDeletes.has(localId));
                return !syncedDelete;
            });

            localRoutes.forEach(r => {
                const localId = r.local_id || r.id;
                if (syncedMap[localId]) {
                    r.synced = true;
                    r.userId = userId;
                    r.server_id = syncedMap[localId];
                }
            });
            
            localStorage.setItem("boulder_local_routes", JSON.stringify(localRoutes));
            console.log("[Sync] Batch sync successfully completed.");
            loadHistory();
        } else {
            console.error("[Sync] Sync request returned status:", resp.status);
        }
    } catch (err) {
        console.error("[Sync] Sync error:", err);
    }
}
window.syncPendingRoutes = syncPendingRoutes;

async function loadHistory() {
    const historyListContainer = document.getElementById("history-list");
    if (!historyListContainer) return;
    
    const storedAuth = localStorage.getItem("pocketbase_auth");
    let user = null;
    let token = null;
    if (storedAuth) {
        try {
            const authData = JSON.parse(storedAuth);
            if (authData && authData.token && authData.record) {
                user = authData.record;
                token = authData.token;
            }
        } catch(e) {}
    }
    
    const syncSetting = localStorage.getItem("cloud_sync_enabled");
    const isSyncEnabled = user && (syncSetting === null || syncSetting === "true");
    
    let serverRoutes = [];
    
    if (isSyncEnabled) {
        try {
            const url = `${API_BASE}/api/navigation/history`;
            const response = await fetch(url, {
                headers: { "Authorization": `Bearer ${token}` }
            });
            if (response.ok) {
                serverRoutes = await response.json();
            }
        } catch (err) {
            console.error("Failed to load telemetry history from server:", err);
        }
    }
    
    let localRoutes = [];
    try {
        localRoutes = JSON.parse(localStorage.getItem("boulder_local_routes") || "[]");
    } catch (e) {}
    
    const filteredLocalRoutes = localRoutes.filter(r => {
        if (r.deleted) return false;
        if (user) {
            return r.userId === user.id || r.userId === null;
        } else {
            return r.userId === null;
        }
    });
    
    const combinedMap = {};
    filteredLocalRoutes.forEach(r => {
        combinedMap[r.server_id || r.id] = { ...r, id: r.server_id || r.id };
    });
    serverRoutes.filter(r => !r.deleted).forEach(r => {
        combinedMap[r.id] = r;
    });
    
    const items = Object.values(combinedMap).sort((a, b) => {
        return new Date(b.started_at) - new Date(a.started_at);
    });
    currentHistoryItems = items;
    
    if (items.length === 0) {
        historyListContainer.innerHTML = '<p class="subtext" style="color: var(--text-secondary); text-align: center; padding: 20px 0;">No saved adventures yet. Log some routes to see them here.</p>';
        return;
    }
    
    historyListContainer.innerHTML = "";
    items.forEach(item => {
        const el = document.createElement("div");
        el.className = "history-item";
        el.setAttribute("data-id", item.id);
        
        const date = new Date(item.started_at).toLocaleDateString(undefined, {
            month: "short",
            day: "numeric",
            hour: "2-digit",
            minute: "2-digit"
        });
        
        const miles = (item.total_length_meters / 1609.34).toFixed(2);
        const actualMiles = item.actual_distance_meters ? (item.actual_distance_meters / 1609.34).toFixed(2) : "0.00";
        
        const durMin = Math.ceil(item.total_estimated_time_seconds / 60);
        const actualDurMin = item.actual_duration_seconds ? Math.ceil(item.actual_duration_seconds / 60) : 0;
        
        const speedMph = item.average_speed ? (item.average_speed * 2.23694).toFixed(1) : "0.0";
        
        el.innerHTML = `
            <div class="history-header">
                <span class="history-title">${escapeHtml(getHistoryRouteTitle(item))}</span>
                <span class="history-date">${date}</span>
            </div>
            <div class="history-stats">
                <div class="history-stat-box">
                    <span class="label">Distance</span>
                    <span class="value">${actualMiles} / ${miles} mi</span>
                </div>
                <div class="history-stat-box">
                    <span class="label">Duration</span>
                    <span class="value">${actualDurMin} / ${durMin} min</span>
                </div>
                <div class="history-stat-box">
                    <span class="label">Speed</span>
                    <span class="value">${speedMph} mph</span>
                </div>
            </div>
            <div class="history-endpoints">
                <div class="history-endpoints-row">
                    <i class="fa-solid fa-circle-dot"></i>
                    <span>${escapeHtml(item.start_point_name)}</span>
                </div>
                <div class="history-endpoints-row">
                    <i class="fa-solid fa-circle"></i>
                    <span>${escapeHtml(item.end_point_name)}</span>
                </div>
            </div>
        `;
        
        el.addEventListener("click", () => {
            document.querySelectorAll(".history-item").forEach(x => x.classList.remove("active"));
            el.classList.add("active");
            showHistoryDetail(item.id);
        });
        
        historyListContainer.appendChild(el);
    });
}

async function showHistoryDetail(routeId) {
    const route = currentHistoryItems.find(item => item.id === routeId || item.local_id === routeId);
    if (!route) return;

    currentHistoryRoute = route;
    isHistoryDetailEditing = false;

    document.getElementById("history-list")?.classList.add("hidden");
    document.getElementById("history-detail")?.classList.remove("hidden");
    renderHistoryDetail(route);
}

function hideHistoryDetail() {
    currentHistoryRoute = null;
    isHistoryDetailEditing = false;
    document.getElementById("history-detail")?.classList.add("hidden");
    document.getElementById("history-list")?.classList.remove("hidden");
}

function renderHistoryDetail(route) {
    const titleInput = document.getElementById("history-detail-title");
    const notesInput = document.getElementById("history-detail-notes");
    const editIcon = document.querySelector("#btn-history-detail-edit i");

    if (titleInput) {
        titleInput.value = getHistoryRouteTitle(route);
        titleInput.readOnly = !isHistoryDetailEditing;
    }
    if (notesInput) {
        notesInput.value = route.notes || "";
        notesInput.readOnly = !isHistoryDetailEditing;
    }
    if (editIcon) {
        editIcon.className = isHistoryDetailEditing ? "fa-solid fa-check" : "fa-solid fa-pen";
    }

    const miles = ((route.actual_distance_meters || route.total_length_meters || 0) / 1609.34).toFixed(2);
    const durationMin = Math.ceil((route.actual_duration_seconds || route.total_estimated_time_seconds || 0) / 60);
    const speedMph = route.average_speed ? (route.average_speed * 2.23694).toFixed(1) : "0.0";

    const dateEl = document.getElementById("history-detail-date");
    if (dateEl) dateEl.textContent = formatHistoryDate(route.started_at);
    document.getElementById("history-detail-distance").textContent = `${miles} mi`;
    document.getElementById("history-detail-duration").textContent = `${durationMin} min`;
    document.getElementById("history-detail-speed").textContent = `${speedMph} mph`;
}

async function toggleHistoryDetailEdit() {
    if (!currentHistoryRoute) return;
    if (!isHistoryDetailEditing) {
        isHistoryDetailEditing = true;
        renderHistoryDetail(currentHistoryRoute);
        document.getElementById("history-detail-title")?.focus();
        return;
    }

    const title = document.getElementById("history-detail-title")?.value.trim() || getHistoryRouteTitle(currentHistoryRoute);
    const notes = document.getElementById("history-detail-notes")?.value.trim() || "";
    await updateHistoryRoute(currentHistoryRoute, { display_name: title, notes });
    isHistoryDetailEditing = false;
}

async function updateHistoryRoute(route, changes) {
    const routeId = route.id;
    let localRoutes = getLocalHistoryRoutes();
    const localIndex = localRoutes.findIndex(r => r.id === routeId || r.local_id === routeId || r.server_id === routeId);

    if (localIndex >= 0) {
        localRoutes[localIndex] = {
            ...localRoutes[localIndex],
            ...changes,
            synced: false,
            updated_at: new Date().toISOString()
        };
        saveLocalHistoryRoutes(localRoutes);
        currentHistoryRoute = localRoutes[localIndex];
    } else {
        currentHistoryRoute = { ...route, ...changes };
    }

    const authData = getStoredAuthSession();
    const serverId = getRouteServerId(route);
    if (authData && serverId) {
        try {
            const resp = await fetch(`${API_BASE}/api/navigation/${serverId}`, {
                method: "PATCH",
                headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${authData.token}`
                },
                body: JSON.stringify(changes)
            });
            if (resp.ok) {
                const updated = await resp.json();
                currentHistoryRoute = { ...currentHistoryRoute, ...updated, synced: true, server_id: updated.id };
                if (localIndex >= 0) {
                    localRoutes = getLocalHistoryRoutes();
                    localRoutes[localIndex] = { ...localRoutes[localIndex], ...updated, synced: true, server_id: updated.id };
                    saveLocalHistoryRoutes(localRoutes);
                }
            }
        } catch (err) {
            console.error("Failed to update route history remotely:", err);
        }
    } else {
        await syncPendingRoutes();
    }

    showToast("Route details saved.");
    await loadHistory();
    if (currentHistoryRoute) {
        const refreshed = currentHistoryItems.find(item => item.id === currentHistoryRoute.id) || currentHistoryRoute;
        currentHistoryRoute = refreshed;
        renderHistoryDetail(refreshed);
    }
}

async function deleteHistoryRoute(route) {
    if (!route) return;
    if (!confirm("Remove this route from history?")) return;

    const routeId = route.id;
    let localRoutes = getLocalHistoryRoutes();
    const localIndex = localRoutes.findIndex(r => r.id === routeId || r.local_id === routeId || r.server_id === routeId);
    const authData = getStoredAuthSession();
    const serverId = getRouteServerId(route);

    if (localIndex >= 0) {
        if (serverId && authData) {
            localRoutes[localIndex] = { ...localRoutes[localIndex], deleted: true, synced: false };
        } else {
            localRoutes.splice(localIndex, 1);
        }
        saveLocalHistoryRoutes(localRoutes);
    }

    if (authData && serverId) {
        try {
            const resp = await fetch(`${API_BASE}/api/navigation/${serverId}`, {
                method: "DELETE",
                headers: { "Authorization": `Bearer ${authData.token}` }
            });
            if (!resp.ok) throw new Error(`Delete failed with status ${resp.status}`);
            localRoutes = getLocalHistoryRoutes().filter(r => !(r.id === routeId || r.local_id === routeId || r.server_id === serverId));
            saveLocalHistoryRoutes(localRoutes);
        } catch (err) {
            console.error("Failed to delete route history remotely:", err);
            await syncPendingRoutes();
        }
    }

    clearHistoryMapLayers();
    hideHistoryDetail();
    await loadHistory();
    showToast("Route removed from history.");
}

function exportHistoryRoute(route) {
    if (!route) return;
    const blob = new Blob([JSON.stringify(route, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${getHistoryRouteTitle(route).replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "").toLowerCase() || "route-history"}.json`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
}

function initializeHistoryDetailControls() {
    document.getElementById("btn-history-detail-back")?.addEventListener("click", hideHistoryDetail);
    document.getElementById("btn-history-detail-edit")?.addEventListener("click", toggleHistoryDetailEdit);
    document.getElementById("btn-history-view-map")?.addEventListener("click", () => {
        if (currentHistoryRoute) loadHistoryRouteOnMap(currentHistoryRoute.id);
    });
    document.getElementById("history-map-preview")?.addEventListener("click", () => {
        if (currentHistoryRoute) loadHistoryRouteOnMap(currentHistoryRoute.id);
    });
    document.getElementById("btn-history-export")?.addEventListener("click", () => exportHistoryRoute(currentHistoryRoute));
    document.getElementById("btn-history-delete")?.addEventListener("click", () => deleteHistoryRoute(currentHistoryRoute));
}

async function loadHistoryRouteOnMap(routeId) {
    clearRoute();
    clearHistoryMapLayers();
    
    let localRoute = null;
    try {
        const localRoutes = getLocalHistoryRoutes();
        localRoute = localRoutes.find(r => !r.deleted && (r.id === routeId || r.local_id === routeId || r.server_id === routeId));
    } catch (e) {}
    
    try {
        let route;
        if (localRoute) {
            route = localRoute;
            console.log("[History] Loaded route details from local storage cache.");
        } else {
            const authData = getStoredAuthSession();
            const response = await fetch(`${API_BASE}/api/navigation/${routeId}`, {
                headers: authData ? { "Authorization": `Bearer ${authData.token}` } : {}
            });
            if (!response.ok) throw new Error("Failed to fetch route details");
            route = await response.json();
        }
        
        if (route.route_geojson) {
            const geojsonLayer = L.geoJSON(route.route_geojson, {
                style: function (feature) {
                    return {
                        color: "#94a3b8",
                        weight: 4,
                        opacity: 0.6,
                        dashArray: "6, 6"
                    };
                }
            }).addTo(map);
            historyPolylines.push(geojsonLayer);
        }
        
        const startIcon = createCustomIcon("green");
        const endIcon = createCustomIcon("red");
        
        const startMarkerLoc = L.marker([route.start_lat, route.start_lon], { icon: startIcon, interactive: true })
            .bindPopup(`<strong>Start point:</strong> ${route.start_point_name}`)
            .addTo(map);
        historyMarkers.push(startMarkerLoc);
        
        const endMarkerLoc = L.marker([route.end_lat, route.end_lon], { icon: endIcon, interactive: true })
            .bindPopup(`<strong>Destination:</strong> ${route.end_point_name}`)
            .addTo(map);
        historyMarkers.push(endMarkerLoc);
        
        if (route.ticks && route.ticks.length > 0) {
            const dotCoords = [];
            route.ticks.forEach((tick, index) => {
                const tickLatLng = [tick.lat, tick.lon];
                dotCoords.push(tickLatLng);
                
                const time = new Date(tick.timestamp).toLocaleTimeString();
                const speed = (tick.speed * 2.23694).toFixed(1);
                const direction = Math.round(tick.direction);
                
                const dotMarker = L.marker(tickLatLng, {
                    icon: L.divIcon({
                        html: '<div class="history-dot-inner"></div>',
                        iconSize: [8, 8],
                        iconAnchor: [4, 4],
                        className: 'history-dot-marker'
                    }),
                    interactive: true
                }).bindTooltip(`
                    <strong>GPS Telemetry Point #${index + 1}</strong><br>
                    Time: ${time}<br>
                    Speed: ${speed} mph<br>
                    Heading: ${direction}°<br>
                    Accuracy: ${tick.accuracy ? tick.accuracy.toFixed(1) + 'm' : 'N/A'}
                `, { sticky: true, opacity: 0.9 }).addTo(map);
                
                historyMarkers.push(dotMarker);
            });
            
            const bounds = L.latLngBounds(dotCoords.concat([[route.start_lat, route.start_lon], [route.end_lat, route.end_lon]]));
            map.fitBounds(bounds, { padding: [40, 40] });
        } else {
            const bounds = L.latLngBounds([[route.start_lat, route.start_lon], [route.end_lat, route.end_lon]]);
            map.fitBounds(bounds, { padding: [40, 40] });
        }
        
        const distanceMiles = route.actual_distance_meters ? (route.actual_distance_meters / 1609.34).toFixed(2) : "0.00";
        const estimatedMiles = (route.total_length_meters / 1609.34).toFixed(2);
        
        const durationMin = route.actual_duration_seconds ? Math.ceil(route.actual_duration_seconds / 60) : 0;
        const estimatedMin = Math.ceil(route.total_estimated_time_seconds / 60);
        
        const avgSpeedMph = route.average_speed ? (route.average_speed * 2.23694).toFixed(1) : "0.0";
        
        document.getElementById("info-distance").innerHTML = `
            <strong>Actual:</strong> ${distanceMiles} mi <span style="font-size:11px; color:var(--text-secondary);">(Est: ${estimatedMiles} mi)</span><br>
            <strong>Duration:</strong> ${durationMin} min <span style="font-size:11px; color:var(--text-secondary);">(Est: ${estimatedMin} min)</span><br>
            <strong>Avg Speed:</strong> ${avgSpeedMph} mph
        `;
        
        const costContainer = document.getElementById("info-cost-container");
        if (costContainer) {
            costContainer.style.display = "none";
        }
        
        const startNavBtn = document.getElementById("btn-start-nav");
        if (startNavBtn) {
            startNavBtn.style.display = "none";
        }
        const tbtContainer = document.getElementById("turn-by-turn-container");
        if (tbtContainer) {
            tbtContainer.classList.add("hidden");
        }
        
        document.getElementById("route-info").classList.remove("hidden");
        
    } catch (err) {
        console.error("Error drawing history route:", err);
        alert("Unable to draw history route telemetry on map.");
    }
}

function clearHistoryMapLayers() {
    historyMarkers.forEach(m => map.removeLayer(m));
    historyMarkers = [];
    historyPolylines.forEach(p => map.removeLayer(p));
    historyPolylines = [];
}
