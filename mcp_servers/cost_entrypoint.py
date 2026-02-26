"""Cost Explorer MCP Server entry point for AgentCore Runtime.

Runs a standalone FastMCP server with streamable-http transport so AgentCore
Gateway can route tool calls to it.

AgentCore requires MCP servers to be stateless HTTP on 0.0.0.0:8000/mcp.

The awslabs cost_explorer_mcp_server handlers use pydantic Field() as function
parameter defaults. When a caller omits an optional parameter, Python resolves
the default to a FieldInfo object (not the Field's default value), causing
"argument of type 'FieldInfo' is not iterable" errors inside the handlers.

Fix: create a fresh FastMCP app with clean wrapper tools that call the CE API
directly using plain Python defaults and Annotated types for descriptions.
"""

import json
import os
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any

from mcp.server.fastmcp import FastMCP
from pydantic import Field

# ---------------------------------------------------------------------------
# Fresh FastMCP server — no awslabs imports (avoids FieldInfo bug)
# ---------------------------------------------------------------------------
app = FastMCP(name="Cost Explorer MCP Server")

# ---------------------------------------------------------------------------
# Shared: boto3 CE client (cached)
# ---------------------------------------------------------------------------
_ce_client = None


def _get_ce():
    global _ce_client
    if _ce_client is None:
        import boto3

        region = os.environ.get("AWS_REGION", "us-east-1")
        _ce_client = boto3.Session(region_name=region).client("ce")
    return _ce_client


# ---------------------------------------------------------------------------
# Tools — call CE API directly with plain Python defaults
# ---------------------------------------------------------------------------


@app.tool()
async def get_today_date() -> str:
    """Get today's date in UTC. Use this to anchor cost query date ranges."""
    now = datetime.now(timezone.utc)
    return json.dumps(
        {"today_date_UTC": now.strftime("%Y-%m-%d"), "current_month": now.strftime("%Y-%m")},
        indent=2,
    )


@app.tool()
async def get_cost_and_usage(
    start_date: Annotated[str, Field(description="Start date in YYYY-MM-DD format")],
    end_date: Annotated[str, Field(description="End date in YYYY-MM-DD format (inclusive)")],
    granularity: Annotated[str, Field(description="DAILY, MONTHLY, or HOURLY")] = "MONTHLY",
    group_by: Annotated[str, Field(description="Dimension to group by (SERVICE, REGION, etc.)")] = "SERVICE",
    metric: Annotated[str, Field(description="Cost metric (BlendedCost, UnblendedCost, etc.)")] = "BlendedCost",
) -> str:
    """Get AWS cost and usage data for a date range, grouped by a dimension."""
    try:
        ce = _get_ce()
        end_adj = (datetime.strptime(end_date, "%Y-%m-%d") + timedelta(days=1)).strftime("%Y-%m-%d")
        params: dict[str, Any] = {
            "TimePeriod": {"Start": start_date, "End": end_adj},
            "Granularity": granularity.upper(),
            "GroupBy": [{"Type": "DIMENSION", "Key": group_by.upper()}],
            "Metrics": [metric],
        }
        results = []
        next_token = None
        while True:
            if next_token:
                params["NextPageToken"] = next_token
            response = ce.get_cost_and_usage(**params)
            for period in response["ResultsByTime"]:
                date = period["TimePeriod"]["Start"]
                for group in period.get("Groups", []):
                    key = group["Keys"][0] if group.get("Keys") else "Other"
                    amount = group["Metrics"][metric]["Amount"]
                    unit = group["Metrics"][metric].get("Unit", "USD")
                    results.append({"date": date, "group": key, "amount": amount, "unit": unit})
                if not period.get("Groups") and period.get("Total"):
                    amount = period["Total"][metric]["Amount"]
                    unit = period["Total"][metric].get("Unit", "USD")
                    results.append({"date": date, "group": "Total", "amount": amount, "unit": unit})
            next_token = response.get("NextPageToken")
            if not next_token:
                break
        return json.dumps(
            {
                "period": f"{start_date} to {end_date}",
                "granularity": granularity,
                "metric": metric,
                "group_by": group_by,
                "results": results,
            },
            indent=2,
        )
    except Exception as exc:
        return json.dumps({"error": str(exc), "type": type(exc).__name__})


@app.tool()
async def get_cost_forecast(
    start_date: Annotated[str, Field(description="Forecast start date YYYY-MM-DD")],
    end_date: Annotated[str, Field(description="Forecast end date (must be future) YYYY-MM-DD")],
    granularity: Annotated[str, Field(description="DAILY or MONTHLY")] = "MONTHLY",
    metric: Annotated[str, Field(description="BLENDED_COST, UNBLENDED_COST, etc.")] = "BLENDED_COST",
) -> str:
    """Forecast future AWS spending based on historical patterns."""
    try:
        ce = _get_ce()
        response = ce.get_cost_forecast(
            TimePeriod={"Start": start_date, "End": end_date},
            Granularity=granularity.upper(),
            Metric=metric,
        )
        total = response.get("Total", {})
        forecasts = [
            {"start": f["TimePeriod"]["Start"], "end": f["TimePeriod"]["End"], "mean": f["MeanValue"]}
            for f in response.get("ForecastResultsByTime", [])
        ]
        return json.dumps(
            {"total_forecast": total.get("Amount"), "unit": total.get("Unit", "USD"), "forecasts": forecasts},
            indent=2,
        )
    except Exception as exc:
        return json.dumps({"error": str(exc), "type": type(exc).__name__})


