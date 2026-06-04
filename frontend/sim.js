// GPS Simulation Test Harness for Boulder Casual Bike Router
// Activated via ?sim=1 URL parameter. Inert otherwise.
// Monkey-patches navigator.geolocation to feed simulated positions along the route.

(function () {
    'use strict';

    // --- Gate: only activate if ?sim=1 is present ---
    if (!new URLSearchParams(window.location.search).has('sim')) return;

    console.log('%c[SIM] GPS Simulation Harness Active', 'color: #ffb300; font-weight: bold; font-size: 14px;');

    // --- Simulation State ---
    const sim = {
        active: false,
        paused: false,
        routeCoords: [],        // Flattened [lat, lng] route points
        currentIdx: 0,          // Current position along interpolated path
        interpCoords: [],       // Densely interpolated route (1m spacing)
        tickInterval: null,
        speed: 1,               // Playback multiplier (1x, 2x, 4x, 8x)
        lateralOffset: 0,       // Current perpendicular offset in meters
        lateralSide: 1,         // +1 or -1 (left/right of route)
        lateralTarget: 5,       // Target offset distance
        watchCallback: null,    // The success callback from watchPosition
        watchErrorCallback: null,
        compassHeading: 0,      // Current simulated compass heading
        compassTarget: 0,       // True bearing (target)
        panel: null,            // DOM element for control panel
        progressBar: null,
    };

    // --- Config (defaults, adjustable from panel) ---
    const config = {
        gpsJitter: 3,           // ±meters random noise per reading
        lateralOffsetMin: 3,    // meters
        lateralOffsetMax: 8,    // meters
        gpsSpikeChance: 0.03,   // 3% per tick
        gpsSpikeDistance: 40,    // meters (20-60 randomized)
        compassJitter: 8,       // ±degrees per reading
        compassBigSwingChance: 0.03, // 3% chance of ±25° swing
        tickMs: 1000,           // Base tick interval (1 second at 1x)
        riderSpeedMps: 4.47,    // 10 mph in m/s
    };

    // --- Monkey-patch navigator.geolocation ---
    const realGeolocation = navigator.geolocation;
    const fakeGeolocation = {
        watchPosition: function (success, error, options) {
            sim.watchCallback = success;
            sim.watchErrorCallback = error;
            // Don't start ticking yet — we start when startSim() is called
            // But we do need to prepare the route
            prepareSim();
            return 999; // Fake watch ID
        },
        clearWatch: function (id) {
            stopSim();
        },
        getCurrentPosition: function (success, error, options) {
            if (sim.interpCoords.length > 0) {
                const pos = buildPosition(sim.interpCoords[0][0], sim.interpCoords[0][1], 0);
                success(pos);
            } else if (realGeolocation) {
                realGeolocation.getCurrentPosition(success, error, options);
            }
        }
    };

    // Replace
    Object.defineProperty(navigator, 'geolocation', {
        get: () => fakeGeolocation,
        configurable: true
    });

    // --- Also patch DeviceOrientationEvent to inject compass ---
    // We'll dispatch fake events on the window
    function fireCompassEvent(heading) {
        try {
            const event = new Event('deviceorientation');
            event.alpha = (360 - heading) % 360; // Android convention
            event.webkitCompassHeading = heading;  // iOS convention
            event.beta = 0;
            event.gamma = 0;
            event.absolute = true;
            window.dispatchEvent(event);
        } catch (e) {
            // Silently fail if event creation isn't supported
        }
    }

    // --- Route Preparation ---
    function prepareSim() {
        // Wait for route data to be available
        const waitForRoute = setInterval(() => {
            if (window.lastRouteSegments && window.lastRouteSegments.length > 0) {
                clearInterval(waitForRoute);
                sim.routeCoords = flattenSegments(window.lastRouteSegments);
                sim.interpCoords = interpolateRoute(sim.routeCoords, 2); // 2m spacing
                sim.currentIdx = 0;

                // Pick random lateral offset
                sim.lateralSide = Math.random() > 0.5 ? 1 : -1;
                sim.lateralTarget = config.lateralOffsetMin +
                    Math.random() * (config.lateralOffsetMax - config.lateralOffsetMin);
                sim.lateralOffset = sim.lateralTarget;

                console.log(`[SIM] Route loaded: ${sim.routeCoords.length} points → ${sim.interpCoords.length} interpolated`);
                console.log(`[SIM] Lateral offset: ${sim.lateralOffset.toFixed(1)}m ${sim.lateralSide > 0 ? 'right' : 'left'} of route`);

                startSim();
            }
        }, 200);
    }

    // --- Interpolation: densify route to ~2m spacing ---
    function interpolateRoute(coords, spacingMeters) {
        if (coords.length < 2) return [...coords];
        const result = [coords[0]];

        for (let i = 0; i < coords.length - 1; i++) {
            const a = coords[i];
            const b = coords[i + 1];
            const dist = getDistance(a[0], a[1], b[0], b[1]);
            const steps = Math.max(1, Math.floor(dist / spacingMeters));

            for (let s = 1; s <= steps; s++) {
                const t = s / steps;
                result.push([
                    a[0] + (b[0] - a[0]) * t,
                    a[1] + (b[1] - a[1]) * t
                ]);
            }
        }
        return result;
    }

    // --- Start / Stop ---
    function startSim() {
        if (sim.active) return;
        sim.active = true;
        sim.paused = false;

        createPanel();
        scheduleNextTick();
        console.log('[SIM] Simulation started');
    }

    function stopSim() {
        sim.active = false;
        if (sim.tickInterval) {
            clearTimeout(sim.tickInterval);
            sim.tickInterval = null;
        }
        console.log('[SIM] Simulation stopped');
    }

    function scheduleNextTick() {
        if (!sim.active) return;
        const interval = config.tickMs / sim.speed;
        sim.tickInterval = setTimeout(() => {
            tick();
            scheduleNextTick();
        }, interval);
    }

    // --- Main Simulation Tick ---
    function tick() {
        if (sim.paused || !sim.watchCallback) return;
        if (sim.currentIdx >= sim.interpCoords.length) {
            console.log('[SIM] Route complete!');
            stopSim();
            return;
        }

        // Advance position: at 10mph with 1s ticks, move ~4.47m per tick
        // With 2m interpolation spacing, advance ~2 points per tick at 1x
        const pointsPerTick = Math.max(1, Math.round(config.riderSpeedMps / 2));
        sim.currentIdx = Math.min(sim.currentIdx + pointsPerTick, sim.interpCoords.length - 1);

        const baseCoord = sim.interpCoords[sim.currentIdx];

        // Calculate true bearing from route
        let trueBearing = 0;
        if (sim.currentIdx < sim.interpCoords.length - 1) {
            const next = sim.interpCoords[Math.min(sim.currentIdx + 5, sim.interpCoords.length - 1)];
            trueBearing = getBearing(baseCoord, next);
        } else if (sim.currentIdx > 0) {
            const prev = sim.interpCoords[sim.currentIdx - 5] || sim.interpCoords[0];
            trueBearing = getBearing(prev, baseCoord);
        }

        // --- Apply lateral offset (perpendicular to bearing) ---
        // Drift the offset slowly
        sim.lateralOffset += (Math.random() - 0.5) * 0.4; // ±0.2m drift per tick
        sim.lateralOffset = clamp(sim.lateralOffset, config.lateralOffsetMin - 1, config.lateralOffsetMax + 1);

        const perpBearing = trueBearing + (sim.lateralSide * 90); // 90° to the right/left
        const offsetLat = baseCoord[0] + (sim.lateralOffset / 111000) * Math.cos(perpBearing * Math.PI / 180);
        const offsetLng = baseCoord[1] + (sim.lateralOffset / (111000 * Math.cos(baseCoord[0] * Math.PI / 180))) * Math.sin(perpBearing * Math.PI / 180);

        // --- Apply GPS jitter ---
        const jitterLat = gaussianRandom() * (config.gpsJitter / 111000);
        const jitterLng = gaussianRandom() * (config.gpsJitter / (111000 * Math.cos(baseCoord[0] * Math.PI / 180)));

        let finalLat = offsetLat + jitterLat;
        let finalLng = offsetLng + jitterLng;

        // --- GPS spike (occasional wild reading) ---
        let accuracy = 5 + Math.random() * 8; // 5-13m typical
        if (Math.random() < config.gpsSpikeChance) {
            const spikeDist = 20 + Math.random() * 40; // 20-60m
            const spikeAngle = Math.random() * 360;
            finalLat += (spikeDist / 111000) * Math.cos(spikeAngle * Math.PI / 180);
            finalLng += (spikeDist / (111000 * Math.cos(baseCoord[0] * Math.PI / 180))) * Math.sin(spikeAngle * Math.PI / 180);
            accuracy = 30 + Math.random() * 20; // Bad accuracy reported
            console.log('[SIM] 💥 GPS spike!');
        }

        // --- Compass heading with jitter ---
        sim.compassTarget = trueBearing;
        let compassJitter = gaussianRandom() * config.compassJitter;
        // Occasional big swing
        if (Math.random() < config.compassBigSwingChance) {
            compassJitter += (Math.random() > 0.5 ? 1 : -1) * 25;
            console.log('[SIM] 🧭 Compass big swing');
        }
        // Smooth towards target with lag
        const headingDiff = shortestAngleDiff(sim.compassHeading, sim.compassTarget + compassJitter);
        sim.compassHeading = (sim.compassHeading + headingDiff * 0.6 + 360) % 360;

        // --- Build Position object and fire callback ---
        const position = buildPosition(finalLat, finalLng, accuracy);
        sim.watchCallback(position);

        // --- Fire compass event ---
        fireCompassEvent(sim.compassHeading);

        // --- Update panel ---
        updatePanel();
    }

    function buildPosition(lat, lng, accuracy) {
        return {
            coords: {
                latitude: lat,
                longitude: lng,
                accuracy: accuracy,
                speed: config.riderSpeedMps + (Math.random() - 0.5),
                heading: sim.compassHeading,
                altitude: 1630 + Math.random() * 5, // Boulder elevation ~1630m
                altitudeAccuracy: 10
            },
            timestamp: Date.now()
        };
    }

    // --- Floating Control Panel ---
    function createPanel() {
        if (sim.panel) return;

        const panel = document.createElement('div');
        panel.id = 'sim-panel';
        panel.innerHTML = `
            <div class="sim-header">
                <span class="sim-badge">🧪 SIM</span>
                <div class="sim-controls">
                    <button id="sim-play-pause" class="sim-btn">⏸</button>
                    <div class="sim-speeds">
                        <button class="sim-speed-btn sim-speed-active" data-speed="1">1x</button>
                        <button class="sim-speed-btn" data-speed="2">2x</button>
                        <button class="sim-speed-btn" data-speed="4">4x</button>
                        <button class="sim-speed-btn" data-speed="8">8x</button>
                    </div>
                </div>
                <button id="sim-dismiss" class="sim-btn sim-dismiss">✕</button>
            </div>
            <div class="sim-details">
                <span>GPS ±${config.gpsJitter}m</span>
                <span>Offset ${sim.lateralTarget.toFixed(0)}m</span>
                <span>Spike ${(config.gpsSpikeChance * 100).toFixed(0)}%</span>
            </div>
            <div class="sim-progress-wrap">
                <div class="sim-progress-bar" id="sim-progress-bar"></div>
            </div>
            <div class="sim-progress-text" id="sim-progress-text">0%</div>
        `;

        // Inject styles
        const style = document.createElement('style');
        style.textContent = `
            #sim-panel {
                position: fixed;
                top: 12px;
                right: 12px;
                z-index: 3000;
                background: rgba(18, 20, 26, 0.94);
                backdrop-filter: blur(16px);
                -webkit-backdrop-filter: blur(16px);
                border: 1px solid rgba(255, 179, 0, 0.25);
                border-radius: 12px;
                padding: 10px 14px;
                font-family: 'Outfit', sans-serif;
                color: #f8fafc;
                min-width: 240px;
                box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
                user-select: none;
            }
            .sim-header {
                display: flex;
                align-items: center;
                gap: 10px;
                margin-bottom: 8px;
            }
            .sim-badge {
                background: rgba(255, 179, 0, 0.15);
                border: 1px solid rgba(255, 179, 0, 0.3);
                color: #ffb300;
                padding: 2px 8px;
                border-radius: 6px;
                font-size: 11px;
                font-weight: 700;
                letter-spacing: 0.5px;
            }
            .sim-controls {
                display: flex;
                align-items: center;
                gap: 8px;
                flex-grow: 1;
            }
            .sim-btn {
                width: 28px;
                height: 28px;
                border-radius: 6px;
                border: 1px solid rgba(255, 255, 255, 0.1);
                background: rgba(255, 255, 255, 0.05);
                color: #f8fafc;
                font-size: 13px;
                cursor: pointer;
                display: flex;
                align-items: center;
                justify-content: center;
                transition: all 0.15s;
            }
            .sim-btn:hover {
                background: rgba(255, 255, 255, 0.1);
            }
            .sim-dismiss {
                margin-left: auto;
                color: #94a3b8;
            }
            .sim-speeds {
                display: flex;
                gap: 4px;
            }
            .sim-speed-btn {
                padding: 2px 7px;
                border-radius: 4px;
                border: 1px solid rgba(255, 255, 255, 0.08);
                background: rgba(255, 255, 255, 0.03);
                color: #94a3b8;
                font-family: inherit;
                font-size: 10px;
                font-weight: 600;
                cursor: pointer;
                transition: all 0.15s;
            }
            .sim-speed-btn:hover {
                background: rgba(255, 255, 255, 0.08);
                color: #f8fafc;
            }
            .sim-speed-active {
                background: rgba(255, 179, 0, 0.15);
                border-color: rgba(255, 179, 0, 0.3);
                color: #ffb300;
            }
            .sim-details {
                display: flex;
                gap: 12px;
                font-size: 10px;
                color: #94a3b8;
                margin-bottom: 6px;
            }
            .sim-progress-wrap {
                height: 4px;
                background: rgba(255, 255, 255, 0.06);
                border-radius: 2px;
                overflow: hidden;
                margin-bottom: 2px;
            }
            .sim-progress-bar {
                height: 100%;
                width: 0%;
                background: linear-gradient(90deg, #ffb300, #ff9100);
                border-radius: 2px;
                transition: width 0.3s ease;
            }
            .sim-progress-text {
                font-size: 10px;
                color: #94a3b8;
                text-align: right;
            }
        `;

        document.head.appendChild(style);
        document.body.appendChild(panel);
        sim.panel = panel;
        sim.progressBar = document.getElementById('sim-progress-bar');

        // --- Event listeners ---
        document.getElementById('sim-play-pause').addEventListener('click', () => {
            sim.paused = !sim.paused;
            document.getElementById('sim-play-pause').textContent = sim.paused ? '▶' : '⏸';
        });

        document.getElementById('sim-dismiss').addEventListener('click', () => {
            panel.style.display = 'none';
        });

        panel.querySelectorAll('.sim-speed-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                sim.speed = parseInt(btn.dataset.speed);
                panel.querySelectorAll('.sim-speed-btn').forEach(b => b.classList.remove('sim-speed-active'));
                btn.classList.add('sim-speed-active');
                // Reschedule tick with new speed
                if (sim.tickInterval) clearTimeout(sim.tickInterval);
                scheduleNextTick();
            });
        });
    }

    function updatePanel() {
        if (!sim.panel) return;
        const pct = sim.interpCoords.length > 0
            ? Math.round((sim.currentIdx / (sim.interpCoords.length - 1)) * 100)
            : 0;
        if (sim.progressBar) sim.progressBar.style.width = `${pct}%`;
        const textEl = document.getElementById('sim-progress-text');
        if (textEl) textEl.textContent = `${pct}%`;
    }

    // --- Geometry Helpers ---
    function flattenSegments(segments) {
        const coords = [];
        segments.forEach(seg => {
            if (seg.coords) {
                seg.coords.forEach(c => {
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

    function gaussianRandom() {
        // Box-Muller transform for gaussian distribution (mean=0, σ=1)
        let u = 0, v = 0;
        while (u === 0) u = Math.random();
        while (v === 0) v = Math.random();
        return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
    }

    function shortestAngleDiff(from, to) {
        let diff = to - from;
        while (diff > 180) diff -= 360;
        while (diff < -180) diff += 360;
        return diff;
    }

    function clamp(val, min, max) {
        return Math.max(min, Math.min(max, val));
    }
})();
