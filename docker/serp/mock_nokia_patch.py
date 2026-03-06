"""
Patch for SERP's opencameragateway.py
Replaces Nokia API calls with mock responses.
Deploy: copy this over backend/src/services/opencameragateway.py
"""

import random
import uuid
from datetime import datetime


NOKIA_API_BASE_URL = "http://mock-nokia-api:6000/api/v1"  # Not used in mock mode


async def nokia_api_call(method: str, endpoint: str, json=None):
    """Mock Nokia API - returns realistic responses without external calls."""
    if "qos" in endpoint:
        return {
            "session_id": str(uuid.uuid4()),
            "profile": "QOS_E",
            "status": "ACTIVE",
            "device": json.get("device", "unknown") if json else "unknown",
            "started_at": datetime.now().isoformat(),
            "mock": True,
        }
    elif "location" in endpoint:
        return {
            "latitude": 41.3851 + random.uniform(-0.01, 0.01),
            "longitude": 2.1734 + random.uniform(-0.01, 0.01),
            "accuracy": random.randint(5, 50),
            "timestamp": datetime.now().isoformat(),
            "mock": True,
        }
    elif "device_status" in endpoint:
        return {
            "connected": True,
            "network_type": "5G",
            "signal_strength": random.randint(-80, -40),
            "mock": True,
        }
    else:
        return {"status": "ok", "mock": True}
