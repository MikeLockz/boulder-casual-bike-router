import unittest

import app as router


class MetricsTests(unittest.TestCase):
    def test_route_metric_labels_are_bounded_for_untrusted_region(self):
        client = router.app.test_client()
        response = client.post('/api/route', json={'region': 'untrusted-coordinate-or-token'})
        self.assertGreaterEqual(response.status_code, 400)
        metrics = client.get('/internal/metrics')
        self.assertEqual(metrics.status_code, 200)
        self.assertIn(b'boulder_route_requests_total{region="invalid"', metrics.data)
        self.assertNotIn(b'untrusted-coordinate-or-token', metrics.data)


if __name__ == '__main__':
    unittest.main()
