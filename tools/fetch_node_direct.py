import requests

node_id = 3338097013
overpass_url = "https://overpass-api.de/api/interpreter"
query = f"""
[out:json];
node({node_id});
out body;
"""

headers = {
    "User-Agent": "BoulderCasualBikeRouter/1.0 (contact: support@bouldercasualrouter.local)"
}
response = requests.post(overpass_url, data={"data": query}, headers=headers)
print("Direct Node Query:")
print("Status Code:", response.status_code)
print("Text:", response.text)
