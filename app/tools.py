"""Demo tools for the AgentCore showcase.

Three lightweight tools that demonstrate the Strands @tool pattern
with context injection via invocation_state.  No external API calls.
"""

from __future__ import annotations

import logging
import random
from datetime import datetime, timedelta, timezone

from strands import tool
from strands.types.tools import ToolContext

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Pure business-logic helpers (no framework dependency)
# ---------------------------------------------------------------------------

_WEATHER_DATA = {
    "new york": {"temp_c": 22, "condition": "Partly cloudy", "humidity": 65},
    "london": {"temp_c": 15, "condition": "Overcast", "humidity": 80},
    "tokyo": {"temp_c": 28, "condition": "Sunny", "humidity": 55},
    "sydney": {"temp_c": 19, "condition": "Clear", "humidity": 50},
    "paris": {"temp_c": 18, "condition": "Light rain", "humidity": 75},
    "berlin": {"temp_c": 16, "condition": "Cloudy", "humidity": 70},
    "dubai": {"temp_c": 38, "condition": "Sunny", "humidity": 30},
    "singapore": {"temp_c": 31, "condition": "Thunderstorms", "humidity": 85},
}

_TIMEZONE_OFFSETS: dict[str, float] = {
    "utc": 0, "gmt": 0,
    "est": -5, "cst": -6, "mst": -7, "pst": -8,
    "cet": 1, "eet": 2, "ist": 5.5, "jst": 9, "aest": 10,
    "us/eastern": -5, "us/pacific": -8,
    "europe/london": 0, "europe/paris": 1,
    "asia/tokyo": 9, "asia/singapore": 8,
}

_JOKES: dict[str, list[str]] = {
    "programming": [
        "Why do programmers prefer dark mode? Because light attracts bugs.",
        "There are only 10 types of people: those who understand binary and those who don't.",
        "A SQL query walks into a bar, sees two tables, and asks: 'Can I JOIN you?'",
    ],
    "cloud": [
        "Why did the cloud architect break up? Too many attachment issues.",
        "I told my server a joke. It didn't laugh -- it just returned 200 OK.",
        "There's no place like 127.0.0.1.",
    ],
    "general": [
        "Why don't scientists trust atoms? Because they make up everything.",
        "I would tell you a UDP joke, but you might not get it.",
        "Why did the developer go broke? Because he used up all his cache.",
    ],
}


def _get_weather(city: str) -> str:
    key = city.strip().lower()
    data = _WEATHER_DATA.get(key)
    if data is None:
        available = ", ".join(sorted(_WEATHER_DATA.keys()))
        return f"No weather data for '{city}'. Available cities: {available}"
    return (
        f"Weather in {city.title()}: {data['condition']}, "
        f"{data['temp_c']}\u00b0C, humidity {data['humidity']}%"
    )


def _get_time(tz: str) -> str:
    key = tz.strip().lower()
    offset = _TIMEZONE_OFFSETS.get(key)
    if offset is None:
        available = ", ".join(sorted(_TIMEZONE_OFFSETS.keys()))
        return f"Unknown timezone '{tz}'. Available: {available}"
    now = datetime.now(timezone.utc) + timedelta(hours=offset)
    return f"Current time in {tz.upper()}: {now.strftime('%Y-%m-%d %H:%M:%S')}"


def _get_joke(topic: str) -> str:
    key = topic.strip().lower()
    jokes = _JOKES.get(key, _JOKES["general"])
    return random.choice(jokes)


# ---------------------------------------------------------------------------
# @tool wrappers (Strands Agent interface)
# ---------------------------------------------------------------------------


@tool(context=True)
def get_weather(city: str, tool_context: ToolContext) -> str:
    """Get the current weather for a city.

    Args:
        city: City name (e.g. "New York", "London", "Tokyo").
    """
    result = _get_weather(city)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "get_weather", "args": {"city": city}}
    )
    return result


@tool(context=True)
def get_time(timezone_name: str, tool_context: ToolContext) -> str:
    """Get the current time in a specific timezone.

    Args:
        timezone_name: Timezone identifier (e.g. "EST", "UTC", "JST", "PST").
    """
    result = _get_time(timezone_name)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "get_time", "args": {"timezone": timezone_name}}
    )
    return result


@tool(context=True)
def tell_joke(topic: str, tool_context: ToolContext) -> str:
    """Tell a joke about a topic.

    Args:
        topic: Topic for the joke (e.g. "programming", "cloud", "general").
    """
    result = _get_joke(topic)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "tell_joke", "args": {"topic": topic}}
    )
    return result
