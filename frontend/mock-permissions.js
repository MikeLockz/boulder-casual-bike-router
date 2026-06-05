// Permissions Mocking Utility for Boulder Casual Bike Router
// Intercepts and overrides global browser APIs (Geolocation, Device Orientation, Wake Lock)
// to simulate different permission states based on local storage configurations.

(function () {
    'use strict';

    console.log('%c[MOCK] Permissions Mocking System initialized', 'color: #64ffda; font-weight: bold;');

    // Helper to log mocking actions in styling colors
    function logMock(apiName, action) {
        console.log(`%c[MOCK] ${apiName}: ${action}`, 'color: #00e5ff; font-style: italic;');
    }

    // ----------------------------------------------------
    // 1. GEOLOCATION MOCKING
    // ----------------------------------------------------
    const realGeolocation = navigator.geolocation;
    let watchCallbacks = {};
    let watchErrorCallbacks = {};
    let watchIntervals = {};
    let nextWatchId = 1000;

    const fakeGeolocation = {
        getCurrentPosition: function (success, error, options) {
            const state = localStorage.getItem("mock_geolocation_state") || "default";
            
            if (state === "default") {
                if (realGeolocation) {
                    realGeolocation.getCurrentPosition(success, error, options);
                } else {
                    error({ code: 2, message: "Geolocation not supported by this browser" });
                }
                return;
            }

            logMock("Geolocation (getCurrentPosition)", `Simulating state: ${state}`);

            if (state === "denied") {
                setTimeout(() => error({ code: 1, message: "User denied Geolocation access (Mocked)" }), 300);
            } else if (state === "unavailable") {
                setTimeout(() => error({ code: 2, message: "Position unavailable (Mocked)" }), 300);
            } else if (state === "timeout") {
                setTimeout(() => error({ code: 3, message: "Location request timed out (Mocked)" }), 300);
            } else if (state === "slow") {
                logMock("Geolocation", "Delaying location response by 5 seconds...");
                setTimeout(() => {
                    success({
                        coords: {
                            latitude: 40.015,
                            longitude: -105.270,
                            accuracy: 10,
                            speed: null,
                            heading: null
                        },
                        timestamp: Date.now()
                    });
                }, 5000);
            } else if (state === "granted") {
                setTimeout(() => {
                    success({
                        coords: {
                            latitude: 40.028446,
                            longitude: -105.281088,
                            accuracy: 5,
                            speed: null,
                            heading: null
                        },
                        timestamp: Date.now()
                    });
                }, 200);
            }
        },

        watchPosition: function (success, error, options) {
            const state = localStorage.getItem("mock_geolocation_state") || "default";

            if (state === "default") {
                if (realGeolocation) {
                    return realGeolocation.watchPosition(success, error, options);
                } else {
                    error({ code: 2, message: "Geolocation not supported by this browser" });
                    return 0;
                }
            }

            const watchId = nextWatchId++;
            logMock("Geolocation (watchPosition)", `Simulating state: ${state} (WatchID: ${watchId})`);

            watchCallbacks[watchId] = success;
            watchErrorCallbacks[watchId] = error;

            if (state === "denied") {
                setTimeout(() => error({ code: 1, message: "User denied Geolocation access (Mocked)" }), 300);
            } else if (state === "unavailable") {
                setTimeout(() => error({ code: 2, message: "Position unavailable (Mocked)" }), 300);
            } else if (state === "timeout") {
                setTimeout(() => error({ code: 3, message: "Location request timed out (Mocked)" }), 300);
            } else {
                // granted or slow
                let count = 0;
                const fireUpdate = () => {
                    // Slight drift around Boulder / Valmont Park area to simulate movement
                    const baseLat = 40.028446;
                    const baseLng = -105.281088;
                    const driftLat = Math.sin(count / 10) * 0.0005;
                    const driftLng = Math.cos(count / 10) * 0.0005;
                    
                    success({
                        coords: {
                            latitude: baseLat + driftLat,
                            longitude: baseLng + driftLng,
                            accuracy: 5,
                            speed: 4.47,
                            heading: (count * 10) % 360
                        },
                        timestamp: Date.now()
                    });
                    count++;
                };

                const delay = state === "slow" ? 5000 : 200;
                setTimeout(() => {
                    fireUpdate();
                    watchIntervals[watchId] = setInterval(fireUpdate, 1000);
                }, delay);
            }

            return watchId;
        },

        clearWatch: function (id) {
            logMock("Geolocation (clearWatch)", `Clearing watch ID: ${id}`);
            if (watchIntervals[id]) {
                clearInterval(watchIntervals[id]);
                delete watchIntervals[id];
            }
            if (watchCallbacks[id]) delete watchCallbacks[id];
            if (watchErrorCallbacks[id]) delete watchErrorCallbacks[id];

            if (realGeolocation) {
                realGeolocation.clearWatch(id);
            }
        }
    };

    // Override Geolocation property
    Object.defineProperty(navigator, 'geolocation', {
        get: () => fakeGeolocation,
        configurable: true
    });

    // Override Permissions API for Geolocation query
    if (navigator.permissions && navigator.permissions.query) {
        const originalPermissionsQuery = navigator.permissions.query;
        navigator.permissions.query = function (queryObj) {
            if (queryObj && queryObj.name === 'geolocation') {
                const state = localStorage.getItem("mock_geolocation_state") || "default";
                logMock("Permissions Query", `Intercepting geolocation state check. Returning: ${state}`);
                
                if (state === "granted") {
                    return Promise.resolve({ state: 'granted', onchange: null });
                } else if (state === "denied") {
                    return Promise.resolve({ state: 'denied', onchange: null });
                } else if (state === "default" || state === "slow") {
                    return Promise.resolve({ state: 'prompt', onchange: null });
                } else {
                    // unavailable/timeout can be treated as prompt or denied
                    return Promise.resolve({ state: 'prompt', onchange: null });
                }
            }
            return originalPermissionsQuery.call(navigator.permissions, queryObj);
        };
    }

    // ----------------------------------------------------
    // 2. DEVICE COMPASS (ORIENTATION) MOCKING
    // ----------------------------------------------------
    const orientationListeners = new Set();
    let orientationInterval = null;

    // Wrap event listeners on window to capture deviceorientation listeners
    const originalAddEventListener = window.addEventListener;
    const originalRemoveEventListener = window.removeEventListener;

    window.addEventListener = function (type, listener, options) {
        if (type === 'deviceorientation') {
            orientationListeners.add(listener);
            startMockOrientationTicks();
        }
        return originalAddEventListener.call(window, type, listener, options);
    };

    window.removeEventListener = function (type, listener, options) {
        if (type === 'deviceorientation') {
            orientationListeners.delete(listener);
            if (orientationListeners.size === 0 && orientationInterval) {
                clearInterval(orientationInterval);
                orientationInterval = null;
            }
        }
        return originalRemoveEventListener.call(window, type, listener, options);
    };

    function startMockOrientationTicks() {
        if (orientationInterval) return;
        orientationInterval = setInterval(() => {
            const compassState = localStorage.getItem("mock_compass_state") || "default";
            if (compassState === "granted") {
                const mockHeading = (45 + Math.sin(Date.now() / 4000) * 20 + 360) % 360;
                
                const event = new Event('deviceorientation');
                event.alpha = (360 - mockHeading) % 360; // Android alpha convention
                event.webkitCompassHeading = mockHeading;  // iOS webkit convention
                event.beta = 0;
                event.gamma = 0;
                event.absolute = true;

                orientationListeners.forEach(listener => {
                    try {
                        listener(event);
                    } catch (err) {
                        console.error("[MOCK] Error in mocked compass listener:", err);
                    }
                });
            }
        }, 1000);
    }

    // Polyfill or override DeviceOrientationEvent.requestPermission for iOS simulator testing
    if (typeof DeviceOrientationEvent === 'undefined') {
        window.DeviceOrientationEvent = function() {};
    }

    DeviceOrientationEvent.requestPermission = function () {
        const compassState = localStorage.getItem("mock_compass_state") || "default";
        logMock("DeviceOrientation", `requestPermission checked. Returning: ${compassState}`);

        if (compassState === "default") {
            // If the browser natively has it, call it, otherwise return granted as fallback
            if (typeof DeviceOrientationEvent.prototype !== 'undefined' && 
                typeof DeviceOrientationEvent.prototype.requestPermission === 'function') {
                return DeviceOrientationEvent.prototype.requestPermission();
            }
            return Promise.resolve('granted');
        }

        if (compassState === "granted") {
            return Promise.resolve('granted');
        } else if (compassState === "denied") {
            return Promise.resolve('denied');
        } else {
            // unsupported
            return Promise.reject(new Error("DeviceOrientation is not supported by this device"));
        }
    };

    // ----------------------------------------------------
    // 3. WAKE LOCK API MOCKING
    // ----------------------------------------------------
    if (!navigator.wakeLock) {
        navigator.wakeLock = {};
    }

    const originalWakeLockRequest = navigator.wakeLock.request;
    navigator.wakeLock.request = function (type) {
        const state = localStorage.getItem("mock_wakelock_state") || "default";
        
        if (state === "default") {
            if (originalWakeLockRequest) {
                return originalWakeLockRequest.call(navigator.wakeLock, type);
            } else {
                return Promise.reject(new TypeError("Wake Lock API is not supported by this browser"));
            }
        }

        logMock("WakeLock", `request lock: ${type}. Simulating state: ${state}`);

        if (state === "unsupported") {
            return Promise.reject(new TypeError("navigator.wakeLock is not defined (mocked)"));
        }
        if (state === "denied") {
            return Promise.reject(new DOMException("Wake Lock permission denied (mocked)", "NotAllowedError"));
        }

        // granted
        return Promise.resolve({
            released: false,
            type: type,
            addEventListener: function (evt, cb) {},
            removeEventListener: function (evt, cb) {},
            release: function () {
                this.released = true;
                logMock("WakeLock", "Sentinel released");
                return Promise.resolve();
            }
        });
    };

})();
