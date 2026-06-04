// Boulder Casual Bike Router
// Frontend logic using Leaflet.js

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

const DEFAULT_WEIGHTS = {
    "separated_path": 0.5,
    "sharrow_minor": 1.5,
    "sidewalk": 2.0,
    "residential": 1.0,
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

// Initialize app when DOM loads
document.addEventListener("DOMContentLoaded", () => {
    initMap();
    initSliders();
    initEventListeners();
    prepopulatePoints();
    loadCrossings();
    loadPlaygrounds();
});

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

    if (!startMarker) {
        // Set Start marker
        startMarker = L.marker(latlng, {
            draggable: true,
            icon: createCustomIcon("green")
        }).addTo(map);
        
        startMarker.bindPopup("<strong>Start Point</strong><br>Drag to move").openPopup();
        startMarker.on("dragend", calculateRoute);
        
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
    document.getElementById("btn-reset").addEventListener("click", () => {
        Object.keys(DEFAULT_WEIGHTS).forEach(key => {
            const slider = document.getElementById(`weight-${key}`);
            const valueSpan = document.getElementById(`val-${key}`);
            if (slider && valueSpan) {
                slider.value = DEFAULT_WEIGHTS[key];
                valueSpan.textContent = `${DEFAULT_WEIGHTS[key].toFixed(1)}x`;
            }
        });
        if (startMarker && endMarker) {
            calculateRoute();
        }
    });

    // Panel toggle button floating
    const panelToggle = document.getElementById("panel-toggle");
    const controlPanel = document.getElementById("control-panel");
    const closeBtn = document.getElementById("btn-close-panel");
    const grabBar = document.getElementById("grab-bar");
    const panelHeader = document.querySelector(".panel-header");

    function togglePanel() {
        controlPanel.classList.toggle("collapsed");
        if (controlPanel.classList.contains("collapsed")) {
            panelToggle.classList.remove("hidden");
        } else {
            panelToggle.classList.add("hidden");
        }
        // Force Leaflet map resize layout update
        setTimeout(() => map.invalidateSize(), 300);
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

            const startCoords = [40.028446, -105.281088]; // Always Cedar Ave location
            const endStr = e.target.value;
            const endCoords = endStr.split(",").map(Number);

            loadPresetRoute(startCoords, endCoords);
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
        weights: weights
    };

    try {
        const response = await fetch("http://localhost:3001/api/route", {
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
        alert("Unable to connect to routing server. Make sure the backend Flask app is running on port 3001.");
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
        map.fitBounds(group.getBounds().pad(0.1));
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
        map.fitBounds(group.getBounds().pad(0.1));
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
        const response = await fetch("http://localhost:3001/api/crossings");
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
        const response = await fetch("http://localhost:3001/api/playgrounds");
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
