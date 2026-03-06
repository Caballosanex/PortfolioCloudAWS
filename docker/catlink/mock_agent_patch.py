"""
Mock replacement for CatLink's agent.py
Replaces Gemini AI calls with deterministic mock responses.
Deploy: copy this over backend/src/agent/agent.py
"""

import os
import time
import asyncio
from datetime import datetime
from src.websocket.manager import manager

FRAUD_PHONES = {"+3672123456", "+34666666666", "+34699999999"}


class CatLinkAgent:
    """Mock agent - evaluates charge requests without Gemini."""

    def __init__(self):
        self._initialized = True

    def _ensure_initialized(self):
        pass

    async def evaluate_charge_request(
        self,
        charger: dict,
        user_phone: str,
        user_lat: float,
        user_lon: float,
    ) -> dict:
        start_time = time.time()
        logs = []

        await manager.broadcast({
            "type": "agent_log",
            "data": {
                "timestamp": datetime.now().isoformat(),
                "event": "start",
                "message": f"Evaluando: {user_phone} -> {charger['id']}"
            }
        })

        # Simulate tool calls with delays
        tools_sequence = [
            ("verify_location", {"phone": user_phone, "charger_lat": charger["lat"],
                                  "charger_lon": charger["lon"], "user_lat": user_lat,
                                  "user_lon": user_lon}),
            ("verify_number", {"phone": user_phone}),
            ("check_sim_swap", {"phone": user_phone}),
        ]

        is_fraud = user_phone in FRAUD_PHONES

        for tool_name, tool_input in tools_sequence:
            await asyncio.sleep(0.5)

            if tool_name == "verify_location":
                from math import radians, sin, cos, sqrt, atan2
                R = 6371000
                lat1, lon1 = radians(user_lat), radians(user_lon)
                lat2, lon2 = radians(charger["lat"]), radians(charger["lon"])
                dlat, dlon = lat2 - lat1, lon2 - lon1
                a = sin(dlat/2)**2 + cos(lat1)*cos(lat2)*sin(dlon/2)**2
                distance = R * 2 * atan2(sqrt(a), sqrt(1-a))
                result = {"verified": distance <= 1500, "distance_m": round(distance, 2),
                          "radius_m": 1500, "mock": True, "api": "location_verification"}
            elif tool_name == "verify_number":
                result = {"verified": True, "phone": user_phone, "mock": True,
                          "api": "number_verification"}
            elif tool_name == "check_sim_swap":
                result = {"swapped_recently": is_fraud, "last_swap_date": None,
                          "risk_level": "high" if is_fraud else "low",
                          "mock": True, "api": "sim_swap"}

            log_entry = {
                "timestamp": datetime.now().isoformat(),
                "tool": tool_name,
                "input": tool_input,
                "output": result,
            }
            logs.append(log_entry)
            await manager.broadcast({"type": "agent_log", "data": log_entry})

        # QoD activation for approved requests
        qod_session_id = None
        if not is_fraud:
            await asyncio.sleep(0.3)
            import uuid
            qod_session_id = f"qod-mock-{uuid.uuid4().hex[:8]}"
            log_entry = {
                "timestamp": datetime.now().isoformat(),
                "tool": "activate_qod",
                "input": {"phone": user_phone},
                "output": {"session_id": qod_session_id, "profile": "QOS_L",
                           "status": "active", "mock": True, "api": "qod"},
            }
            logs.append(log_entry)
            await manager.broadcast({"type": "agent_log", "data": log_entry})

        processing_time = int((time.time() - start_time) * 1000)

        if is_fraud:
            decision = "REJECT_FRAUD"
            reason = ("SIM swap detected within the last 24 hours. "
                      "This is a strong indicator of potential fraud.")
            user_message = ("Your request has been flagged for security review. "
                            "Please contact support if you believe this is an error.")
            confidence = 0.92
        else:
            decision = "APPROVE"
            reason = ("All security checks passed. Location verified. "
                      "Phone identity confirmed. No SIM swap detected. "
                      "Quality-on-Demand session activated.")
            user_message = "Your charging session has been approved! You may begin charging now."
            confidence = 0.95

        await manager.broadcast({
            "type": "agent_log",
            "data": {
                "timestamp": datetime.now().isoformat(),
                "event": "decision",
                "decision": decision,
                "reason": reason,
            }
        })

        return {
            "decision": decision,
            "reason": reason,
            "user_message": user_message,
            "confidence": confidence,
            "logs": logs,
            "qod_session_id": qod_session_id,
            "processing_time_ms": processing_time,
        }


# Singleton
agent = CatLinkAgent()
