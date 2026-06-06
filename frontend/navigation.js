// Navigation Module for Boulder Casual Bike Router
// GPS tracking, heading-up map, voice turn-by-turn guidance

const Navigation = (() => {
    // --- State ---
    const state = {
        active: false,
        routeCoords: [],       // Flattened [lat, lng] array of entire route
        segments: [],          // Original segments from router
        maneuvers: [],         // Structured turn instructions
        currentManeuverIdx: 0,
        watchId: null,
        wakeLock: null,
        position: null,        // { lat, lng, accuracy, speed, heading }
        lastPositions: [],     // For smoothing + bearing calc
        heading: 0,            // Degrees from north
        muted: false,
        mapPaneEl: null,
        userMarker: null,
        headingConeMarker: null,
        originalMapState: null, // { center, zoom, bearing } to restore on exit
        routeId: null,
        lastLoggedPosition: null,
        lastLoggedTime: 0
    };

    // --- Constants ---
    const CASUAL_SPEED_MPS = 4.47;  // 10 mph in m/s
    const PRE_ANNOUNCE_DIST = 200;  // meters — "In 600 feet..."
    const CONFIRM_DIST = 30;        // meters — "Turn left now"
    const ANNOUNCED_PRE = new Set();
    const ANNOUNCED_CONFIRM = new Set();

    // --- Public API ---
    function start(segments, mapInstance) {
        if (state.active) return;

        state.segments = segments;
        state.routeCoords = flattenSegments(segments);
        state.maneuvers = buildManeuvers(segments);
        state.currentManeuverIdx = 0;
        state.active = true;
        state.muted = false;
        ANNOUNCED_PRE.clear();
        ANNOUNCED_CONFIRM.clear();

        // Save map state for restore
        state.originalMapState = {
            center: mapInstance.getCenter(),
            zoom: mapInstance.getZoom()
        };

        // Get map pane for rotation
        state.mapPaneEl = document.querySelector('.leaflet-map-pane');

        // Show nav overlay
        showOverlay();

        // Wire up permissions fix buttons
        const btnFixGps = document.getElementById('btn-fix-gps');
        if (btnFixGps) {
            btnFixGps.onclick = () => {
                const gpsDenied = localStorage.getItem("geolocation_denied") === "true";
                if (gpsDenied) {
                    if (window.showLocationSettingsModal) {
                        window.showLocationSettingsModal();
                    }
                } else {
                    if ('geolocation' in navigator) {
                        navigator.geolocation.getCurrentPosition(
                            (pos) => {
                                showToast("GPS location acquired!");
                                onPositionUpdate(pos, mapInstance);
                            },
                            (err) => {
                                onPositionError(err, mapInstance);
                            }
                        );
                    }
                }
            };
        }

        const btnFixCompass = document.getElementById('btn-fix-compass');
        if (btnFixCompass) {
            btnFixCompass.onclick = () => {
                requestDeviceOrientation();
            };
        }

        const btnFixWakelock = document.getElementById('btn-fix-wakelock');
        if (btnFixWakelock) {
            btnFixWakelock.onclick = () => {
                requestWakeLock();
            };
        }

        // Zoom in for navigation
        mapInstance.setZoom(17);

        // Request wake lock
        requestWakeLock();
        
        // Start route recording
        startRouteLogging(segments);

        // Start GPS
        if ('geolocation' in navigator) {
            const mockState = localStorage.getItem("mock_geolocation_state") || "default";
            if (mockState === "default" && !window.isSecureContext) {
                showToast('Insecure Context: Geolocation requires HTTPS or localhost on mobile.');
                stop(mapInstance);
                return;
            }
            state.watchId = navigator.geolocation.watchPosition(
                (pos) => onPositionUpdate(pos, mapInstance),
                (err) => onPositionError(err, mapInstance),
                {
                    enableHighAccuracy: true,
                    maximumAge: 3000,
                    timeout: 10000
                }
            );
        } else {
            showToast('Geolocation is not supported by this browser.');
            stop(mapInstance);
        }

        // Request device orientation for compass heading (iOS needs permission)
        requestDeviceOrientation();

        updateBottomBar();
    }

    function stop(mapInstance) {
        if (!state.active) return;
        state.active = false;

        // Stop GPS
        if (state.watchId !== null) {
            navigator.geolocation.clearWatch(state.watchId);
            state.watchId = null;
        }

        // Release wake lock
        releaseWakeLock();
        
        // End route logging
        endRouteLogging();

        // Remove user marker
        if (state.userMarker && mapInstance) {
            mapInstance.removeLayer(state.userMarker);
            state.userMarker = null;
        }
        if (state.headingConeMarker && mapInstance) {
            mapInstance.removeLayer(state.headingConeMarker);
            state.headingConeMarker = null;
        }

        // Reset map rotation
        if (state.mapPaneEl) {
            state.mapPaneEl.style.transform = '';
            state.mapPaneEl.style.transformOrigin = '';
        }

        // Restore map view
        if (state.originalMapState && mapInstance) {
            mapInstance.setView(state.originalMapState.center, state.originalMapState.zoom, { animate: true });
        }

        // Hide overlay
        hideOverlay();

        // Reset state
        state.lastPositions = [];
        state.position = null;
        state.heading = 0;
        state.maneuvers = [];
        state.routeCoords = [];
        state.segments = [];
        ANNOUNCED_PRE.clear();
        ANNOUNCED_CONFIRM.clear();
    }

    function toggleMute() {
        state.muted = !state.muted;
        const btn = document.getElementById('nav-mute-btn');
        if (btn) {
            btn.innerHTML = state.muted
                ? '<i class="fa-solid fa-volume-xmark"></i>'
                : '<i class="fa-solid fa-volume-high"></i>';
        }
        if (state.muted) {
            window.speechSynthesis.cancel();
        }
    }

    // --- GPS Handling ---
    function onPositionUpdate(pos, mapInstance) {
        if (!state.active) return;

        const lat = pos.coords.latitude;
        const lng = pos.coords.longitude;
        const accuracy = pos.coords.accuracy;
        const speed = pos.coords.speed; // may be null

        // Smoothing: keep last 2 positions for bearing calc
        state.lastPositions.push({ lat, lng, ts: pos.timestamp });
        if (state.lastPositions.length > 3) {
            state.lastPositions.shift();
        }

        // Smooth position (average of last 2)
        let smoothLat = lat, smoothLng = lng;
        if (state.lastPositions.length >= 2) {
            const recent = state.lastPositions.slice(-2);
            smoothLat = (recent[0].lat + recent[1].lat) / 2;
            smoothLng = (recent[0].lng + recent[1].lng) / 2;
        }

        state.position = { lat: smoothLat, lng: smoothLng, accuracy, speed };

        // Hide permissions checklist on first position lock
        updateNavPermissionsPanel();

        // Calculate GPS-derived bearing if no compass
        if (state.lastPositions.length >= 2) {
            const prev = state.lastPositions[state.lastPositions.length - 2];
            const curr = state.lastPositions[state.lastPositions.length - 1];
            const dist = getDistance(prev.lat, prev.lng, curr.lat, curr.lng);
            if (dist > 3) { // Only update bearing if moved > 3m (avoid jitter)
                const gpsBearing = getBearing([prev.lat, prev.lng], [curr.lat, curr.lng]);
                // Only use GPS bearing if we don't have device compass
                if (!state._hasDeviceHeading) {
                    state.heading = gpsBearing;
                }
            }
        }

        // Update blue dot
        updateUserMarker(mapInstance, smoothLat, smoothLng);

        // Re-center map on user
        mapInstance.panTo([smoothLat, smoothLng], { animate: true, duration: 0.5 });

        // Rotate map to heading
        rotateMap();

        // Check maneuver proximity
        checkManeuvers();

        // Update bottom bar
        updateBottomBar();
        
        // Telemetry logging to backend
        logTick(smoothLat, smoothLng, accuracy, speed);
    }

    function onPositionError(err, mapInstance) {
        console.warn('GPS error:', err.message);
        if (err.code === 1) { // PERMISSION_DENIED
            showToast('Location permission denied. Enable GPS to navigate.');
            stop(mapInstance);
            if (window.showLocationSettingsModal) {
                window.showLocationSettingsModal();
            }
        } else {
            // Update banner to inform user
            const textEl = document.getElementById('nav-maneuver-text');
            if (textEl && !state.position) {
                textEl.textContent = 'Waiting for GPS signal...';
            }
            showToast(`GPS Error: ${err.message}`);
            updateNavPermissionsPanel();
        }
    }

    // --- User Marker ---
    function updateUserMarker(mapInstance, lat, lng) {
        if (!state.userMarker) {
            const dotHtml = `
                <div class="nav-user-dot-outer">
                    <div class="nav-user-dot-inner"></div>
                </div>
            `;
            state.userMarker = L.marker([lat, lng], {
                icon: L.divIcon({
                    html: dotHtml,
                    iconSize: [24, 24],
                    iconAnchor: [12, 12],
                    className: 'nav-user-marker'
                }),
                zIndexOffset: 9999,
                interactive: false
            }).addTo(mapInstance);
        } else {
            state.userMarker.setLatLng([lat, lng]);
        }

        // Heading cone
        if (!state.headingConeMarker) {
            const coneHtml = `<div class="nav-heading-cone" id="nav-heading-cone"></div>`;
            state.headingConeMarker = L.marker([lat, lng], {
                icon: L.divIcon({
                    html: coneHtml,
                    iconSize: [60, 60],
                    iconAnchor: [30, 30],
                    className: 'nav-cone-marker'
                }),
                zIndexOffset: 9998,
                interactive: false
            }).addTo(mapInstance);
        } else {
            state.headingConeMarker.setLatLng([lat, lng]);
        }

        // Rotate cone with heading (relative to map, so use raw heading since map is rotated)
        const coneEl = document.getElementById('nav-heading-cone');
        if (coneEl) {
            coneEl.style.transform = `rotate(${state.heading}deg)`;
        }
    }

    // --- Map Rotation ---
    function rotateMap() {
        if (!state.mapPaneEl) return;
        const rotation = -state.heading; // Counter-rotate so heading points up
        state.mapPaneEl.style.transformOrigin = '50% 50%';
        state.mapPaneEl.style.transform = `rotate(${rotation}deg)`;
    }

    // --- Device Orientation (compass) ---
    function requestDeviceOrientation() {
        state._hasDeviceHeading = false;

        // iOS 13+ requires permission
        if (typeof DeviceOrientationEvent !== 'undefined' &&
            typeof DeviceOrientationEvent.requestPermission === 'function') {
            DeviceOrientationEvent.requestPermission()
                .then(response => {
                    if (response === 'granted') {
                        window.addEventListener('deviceorientation', onDeviceOrientation);
                        state._hasDeviceHeading = true;
                    } else {
                        state._hasDeviceHeading = false;
                    }
                    updateNavPermissionsPanel();
                })
                .catch(err => {
                    console.warn('DeviceOrientation permission error:', err);
                    updateNavPermissionsPanel();
                });
        } else if ('DeviceOrientationEvent' in window) {
            window.addEventListener('deviceorientation', onDeviceOrientation);
            state._hasDeviceHeading = true;
            updateNavPermissionsPanel();
        }
    }

    function onDeviceOrientation(event) {
        if (!state.active) return;
        // webkitCompassHeading for iOS, alpha for Android (inverted)
        let heading = event.webkitCompassHeading;
        if (heading === undefined || heading === null) {
            if (event.alpha !== null) {
                heading = (360 - event.alpha) % 360;
            }
        }
        if (heading !== undefined && heading !== null && !isNaN(heading)) {
            state.heading = heading;
            if (!state._hasDeviceHeading) {
                state._hasDeviceHeading = true;
                updateNavPermissionsPanel();
            }
        }
    }

    // --- Maneuver System ---
    function buildManeuvers(segments) {
        if (!segments || segments.length === 0) return [];

        // Group consecutive segments by street name
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
                    name: seg.name || 'Unnamed Path',
                    length: seg.length,
                    type: seg.type,
                    coords: seg.coords ? [...seg.coords] : []
                });
            }
        });

        const maneuvers = [];
        let distFromStart = 0;

        // Starting instruction
        maneuvers.push({
            instruction: `Head onto ${grouped[0].name}`,
            shortInstruction: grouped[0].name,
            distanceFromStart: 0,
            triggerCoord: grouped[0].coords[0] || null,
            icon: 'fa-location-arrow',
            distanceToNext: grouped[0].length
        });

        for (let i = 0; i < grouped.length - 1; i++) {
            distFromStart += grouped[i].length;
            const legA = grouped[i];
            const legB = grouped[i + 1];

            // Get bearings for turn classification
            const coordsA = legA.coords;
            const ptA1 = coordsA[coordsA.length - 2] || coordsA[0];
            const ptA2 = coordsA[coordsA.length - 1];
            const bearingA = getBearing(ptA1, ptA2);

            const coordsB = legB.coords;
            const ptB1 = coordsB[0];
            const ptB2 = coordsB[1] || coordsB[0];
            const bearingB = getBearing(ptB1, ptB2);

            let diff = bearingB - bearingA;
            if (diff > 180) diff -= 360;
            if (diff < -180) diff += 360;

            let action, icon;
            if (diff > 135) { action = 'Sharp right onto'; icon = 'fa-arrow-right'; }
            else if (diff > 45) { action = 'Turn right onto'; icon = 'fa-arrow-right'; }
            else if (diff > 15) { action = 'Slight right onto'; icon = 'fa-arrow-right'; }
            else if (diff < -135) { action = 'Sharp left onto'; icon = 'fa-arrow-left'; }
            else if (diff < -45) { action = 'Turn left onto'; icon = 'fa-arrow-left'; }
            else if (diff < -15) { action = 'Slight left onto'; icon = 'fa-arrow-left'; }
            else { action = 'Continue onto'; icon = 'fa-arrow-up'; }

            maneuvers.push({
                instruction: `${action} ${legB.name}`,
                shortInstruction: legB.name,
                distanceFromStart: distFromStart,
                triggerCoord: ptA2, // The point where the turn happens
                icon: icon,
                distanceToNext: legB.length
            });
        }

        // Arrival
        const lastGroup = grouped[grouped.length - 1];
        distFromStart += lastGroup.length;
        const lastCoords = lastGroup.coords;
        maneuvers.push({
            instruction: 'Arrive at your destination',
            shortInstruction: 'Destination',
            distanceFromStart: distFromStart,
            triggerCoord: lastCoords[lastCoords.length - 1] || null,
            icon: 'fa-flag-checkered',
            distanceToNext: 0
        });

        return maneuvers;
    }

    function checkManeuvers() {
        if (!state.position || state.maneuvers.length === 0) return;

        const pos = state.position;

        for (let i = state.currentManeuverIdx; i < state.maneuvers.length; i++) {
            const m = state.maneuvers[i];
            if (!m.triggerCoord) continue;

            const dist = getDistance(pos.lat, pos.lng, m.triggerCoord[0], m.triggerCoord[1]);

            // Pre-announce
            if (dist <= PRE_ANNOUNCE_DIST && dist > CONFIRM_DIST && !ANNOUNCED_PRE.has(i)) {
                ANNOUNCED_PRE.add(i);
                const distStr = formatDistanceVoice(dist);
                speak(`In ${distStr}, ${m.instruction}`);
                updateManeuverBanner(m, dist);
            }

            // Confirm
            if (dist <= CONFIRM_DIST && !ANNOUNCED_CONFIRM.has(i)) {
                ANNOUNCED_CONFIRM.add(i);
                if (m.icon === 'fa-flag-checkered') {
                    speak('You have arrived at your destination.');
                } else {
                    speak(`${m.instruction}`);
                }
                state.currentManeuverIdx = Math.min(i + 1, state.maneuvers.length - 1);
                updateManeuverBanner(state.maneuvers[state.currentManeuverIdx], null);
            }
        }

        // Update banner with current distance to next maneuver
        if (state.currentManeuverIdx < state.maneuvers.length) {
            const next = state.maneuvers[state.currentManeuverIdx];
            if (next.triggerCoord) {
                const dist = getDistance(pos.lat, pos.lng, next.triggerCoord[0], next.triggerCoord[1]);
                updateManeuverBanner(next, dist);
            }
        }
    }

    // --- Voice ---
    function speak(text) {
        if (state.muted || !('speechSynthesis' in window)) return;
        window.speechSynthesis.cancel();
        const utterance = new SpeechSynthesisUtterance(text);
        utterance.rate = 1.0;
        utterance.pitch = 1.0;
        utterance.volume = 1.0;
        window.speechSynthesis.speak(utterance);
    }

    // --- Wake Lock ---
    async function requestWakeLock() {
        try {
            if ('wakeLock' in navigator) {
                state.wakeLock = await navigator.wakeLock.request('screen');
                state.wakeLock.addEventListener('release', () => {
                    state.wakeLock = null;
                    updateNavPermissionsPanel();
                });
                updateNavPermissionsPanel();
            }
        } catch (err) {
            console.warn('Wake lock request failed:', err);
            updateNavPermissionsPanel();
        }
    }

    function releaseWakeLock() {
        if (state.wakeLock) {
            state.wakeLock.release();
            state.wakeLock = null;
        }
    }

    // Update navigation permissions panel status
    function updateNavPermissionsPanel() {
        const panel = document.getElementById('nav-permissions-panel');
        if (!panel) return;

        // If GPS position is already acquired, hide the permissions checklist completely!
        if (state.position) {
            panel.classList.add('hidden');
            return;
        }

        panel.classList.remove('hidden');

        // 1. GPS Status
        const gpsStateEl = document.getElementById('perm-status-gps');
        const gpsBtn = document.getElementById('btn-fix-gps');
        const gpsDenied = localStorage.getItem("geolocation_denied") === "true";
        const gpsGranted = localStorage.getItem("geolocation_granted") === "true";

        if (gpsGranted) {
            gpsStateEl.className = 'perm-state status-granted';
            gpsStateEl.textContent = 'Allowed';
            gpsBtn.classList.add('hidden');
        } else if (gpsDenied) {
            gpsStateEl.className = 'perm-state status-denied';
            gpsStateEl.textContent = 'Blocked';
            gpsBtn.className = 'btn-perm-action';
            gpsBtn.textContent = 'Fix';
        } else {
            gpsStateEl.className = 'perm-state status-pending';
            gpsStateEl.textContent = 'Pending Lock...';
            gpsBtn.className = 'btn-perm-action';
            gpsBtn.textContent = 'Allow';
        }

        // 2. Compass Status
        const compassStateEl = document.getElementById('perm-status-compass');
        const compassBtn = document.getElementById('btn-fix-compass');
        const compassMockState = localStorage.getItem("mock_compass_state") || "default";

        if (state._hasDeviceHeading || compassMockState === 'granted') {
            compassStateEl.className = 'perm-state status-granted';
            compassStateEl.textContent = 'Allowed';
            compassBtn.classList.add('hidden');
        } else if (compassMockState === 'unsupported') {
            compassStateEl.className = 'perm-state status-denied';
            compassStateEl.textContent = 'Unsupported';
            compassBtn.classList.add('hidden');
        } else if (compassMockState === 'denied') {
            compassStateEl.className = 'perm-state status-denied';
            compassStateEl.textContent = 'Blocked';
            compassBtn.className = 'btn-perm-action';
            compassBtn.textContent = 'Allow';
        } else {
            compassStateEl.className = 'perm-state status-pending';
            compassStateEl.textContent = 'Pending...';
            compassBtn.className = 'btn-perm-action';
            compassBtn.textContent = 'Allow';
        }

        // 3. Wake Lock Status
        const wakeStateEl = document.getElementById('perm-status-wakelock');
        const wakeBtn = document.getElementById('btn-fix-wakelock');
        const wakeMockState = localStorage.getItem("mock_wakelock_state") || "default";

        if (state.wakeLock || wakeMockState === 'granted') {
            wakeStateEl.className = 'perm-state status-granted';
            wakeStateEl.textContent = 'Allowed';
            wakeBtn.classList.add('hidden');
        } else if (wakeMockState === 'unsupported' || (!('wakeLock' in navigator) && wakeMockState === 'default')) {
            wakeStateEl.className = 'perm-state status-denied';
            wakeStateEl.textContent = 'Unsupported';
            wakeBtn.classList.add('hidden');
        } else if (wakeMockState === 'denied') {
            wakeStateEl.className = 'perm-state status-denied';
            wakeStateEl.textContent = 'Blocked';
            wakeBtn.className = 'btn-perm-action';
            wakeBtn.textContent = 'Request';
        } else {
            wakeStateEl.className = 'perm-state status-pending';
            wakeStateEl.textContent = 'Ready';
            wakeBtn.className = 'btn-perm-action';
            wakeBtn.textContent = 'Request';
        }
    }

    // --- UI ---
    function showOverlay() {
        const overlay = document.getElementById('nav-overlay');
        if (overlay) {
            overlay.classList.remove('hidden');
            overlay.classList.add('visible');
        }
        // Hide the control panel
        const panel = document.getElementById('control-panel');
        if (panel) panel.classList.add('collapsed');
        const toggle = document.getElementById('panel-toggle');
        if (toggle) toggle.classList.add('hidden');

        // Show permissions checklist
        updateNavPermissionsPanel();
    }

    function hideOverlay() {
        const overlay = document.getElementById('nav-overlay');
        if (overlay) {
            overlay.classList.remove('visible');
            overlay.classList.add('hidden');
        }
        // Restore panel toggle
        const toggle = document.getElementById('panel-toggle');
        if (toggle) toggle.classList.remove('hidden');
    }

    function updateManeuverBanner(maneuver, distance) {
        const iconEl = document.getElementById('nav-maneuver-icon');
        const textEl = document.getElementById('nav-maneuver-text');
        const distEl = document.getElementById('nav-maneuver-dist');

        if (iconEl) iconEl.className = `fa-solid ${maneuver.icon}`;
        if (textEl) textEl.textContent = maneuver.instruction;
        if (distEl) {
            distEl.textContent = distance !== null ? formatDistanceShort(distance) : '';
        }
    }

    function updateBottomBar() {
        const distEl = document.getElementById('nav-remaining-dist');
        const etaEl = document.getElementById('nav-eta');

        if (!state.position || state.routeCoords.length === 0) return;

        // Find closest point on route to current position
        let minDist = Infinity;
        let closestIdx = 0;
        for (let i = 0; i < state.routeCoords.length; i++) {
            const d = getDistance(state.position.lat, state.position.lng,
                state.routeCoords[i][0], state.routeCoords[i][1]);
            if (d < minDist) {
                minDist = d;
                closestIdx = i;
            }
        }

        // Sum remaining distance from closest point to end
        let remaining = 0;
        for (let i = closestIdx; i < state.routeCoords.length - 1; i++) {
            remaining += getDistance(
                state.routeCoords[i][0], state.routeCoords[i][1],
                state.routeCoords[i + 1][0], state.routeCoords[i + 1][1]
            );
        }

        const remainingMiles = (remaining / 1609.34).toFixed(1);
        const etaMinutes = Math.ceil(remaining / CASUAL_SPEED_MPS / 60);

        if (distEl) distEl.textContent = `${remainingMiles} mi`;
        if (etaEl) etaEl.textContent = `${etaMinutes} min`;
    }

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

    // --- Geometry Helpers ---
    function flattenSegments(segments) {
        const coords = [];
        segments.forEach(seg => {
            if (seg.coords) {
                seg.coords.forEach(c => {
                    // Avoid duplicates at segment joins
                    const last = coords[coords.length - 1];
                    if (!last || last[0] !== c[0] || last[1] !== c[1]) {
                        coords.push(c);
                    }
                });
            }
        });
        return coords;
    }

    function getDistance(lat1, lon1, lat2, lon2) {
        const dy = (lat2 - lat1) * 111000;
        const dx = (lon2 - lon1) * 111000 * Math.cos(lat1 * Math.PI / 180);
        return Math.sqrt(dx * dx + dy * dy);
    }

    function getBearing(pt1, pt2) {
        const lat1 = pt1[0] * Math.PI / 180;
        const lat2 = pt2[0] * Math.PI / 180;
        const dLon = (pt2[1] - pt1[1]) * Math.PI / 180;
        const y = Math.sin(dLon) * Math.cos(lat2);
        const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
        return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
    }

    function formatDistanceShort(meters) {
        const miles = meters / 1609.34;
        if (miles < 0.1) {
            const feet = Math.round(meters * 3.28084);
            return `${Math.round(feet / 10) * 10} ft`;
        }
        return `${miles.toFixed(1)} mi`;
    }

    function formatDistanceVoice(meters) {
        const feet = Math.round(meters * 3.28084);
        if (feet < 528) { // < 0.1 mi
            return `${Math.round(feet / 50) * 50} feet`;
        }
        const miles = (meters / 1609.34).toFixed(1);
        return `${miles} miles`;
    }

    // --- Telemetry Logging API Gateway Calls ---
    function getAuthHeaders() {
        const headers = {
            "Content-Type": "application/json"
        };
        const storedAuth = localStorage.getItem("pocketbase_auth");
        if (storedAuth) {
            try {
                const authData = JSON.parse(storedAuth);
                if (authData && authData.token) {
                    headers["Authorization"] = `Bearer ${authData.token}`;
                }
            } catch (e) {
                console.error("Error reading auth token", e);
            }
        }
        return headers;
    }

    function isSyncActive() {
        const hasAuth = localStorage.getItem("pocketbase_auth") !== null;
        const syncSetting = localStorage.getItem("cloud_sync_enabled");
        const isSyncEnabled = (syncSetting === null || syncSetting === "true");
        return hasAuth && isSyncEnabled;
    }

    function generateUUID() {
        if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
            return crypto.randomUUID();
        }
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    async function startRouteLogging(segments) {
        if (!segments || segments.length === 0) return;
        
        let totalLength = 0;
        segments.forEach(seg => totalLength += seg.length);
        
        const CASUAL_SPEED_MPS = 4.47;
        const totalEstimatedTime = totalLength / CASUAL_SPEED_MPS;
        
        let startName = "Start Point";
        let endName = "Destination";
        
        const activePreset = document.querySelector(".preset-item.active");
        if (activePreset) {
            const nameSpan = activePreset.querySelector(".preset-name");
            if (nameSpan) {
                const text = nameSpan.textContent.trim();
                if (text.includes("➔")) {
                    const parts = text.split("➔");
                    startName = parts[0].trim();
                    endName = parts[1].trim();
                } else {
                    endName = text;
                }
            }
        } else {
            const playSelect = document.getElementById("playground-select");
            if (playSelect && playSelect.selectedIndex > 0) {
                endName = playSelect.options[playSelect.selectedIndex].text.trim();
            }
        }
        
        const routeGeojson = {
            type: "FeatureCollection",
            features: segments.map(seg => ({
                type: "Feature",
                geometry: {
                    type: "LineString",
                    coordinates: seg.coords.map(c => [c[1], c[0]])
                },
                properties: {
                    name: seg.name,
                    type: seg.type,
                    length: seg.length
                }
            }))
        };
        
        const weights = {};
        if (typeof getWeightsFromSliders === "function") {
            Object.assign(weights, getWeightsFromSliders());
        } else if (typeof DEFAULT_WEIGHTS !== "undefined") {
            Object.assign(weights, DEFAULT_WEIGHTS);
        }
        
        const startLat = segments[0].coords[0][0];
        const startLon = segments[0].coords[0][1];
        const endLat = segments[segments.length - 1].coords[segments[segments.length - 1].coords.length - 1][0];
        const endLon = segments[segments.length - 1].coords[segments[segments.length - 1].coords.length - 1][1];
        
        const tempId = generateUUID();
        state.routeId = tempId;
        state.lastLoggedTime = Date.now();
        state.localTicksCache = [];
        state.routeGeojson = routeGeojson;
        
        state.localStartRequest = {
            local_id: tempId,
            start_lat: startLat,
            start_lon: startLon,
            end_lat: endLat,
            end_lon: endLon,
            start_point_name: startName,
            end_point_name: endName,
            total_length_meters: totalLength,
            total_estimated_time_seconds: totalEstimatedTime,
            started_at: new Date().toISOString(),
            weights: weights
        };

        if (isSyncActive()) {
            const payload = {
                start_lat: startLat,
                start_lon: startLon,
                end_lat: endLat,
                end_lon: endLon,
                start_point_name: startName,
                end_point_name: endName,
                route_geojson: routeGeojson,
                total_length_meters: totalLength,
                total_estimated_time_seconds: totalEstimatedTime,
                device_type: "web",
                weights: weights
            };
            
            try {
                const base = typeof API_BASE !== "undefined" ? API_BASE : "";
                const response = await fetch(`${base}/api/navigation/start`, {
                    method: "POST",
                    headers: getAuthHeaders(),
                    body: JSON.stringify(payload)
                });
                if (response.ok) {
                    const data = await response.json();
                    state.routeId = data.route_id;
                    state.localStartRequest.local_id = data.route_id; // match IDs
                    console.log("[Navigation] Telemetry route created remotely:", state.routeId);
                }
            } catch (err) {
                console.error("[Navigation] Failed to start route recording remotely:", err);
            }
        } else {
            console.log("[Navigation] Guest or Sync Disabled: session running locally:", state.routeId);
        }
    }

    async function logTick(lat, lng, accuracy, speed) {
        if (!state.routeId) return;
        
        const now = Date.now();
        const timeElapsed = (now - state.lastLoggedTime) / 1000;
        
        let shouldLog = false;
        if (!state.lastLoggedPosition) {
            shouldLog = true;
        } else {
            const dist = getDistance(
                state.lastLoggedPosition.lat, state.lastLoggedPosition.lng,
                lat, lng
            );
            if (dist >= 2.0 || timeElapsed >= 3.0) {
                shouldLog = true;
            }
        }
        
        if (!shouldLog) return;
        
        state.lastLoggedPosition = { lat, lng };
        state.lastLoggedTime = now;
        
        const tick = {
            lat: lat,
            lon: lng,
            speed: speed || 0,
            direction: state.heading || 0,
            accuracy: accuracy || 0,
            altitude: 0,
            timestamp: new Date().toISOString()
        };
        
        state.localTicksCache.push(tick);
        
        if (isSyncActive()) {
            try {
                const base = typeof API_BASE !== "undefined" ? API_BASE : "";
                await fetch(`${base}/api/navigation/${state.routeId}/tick`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(tick)
                });
            } catch (err) {
                console.error("[Navigation] Failed to log telemetry tick remotely:", err);
            }
        }
    }

    async function endRouteLogging() {
        if (!state.routeId) return;
        
        const routeId = state.routeId;
        state.routeId = null;
        
        let status = "cancelled";
        let finalLat = null;
        let finalLon = null;
        
        if (state.position && state.routeCoords.length > 0) {
            finalLat = state.position.lat;
            finalLon = state.position.lng;
            const dest = state.routeCoords[state.routeCoords.length - 1];
            const distToDest = getDistance(finalLat, finalLon, dest[0], dest[1]);
            if (distToDest <= 50.0) {
                status = "completed";
            }
        }
        
        // 1. Calculate stats locally
        let actualDistance = 0.0;
        if (state.localTicksCache.length >= 2) {
            for (let i = 0; i < state.localTicksCache.length - 1; i++) {
                const t1 = state.localTicksCache[i];
                const t2 = state.localTicksCache[i+1];
                actualDistance += getDistance(t1.lat, t1.lon, t2.lat, t2.lon);
            }
        }
        
        let actualDuration = 0.0;
        if (state.localTicksCache.length >= 2) {
            const first = new Date(state.localTicksCache[0].timestamp).getTime();
            const last = new Date(state.localTicksCache[state.localTicksCache.length - 1].timestamp).getTime();
            actualDuration = (last - first) / 1000;
        }
        if (actualDuration <= 0) {
            actualDuration = state.localTicksCache.length * 3;
        }
        
        const avgSpeed = actualDuration > 0 ? (actualDistance / actualDuration) : 0.0;
        const startReq = state.localStartRequest;
        
        // 2. Save locally to localStorage
        const currentAuth = localStorage.getItem("pocketbase_auth");
        let currentUserId = null;
        if (currentAuth) {
            try {
                currentUserId = JSON.parse(currentAuth).record.id;
            } catch (e) {}
        }
        
        if (startReq) {
            const localRoute = {
                local_id: routeId,
                id: routeId,
                start_lat: startReq.start_lat,
                start_lon: startReq.start_lon,
                end_lat: startReq.end_lat,
                end_lon: startReq.end_lon,
                start_point_name: startReq.start_point_name,
                end_point_name: startReq.end_point_name,
                route_geojson: state.routeGeojson,
                total_length_meters: startReq.total_length_meters,
                total_estimated_time_seconds: startReq.total_estimated_time_seconds,
                status: status,
                started_at: startReq.started_at,
                ended_at: new Date().toISOString(),
                ended_lat: finalLat,
                ended_lon: finalLon,
                actual_distance_meters: actualDistance,
                actual_duration_seconds: actualDuration,
                average_speed: avgSpeed,
                device_type: "web",
                weights: startReq.weights,
                userId: currentUserId,
                synced: isSyncActive(),
                ticks: state.localTicksCache
            };
            
            let localRoutes = [];
            try {
                localRoutes = JSON.parse(localStorage.getItem("boulder_local_routes") || "[]");
            } catch (e) {}
            localRoutes.unshift(localRoute);
            localStorage.setItem("boulder_local_routes", JSON.stringify(localRoutes));
            console.log("[Navigation] Saved route locally to localStorage.");
        }
        
        // 3. Complete remote logging if sync was active
        if (isSyncActive()) {
            const endPayload = {
                status: status,
                ended_lat: finalLat,
                ended_lon: finalLon,
                ended_at: new Date().toISOString()
            };
            
            try {
                const base = typeof API_BASE !== "undefined" ? API_BASE : "";
                const response = await fetch(`${base}/api/navigation/${routeId}/end`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(endPayload)
                });
                
                if (response.ok) {
                    console.log("[Navigation] Telemetry ended remotely successfully.");
                }
            } catch (err) {
                console.error("[Navigation] Failed to stop route recording remotely:", err);
            }
        }
        
        if (window.loadHistory) {
            window.loadHistory();
        }
        
        // Auto-trigger background sync if logged in
        if (window.syncPendingRoutes) {
            window.syncPendingRoutes();
        }
        
        state.lastLoggedPosition = null;
        state.lastLoggedTime = 0;
        state.localStartRequest = null;
        state.routeGeojson = null;
        state.localTicksCache = [];
    }

    // --- Expose public API ---
    return { start, stop, toggleMute, state };
})();
