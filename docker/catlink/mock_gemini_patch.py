"""
Patch for CatLink's agent.py
Replaces Gemini AI calls with deterministic mock responses.
Deploy: integrated via GEMINI_MOCK_MODE=true env var.
This file is applied as a monkey-patch in the backend startup.
"""

import json
import asyncio
from datetime import datetime


MOCK_RESPONSES = {
    "approve": {
        "decision": "APPROVE",
        "reason": "All security checks passed. Location verified (within 500m of charger). "
                  "Phone identity confirmed. No SIM swap detected in the last 24 hours. "
                  "Quality-on-Demand session activated for optimal charging experience.",
        "user_message": "Your charging session has been approved! You may begin charging now.",
        "confidence": 0.95,
    },
    "reject_location": {
        "decision": "REJECT_LOCATION",
        "reason": "Location verification failed. The user's reported position is more than "
                  "1500m from the charger station. This could indicate GPS spoofing or an "
                  "incorrect station selection.",
        "user_message": "We couldn't verify your location near the charger. Please make sure "
                       "you're physically at the charging station and try again.",
        "confidence": 0.88,
    },
    "reject_fraud": {
        "decision": "REJECT_FRAUD",
        "reason": "SIM swap detected within the last 24 hours. This is a strong indicator "
                  "of potential fraud. The charging request has been blocked for security.",
        "user_message": "Your request has been flagged for security review. Please contact "
                       "support if you believe this is an error.",
        "confidence": 0.92,
    },
}

FRAUD_PHONES = {"+3672123456", "+34666666666", "+34699999999"}


def get_mock_agent_logs(decision_type: str, charger_name: str, phone: str):
    """Generate realistic-looking agent execution logs."""
    return [
        {
            "type": "tool_call",
            "tool": "verify_location",
            "input": {"phone": phone, "radius_m": 1500},
            "output": {"verified": decision_type != "reject_location", "distance_m": 342 if decision_type != "reject_location" else 3200},
            "timestamp": datetime.now().isoformat(),
        },
        {
            "type": "tool_call",
            "tool": "verify_number",
            "input": {"phone": phone},
            "output": {"verified": True, "phone": phone},
            "timestamp": datetime.now().isoformat(),
        },
        {
            "type": "tool_call",
            "tool": "check_sim_swap",
            "input": {"phone": phone, "max_age_hours": 24},
            "output": {"swapped_recently": decision_type == "reject_fraud", "risk_level": "high" if decision_type == "reject_fraud" else "low"},
            "timestamp": datetime.now().isoformat(),
        },
    ]

    if decision_type == "approve":
        logs.append({
            "type": "tool_call",
            "tool": "activate_qod",
            "input": {"phone": phone, "profile": "QOS_L"},
            "output": {"session_id": "mock-qod-session-001", "status": "ACTIVE"},
            "timestamp": datetime.now().isoformat(),
        })

    return logs


async def mock_evaluate_charge_request(charger, user_phone, user_lat, user_lon):
    """Mock replacement for CatLinkAgent.evaluate_charge_request()."""
    await asyncio.sleep(1.5)  # Simulate processing time

    if user_phone in FRAUD_PHONES:
        decision_type = "reject_fraud"
    else:
        decision_type = "approve"

    response = MOCK_RESPONSES[decision_type].copy()
    logs = get_mock_agent_logs(decision_type, getattr(charger, 'name', 'Station'), user_phone)

    return {
        "decision": response,
        "logs": logs,
    }