@app.tool()
async def get_dimension_values(
    start_date: Annotated[str, Field(description="Start date YYYY-MM-DD")],
    end_date: Annotated[str, Field(description="End date YYYY-MM-DD")],
    dimension: Annotated[str, Field(description="Dimension key (SERVICE, REGION, LINKED_ACCOUNT, etc.)")],
) -> str:
    """Get valid values for a Cost Explorer dimension."""
    try:
        ce = _get_ce()
        response = ce.get_dimension_values(
            TimePeriod={"Start": start_date, "End": end_date},
            Dimension=dimension.upper(),
        )
        values = [v["Value"] for v in response.get("DimensionValues", [])]
        return json.dumps({"dimension": dimension, "values": values}, indent=2)
    except Exception as exc:
        return json.dumps({"error": str(exc), "type": type(exc).__name__})


@app.tool()
async def get_tag_values(
    start_date: Annotated[str, Field(description="Start date YYYY-MM-DD")],
    end_date: Annotated[str, Field(description="End date YYYY-MM-DD")],
    tag_key: Annotated[str, Field(description="Cost allocation tag key")],
) -> str:
    """Get all values for a cost allocation tag key."""
    try:
        ce = _get_ce()
        response = ce.get_tags(
            TimePeriod={"Start": start_date, "End": end_date},
            TagKey=tag_key,
        )
        return json.dumps({"tag_key": tag_key, "values": response.get("Tags", [])}, indent=2)
    except Exception as exc:
        return json.dumps({"error": str(exc), "type": type(exc).__name__})


@app.tool()
async def get_cost_and_usage_comparisons(
    start_date: Annotated[str, Field(description="Current period start (1st of month) YYYY-MM-DD")],
    end_date: Annotated[str, Field(description="Current period end (1st of next month) YYYY-MM-DD")],
    comparison_start_date: Annotated[str, Field(description="Comparison period start YYYY-MM-DD")],
    comparison_end_date: Annotated[str, Field(description="Comparison period end YYYY-MM-DD")],
) -> str:
    """Compare spending between two monthly periods."""
    try:
        ce = _get_ce()
        current = ce.get_cost_and_usage(
            TimePeriod={"Start": start_date, "End": end_date},
            Granularity="MONTHLY",
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
            Metrics=["BlendedCost"],
        )
        comparison = ce.get_cost_and_usage(
            TimePeriod={"Start": comparison_start_date, "End": comparison_end_date},
            Granularity="MONTHLY",
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
            Metrics=["BlendedCost"],
        )

        def _extract(resp):
            out = {}
            for period in resp["ResultsByTime"]:
                for g in period.get("Groups", []):
                    out[g["Keys"][0]] = float(g["Metrics"]["BlendedCost"]["Amount"])
            return out

        curr, comp = _extract(current), _extract(comparison)
        all_services = sorted(set(list(curr.keys()) + list(comp.keys())))
        rows = []
        for svc in all_services:
            c, p = curr.get(svc, 0), comp.get(svc, 0)
            rows.append({"service": svc, "current": round(c, 4), "comparison": round(p, 4), "delta": round(c - p, 4)})
        return json.dumps(
            {
                "current_period": f"{start_date} to {end_date}",
                "comparison_period": f"{comparison_start_date} to {comparison_end_date}",
                "services": rows,
            },
            indent=2,
        )
    except Exception as exc:
        return json.dumps({"error": str(exc), "type": type(exc).__name__})


@app.tool()
async def get_cost_comparison_drivers(
    start_date: Annotated[str, Field(description="Current period start (1st of month) YYYY-MM-DD")],
    end_date: Annotated[str, Field(description="Current period end (1st of next month) YYYY-MM-DD")],
    comparison_start_date: Annotated[str, Field(description="Comparison period start YYYY-MM-DD")],
    comparison_end_date: Annotated[str, Field(description="Comparison period end YYYY-MM-DD")],
) -> str:
    """Identify what drove cost changes between two periods."""
    try:
        ce = _get_ce()
        current = ce.get_cost_and_usage(
            TimePeriod={"Start": start_date, "End": end_date},
            Granularity="MONTHLY",
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
            Metrics=["BlendedCost"],
        )
        comparison = ce.get_cost_and_usage(
            TimePeriod={"Start": comparison_start_date, "End": comparison_end_date},
            Granularity="MONTHLY",
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
            Metrics=["BlendedCost"],
        )

        def _extract(resp):
            out = {}
            for period in resp["ResultsByTime"]:
                for g in period.get("Groups", []):
                    out[g["Keys"][0]] = float(g["Metrics"]["BlendedCost"]["Amount"])
            return out

        curr, comp = _extract(current), _extract(comparison)
        drivers = []
        for svc in set(list(curr.keys()) + list(comp.keys())):
            c, p = curr.get(svc, 0), comp.get(svc, 0)
            delta = c - p
            if abs(delta) > 0.001:
                drivers.append({"service": svc, "current": round(c, 4), "previous": round(p, 4), "delta": round(delta, 4)})
        drivers.sort(key=lambda x: abs(x["delta"]), reverse=True)
        return json.dumps({"top_drivers": drivers[:10]}, indent=2)
    except Exception as exc:
        return json.dumps({"error": str(exc), "type": type(exc).__name__})


# ---------------------------------------------------------------------------
# AgentCore Runtime transport config
# ---------------------------------------------------------------------------
app.settings.host = "0.0.0.0"
app.settings.port = 8000
app.settings.stateless_http = True
app.settings.transport_security = None

app.run(transport="streamable-http")
