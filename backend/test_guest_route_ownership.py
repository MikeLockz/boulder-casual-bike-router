import hashlib
import unittest
from unittest.mock import Mock, patch

from backend import app as app_module


class GuestRouteOwnershipTests(unittest.TestCase):
    route_id = "t9q66n2cdsbwsn8"
    guest_id = "installation-a"
    guest_token = "secret-a"

    @property
    def owner_hash(self):
        return hashlib.sha256(
            f"{self.guest_id}:{self.guest_token}".encode("utf-8")
        ).hexdigest()

    def route_response(self, **overrides):
        route = {
            "id": self.route_id,
            "user": "",
            "guest_owner_hash": self.owner_hash,
        }
        route.update(overrides)
        response = Mock(status_code=200)
        response.json.return_value = route
        return response

    def authorize(self, headers, route_response=None, auth_user=None):
        with app_module.app.test_request_context("/", headers=headers):
            with patch.object(app_module.requests, "get", return_value=route_response or self.route_response()):
                with patch.object(app_module, "get_auth_user_id", return_value=auth_user):
                    return app_module.get_navigation_route_for_user(
                        "http://pocketbase", self.route_id, headers.get("Authorization")
                    )

    def test_matching_guest_can_access_route(self):
        route, user_id, error = self.authorize({
            "X-Guest-Id": self.guest_id,
            "X-Guest-Token": self.guest_token,
        })
        self.assertIsNone(error)
        self.assertEqual(route["id"], self.route_id)
        self.assertIsNone(user_id)

    def test_different_guest_is_forbidden(self):
        route, _, error = self.authorize({
            "X-Guest-Id": "installation-b",
            "X-Guest-Token": "secret-b",
        })
        self.assertIsNone(route)
        self.assertEqual(error[1], 403)

    def test_missing_guest_credentials_are_rejected(self):
        route, _, error = self.authorize({})
        self.assertIsNone(route)
        self.assertEqual(error[1], 401)

    def test_authenticated_owner_does_not_bypass_guest_ownership(self):
        route, _, error = self.authorize(
            {"Authorization": "Bearer valid"}, auth_user="user-a"
        )
        self.assertIsNone(route)
        self.assertEqual(error[1], 401)

    def test_authenticated_user_can_migrate_legacy_guest_route(self):
        legacy = self.route_response(guest_owner_hash="")
        route, user_id, error = self.authorize(
            {"Authorization": "Bearer valid"},
            route_response=legacy,
            auth_user="user-a",
        )
        self.assertIsNone(error)
        self.assertEqual(route["id"], self.route_id)
        self.assertEqual(user_id, "user-a")

    def test_guest_owner_hash_is_not_returned_to_clients(self):
        route = app_module.route_with_display_metrics({
            "guest_owner_hash": self.owner_hash,
            "total_length_meters": 100,
            "total_estimated_time_seconds": 20,
        })
        self.assertNotIn("guest_owner_hash", route)


if __name__ == "__main__":
    unittest.main()
