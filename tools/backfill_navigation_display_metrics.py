#!/usr/bin/env python3
"""Backfill canonical navigation display metrics in PocketBase."""

import datetime
import math
import os
import sys
from typing import Any

import requests


POCKETBASE_URL = os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090").rstrip("/")
ADMIN_EMAIL = os.environ.get("PB_ADMIN_EMAIL")
ADMIN_PASSWORD = os.environ.get("PB_ADMIN_PASSWORD")


def haversine_distance(coord1: tuple[float, float], coord2: tuple[float, float]) -> float:
    lat1, lon1 = coord1
    lat2, lon2 = coord2
    radius_meters = 6371000
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return radius_meters * c


def parse_date(value: Any) -> datetime.datetime | None:
    if not value:
        return None
    date_str = str(value).strip().replace("Z", "+00:00")
    if " " in date_str and "T" not in date_str:
        date_str = date_str.replace(" ", "T", 1)
    try:
        parsed = datetime.datetime.fromisoformat(date_str)
    except ValueError:
        if "." not in date_str:
            return None
        try:
            parsed = datetime.datetime.fromisoformat(date_str.split(".")[0] + "+00:00")
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    return parsed.astimezone(datetime.timezone.utc)


def sorted_ticks(ticks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    min_date = datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)
    return sorted(ticks, key=lambda tick: parse_date(tick.get("timestamp")) or min_date)


def tick_distance(ticks: list[dict[str, Any]]) -> float:
    ordered = sorted_ticks(ticks)
    total = 0.0
    for tick, next_tick in zip(ordered, ordered[1:]):
        if tick.get("lat") is None or tick.get("lon") is None or next_tick.get("lat") is None or next_tick.get("lon") is None:
            continue
        total += haversine_distance((tick["lat"], tick["lon"]), (next_tick["lat"], next_tick["lon"]))
    return total


def route_duration(route: dict[str, Any], ticks: list[dict[str, Any]]) -> float:
    started_at = parse_date(route.get("started_at"))
    ended_at = parse_date(route.get("ended_at"))
    if started_at and ended_at:
        duration = (ended_at - started_at).total_seconds()
        if duration > 0:
            return duration

    ordered = sorted_ticks(ticks)
    if len(ordered) >= 2:
        first_tick = parse_date(ordered[0].get("timestamp"))
        last_tick = parse_date(ordered[-1].get("timestamp"))
        if first_tick and last_tick:
            duration = (last_tick - first_tick).total_seconds()
            if duration > 0:
                return duration
    return 0.0


def calculate_metrics(route: dict[str, Any], ticks: list[dict[str, Any]]) -> dict[str, float]:
    actual_distance = tick_distance(ticks)
    actual_duration = route_duration(route, ticks)
    total_length = float(route.get("total_length_meters") or 0.0)
    total_duration = float(route.get("total_estimated_time_seconds") or 0.0)

    if route.get("status") == "completed" and total_length > 0 and actual_distance < total_length * 0.25:
        actual_distance = total_length

    stored_actual_distance = float(route.get("actual_distance_meters") or 0.0)
    stored_actual_duration = float(route.get("actual_duration_seconds") or 0.0)
    display_distance = actual_distance if actual_distance > 0 else (stored_actual_distance if stored_actual_distance > 0 else total_length)
    display_duration = actual_duration if actual_duration > 0 else (stored_actual_duration if stored_actual_duration > 0 else total_duration)
    if (
        display_distance > 500
        and total_duration > 0
        and (
            display_duration <= 0
            or display_duration < 60
            or (display_distance / display_duration) > 15.0
        )
    ):
        display_duration = total_duration

    return {
        "actual_distance_meters": actual_distance,
        "actual_duration_seconds": actual_duration,
        "average_speed": actual_distance / actual_duration if actual_duration > 0 else 0.0,
        "display_distance_meters": display_distance,
        "display_duration_seconds": display_duration,
        "display_average_speed": display_distance / display_duration if display_duration > 0 else 0.0,
    }


def get_headers() -> dict[str, str]:
    if not ADMIN_EMAIL or not ADMIN_PASSWORD:
        return {}
    response = requests.post(
        f"{POCKETBASE_URL}/api/admins/auth-with-password",
        json={"identity": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
        timeout=10,
    )
    response.raise_for_status()
    return {"Authorization": f"Bearer {response.json()['token']}"}


def fetch_all(collection: str, headers: dict[str, str], params: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    page = 1
    items: list[dict[str, Any]] = []
    while True:
        response = requests.get(
            f"{POCKETBASE_URL}/api/collections/{collection}/records",
            headers=headers,
            params={**(params or {}), "page": page, "perPage": 200},
            timeout=20,
        )
        response.raise_for_status()
        payload = response.json()
        items.extend(payload.get("items", []))
        if page >= payload.get("totalPages", 1):
            return items
        page += 1


def main() -> int:
    headers = get_headers()
    routes = fetch_all("navigation_routes", headers, {"sort": "started_at"})
    print(f"Found {len(routes)} navigation routes.")

    updated = 0
    for route in routes:
        route_id = route["id"]
        ticks = fetch_all("navigation_ticks", headers, {"filter": f"route='{route_id}'", "sort": "timestamp"})
        metrics = calculate_metrics(route, ticks)
        response = requests.patch(
            f"{POCKETBASE_URL}/api/collections/navigation_routes/records/{route_id}",
            headers=headers,
            json=metrics,
            timeout=20,
        )
        response.raise_for_status()
        updated += 1
        print(f"Backfilled {route_id}: {metrics['display_distance_meters']:.1f}m, {metrics['display_duration_seconds']:.1f}s")

    print(f"Backfill complete. Updated {updated} routes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
