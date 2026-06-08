// Shared navigation metric filtering for web, iOS, and Flask implementations.
// Keep these constants in sync with backend/app.py and NavigationMetricFilter.swift.
window.NavigationMetricFilter = (() => {
    const CONFIG = {
        maxAccuracyMeters: 75.0,
        stationaryRadiusMeters: 65.0,
        idleAutoEndSeconds: 2700.0,
        maxStepSpeedMps: 15.0
    };

    function distanceMeters(a, b) {
        const lat1 = Number(a.lat);
        const lon1 = Number(a.lon ?? a.lng);
        const lat2 = Number(b.lat);
        const lon2 = Number(b.lon ?? b.lng);
        const radius = 6371000;
        const phi1 = lat1 * Math.PI / 180;
        const phi2 = lat2 * Math.PI / 180;
        const deltaPhi = (lat2 - lat1) * Math.PI / 180;
        const deltaLambda = (lon2 - lon1) * Math.PI / 180;
        const x = Math.sin(deltaPhi / 2) ** 2
            + Math.cos(phi1) * Math.cos(phi2) * Math.sin(deltaLambda / 2) ** 2;
        return radius * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
    }

    function parsedTick(tick) {
        if (!tick) return null;
        const lat = Number(tick.lat);
        const lon = Number(tick.lon ?? tick.lng);
        const ts = new Date(tick.timestamp).getTime();
        if (!Number.isFinite(lat) || !Number.isFinite(lon) || !Number.isFinite(ts)) return null;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
        const accuracy = tick.accuracy == null ? null : Number(tick.accuracy);
        if (Number.isFinite(accuracy) && accuracy > CONFIG.maxAccuracyMeters) return null;
        return { ...tick, lat, lon, _ts: ts };
    }

    function summarizeTicks(ticks) {
        const usable = (ticks || [])
            .map(parsedTick)
            .filter(Boolean)
            .sort((a, b) => a._ts - b._ts);
        if (usable.length === 0) {
            return { ticks: [], distanceMeters: 0, durationSeconds: 0, idleCutoffAt: null };
        }

        const kept = [usable[0]];
        let anchor = usable[0];
        let distance = 0;
        let idleCutoffAt = null;

        for (let i = 1; i < usable.length; i++) {
            const tick = usable[i];
            const elapsedSeconds = Math.max(0, (tick._ts - anchor._ts) / 1000);
            const stepDistance = distanceMeters(anchor, tick);

            if (elapsedSeconds > 0 && stepDistance / elapsedSeconds > CONFIG.maxStepSpeedMps) {
                continue;
            }

            if (stepDistance <= CONFIG.stationaryRadiusMeters) {
                if (elapsedSeconds >= CONFIG.idleAutoEndSeconds) {
                    idleCutoffAt = new Date(anchor._ts + CONFIG.idleAutoEndSeconds * 1000).toISOString();
                    break;
                }
                kept.push(tick);
                continue;
            }

            distance += stepDistance;
            anchor = tick;
            kept.push(tick);
        }

        const firstTs = kept[0]?._ts;
        const lastTs = kept[kept.length - 1]?._ts;
        return {
            ticks: kept,
            distanceMeters: distance,
            durationSeconds: firstTs && lastTs ? Math.max(0, (lastTs - firstTs) / 1000) : 0,
            idleCutoffAt
        };
    }

    function shouldAutoEndForIdle(anchor, current, nowMs = Date.now()) {
        if (!anchor || !current) return false;
        const elapsedSeconds = Math.max(0, (nowMs - anchor.timestampMs) / 1000);
        return distanceMeters(anchor, current) <= CONFIG.stationaryRadiusMeters
            && elapsedSeconds >= CONFIG.idleAutoEndSeconds;
    }

    return { CONFIG, distanceMeters, summarizeTicks, shouldAutoEndForIdle };
})();
