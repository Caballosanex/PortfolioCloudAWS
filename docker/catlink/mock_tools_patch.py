"""
Mock replacement for CatLink's agent/tools.py
Removes google.generativeai dependency.
Deploy: copy this over backend/src/agent/tools.py
"""

from src.services.nokia_service import nokia_service

GEMINI_TOOLS = []


async def execute_tool(tool_name: str, tool_input: dict) -> dict:
    """Ejecuta una herramienta y devuelve el resultado."""

    if tool_name == "verify_location":
        return await nokia_service.verify_location(
            phone=tool_input["phone"],
            target_lat=tool_input["charger_lat"],
            target_lon=tool_input["charger_lon"],
            user_lat=tool_input["user_lat"],
            user_lon=tool_input["user_lon"],
        )
    elif tool_name == "verify_number":
        return await nokia_service.verify_number(tool_input["phone"])
    elif tool_name == "check_sim_swap":
        return await nokia_service.check_sim_swap(tool_input["phone"])
    elif tool_name == "activate_qod":
        return await nokia_service.activate_qod(tool_input["phone"])
    else:
        return {"error": f"Unknown tool: {tool_name}"}
