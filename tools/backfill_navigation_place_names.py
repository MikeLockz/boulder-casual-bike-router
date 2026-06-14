#!/usr/bin/env python3
"""Backfill nearest-place labels on PocketBase navigation routes."""

import argparse
import os
import sys
from typing import Any

import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from backend.app import resolved_near_name


def auth_headers(pb_url: str) -> dict[str, str]:
    email = os.environ.get("POCKETBASE_ADMIN_EMAIL") or os.environ.get("PB_ADMIN_EMAIL")
    password = os.environ.get("POCKETBASE_ADMIN_PASSWORD") or os.environ.get("PB_ADMIN_PASSWORD")
    if not email or not password:
        return {}

    last_error = None
    for path in ("/api/collections/_superusers/auth-with-password", "/api/admins/auth-with-password"):
        response = requests.post(
            f"{pb_url}{path}",
            json={"identity": email, "email": email, "password": password},
            timeout=15,
        )
        if response.status_code == 200 and response.json().get("token"):
            return {"Authorization": f"Bearer {response.json()['token']}"}
        last_error = f"{response.status_code}: {response.text[:300]}"
    raise RuntimeError(f"PocketBase admin authentication failed: {last_error}")


def fetch_routes(pb_url: str, headers: dict[str, str]) -> list[dict[str, Any]]:
    routes = []
    page = 1
    while True:
        response = requests.get(
            f"{pb_url}/api/collections/navigation_routes/records",
            headers=headers,
            params={"page": page, "perPage": 200, "sort": "started_at"},
            timeout=30,
        )
        response.raise_for_status()
        payload = response.json()
        routes.extend(payload.get("items", []))
        if page >= payload.get("totalPages", 1):
            return routes
        page += 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pb-url", default=os.environ.get("POCKETBASE_URL", "http://127.0.0.1:8090"))
    parser.add_argument("--apply", action="store_true", help="Write updates. Without this flag the command is a dry run.")
    parser.add_argument("--force", action="store_true", help="Recompute fields that are already populated.")
    args = parser.parse_args()

    pb_url = args.pb_url.rstrip("/")
    headers = auth_headers(pb_url)
    routes = fetch_routes(pb_url, headers)
    cache: dict[tuple[float, float], str | None] = {}
    counts = {"routes": len(routes), "changed": 0, "updated": 0, "unresolved": 0, "failed": 0}

    def resolve(lat: Any, lon: Any) -> str | None:
        try:
            key = (float(lat), float(lon))
        except (TypeError, ValueError):
            return None
        if key not in cache:
            cache[key] = resolved_near_name(key[0], key[1], pb_url=pb_url)
        return cache[key]

    for route in routes:
        update = {}
        for endpoint in ("start", "end"):
            field = f"{endpoint}_near_name"
            if route.get(field) and not args.force:
                continue
            name = resolve(route.get(f"{endpoint}_lat"), route.get(f"{endpoint}_lon"))
            if name:
                update[field] = name
            else:
                counts["unresolved"] += 1

        if not update:
            continue
        counts["changed"] += 1
        print(f"{route['id']}: {update}")
        if not args.apply:
            continue
        try:
            response = requests.patch(
                f"{pb_url}/api/collections/navigation_routes/records/{route['id']}",
                headers=headers,
                json=update,
                timeout=30,
            )
            response.raise_for_status()
            counts["updated"] += 1
        except requests.RequestException as exc:
            counts["failed"] += 1
            print(f"Failed {route['id']}: {exc}", file=sys.stderr)

    mode = "APPLY" if args.apply else "DRY RUN"
    print(
        f"{mode}: {counts['routes']} routes, {counts['changed']} needing changes, "
        f"{counts['updated']} updated, {counts['unresolved']} unresolved endpoints, "
        f"{counts['failed']} failed."
    )
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
