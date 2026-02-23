"""AWS account inspection tools for the Infrastructure Bootstrapper.

Three read-only tools for AWS account introspection:
- describe_account: Overview of EC2, Lambda, S3, RDS, DynamoDB, ECS, and CloudWatch alarms
- get_spending: Cost breakdown via Cost Explorer
- search_logs: CloudWatch Logs search (can read the agent's own logs)
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError
from strands import tool
from strands.types.tools import ToolContext

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Pure business-logic helpers (no framework dependency)
# ---------------------------------------------------------------------------


def _describe_account(session: boto3.Session, region: str) -> str:
    """Describe key resources in the AWS account."""
    sections = []

    # EC2 instances
    try:
        ec2 = session.client("ec2", region_name=region)
        resp = ec2.describe_instances()
        instances = []
        for res in resp.get("Reservations", []):
            for inst in res.get("Instances", []):
                name = ""
                for tag in inst.get("Tags", []):
                    if tag["Key"] == "Name":
                        name = tag["Value"]
                        break
                instances.append(
                    f"  - {name or '(unnamed)'} ({inst['InstanceId']}): "
                    f"{inst['InstanceType']}, {inst['State']['Name']}, "
                    f"{inst.get('Placement', {}).get('AvailabilityZone', '?')}"
                )
        if instances:
            sections.append(f"EC2 Instances ({len(instances)}):\n" + "\n".join(instances))
        else:
            sections.append("EC2 Instances: none")
    except ClientError as e:
        sections.append(f"EC2: error - {e}")

    # Lambda functions
    try:
        lam = session.client("lambda", region_name=region)
        resp = lam.list_functions()
        functions = resp.get("Functions", [])
        if functions:
            lines = [
                f"  - {f['FunctionName']}: {f.get('Runtime', 'n/a')}, {f['MemorySize']}MB"
                for f in functions
            ]
            sections.append(f"Lambda Functions ({len(functions)}):\n" + "\n".join(lines))
        else:
            sections.append("Lambda Functions: none")
    except ClientError as e:
        sections.append(f"Lambda: error - {e}")

    # S3 buckets
    try:
        s3 = session.client("s3")
        resp = s3.list_buckets()
        buckets = resp.get("Buckets", [])
        if buckets:
            lines = [
                f"  - {b['Name']} (created {b['CreationDate'].strftime('%Y-%m-%d')})"
                for b in buckets[:15]
            ]
            if len(buckets) > 15:
                lines.append(f"  ... and {len(buckets) - 15} more")
            sections.append(f"S3 Buckets ({len(buckets)}):\n" + "\n".join(lines))
        else:
            sections.append("S3 Buckets: none")
    except ClientError as e:
        sections.append(f"S3: error - {e}")

    # RDS instances
    try:
        rds = session.client("rds", region_name=region)
        resp = rds.describe_db_instances()
        dbs = resp.get("DBInstances", [])
        if dbs:
            lines = [
                f"  - {d['DBInstanceIdentifier']}: {d['Engine']} {d.get('EngineVersion', '')}, "
                f"{d['DBInstanceClass']}, {d['DBInstanceStatus']}"
                for d in dbs
            ]
            sections.append(f"RDS Instances ({len(dbs)}):\n" + "\n".join(lines))
        else:
            sections.append("RDS Instances: none")
    except ClientError as e:
        sections.append(f"RDS: error - {e}")

    # DynamoDB tables
    try:
        ddb = session.client("dynamodb", region_name=region)
        resp = ddb.list_tables()
        tables = resp.get("TableNames", [])
        if tables:
            lines = [f"  - {t}" for t in tables[:20]]
            if len(tables) > 20:
                lines.append(f"  ... and {len(tables) - 20} more")
            sections.append(f"DynamoDB Tables ({len(tables)}):\n" + "\n".join(lines))
        else:
            sections.append("DynamoDB Tables: none")
    except ClientError as e:
        sections.append(f"DynamoDB: error - {e}")

    # ECS clusters
    try:
        ecs = session.client("ecs", region_name=region)
        resp = ecs.list_clusters()
        cluster_arns = resp.get("clusterArns", [])
        if cluster_arns:
            detail = ecs.describe_clusters(clusters=cluster_arns)
            lines = [
                f"  - {c['clusterName']}: {c.get('runningTasksCount', 0)} running tasks, "
                f"{c.get('activeServicesCount', 0)} services"
                for c in detail.get("clusters", [])
            ]
            sections.append(f"ECS Clusters ({len(cluster_arns)}):\n" + "\n".join(lines))
        else:
            sections.append("ECS Clusters: none")
    except ClientError as e:
        sections.append(f"ECS: error - {e}")

    # CloudWatch alarms in ALARM state
    try:
        cw = session.client("cloudwatch", region_name=region)
        resp = cw.describe_alarms(StateValue="ALARM")
        alarms = resp.get("MetricAlarms", []) + resp.get("CompositeAlarms", [])
        if alarms:
            lines = [
                f"  - [ALARM] {a['AlarmName']}: {a.get('AlarmDescription', 'no description')}"
                for a in alarms
            ]
            sections.append(f"Active Alarms ({len(alarms)}):\n" + "\n".join(lines))
        else:
            sections.append("CloudWatch Alarms: all clear, no alarms firing")
    except ClientError as e:
        sections.append(f"CloudWatch Alarms: error - {e}")

    header = f"AWS Account Overview (region: {region})"
    return f"{header}\n{'=' * len(header)}\n\n" + "\n\n".join(sections)


def _get_spending(session: boto3.Session, days: int = 7) -> str:
    """Get AWS spending breakdown by service."""
    days = max(1, min(days, 90))

    # Cost Explorer endpoint is only in us-east-1
    ce = session.client("ce", region_name="us-east-1")

    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=days)

    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": start.isoformat(), "End": end.isoformat()},
        Granularity="DAILY" if days <= 14 else "MONTHLY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    service_costs: dict[str, float] = {}
    for result in resp.get("ResultsByTime", []):
        for group in result.get("Groups", []):
            service = group["Keys"][0]
            amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
            service_costs[service] = service_costs.get(service, 0) + amount

    total = sum(service_costs.values())
    sorted_services = sorted(service_costs.items(), key=lambda x: x[1], reverse=True)

    lines = [f"AWS Spending (last {days} days): ${total:.2f} USD", ""]
    for service, cost in sorted_services:
        if cost > 0.001:
            pct = (cost / total * 100) if total > 0 else 0
            lines.append(f"  ${cost:>8.2f}  ({pct:>5.1f}%)  {service}")

    return "\n".join(lines)


def _search_logs(
    session: boto3.Session,
    region: str,
    log_group: str,
    filter_pattern: str = "",
    minutes: int = 30,
) -> str:
    """Search CloudWatch Logs for recent entries."""
    minutes = max(1, min(minutes, 1440))

    logs = session.client("logs", region_name=region)

    # List available log groups when none specified
    if not log_group.strip():
        resp = logs.describe_log_groups(limit=25)
        groups = resp.get("logGroups", [])
        if not groups:
            return "No log groups found in this region."
        lines = ["Available log groups:"]
        for g in groups:
            lines.append(f"  - {g['logGroupName']}")
        return "\n".join(lines)

    start_ms = int((datetime.now(timezone.utc) - timedelta(minutes=minutes)).timestamp() * 1000)
    end_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

    kwargs: dict = {
        "logGroupName": log_group,
        "startTime": start_ms,
        "endTime": end_ms,
        "limit": 50,
    }
    if filter_pattern.strip():
        kwargs["filterPattern"] = filter_pattern

    resp = logs.filter_log_events(**kwargs)
    events = resp.get("events", [])

    if not events:
        return (
            f"No log events found in '{log_group}' "
            f"(last {minutes} min, filter: '{filter_pattern or 'none'}')"
        )

    lines = [
        f"Logs from '{log_group}' (last {minutes} min, {len(events)} events):"
    ]
    for event in events:
        ts = datetime.fromtimestamp(
            event["timestamp"] / 1000, tz=timezone.utc
        ).strftime("%H:%M:%S")
        msg = event["message"].strip()
        if len(msg) > 300:
            msg = msg[:300] + "..."
        lines.append(f"  [{ts}] {msg}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# @tool wrappers (Strands Agent interface)
# ---------------------------------------------------------------------------


@tool(context=True)
def describe_account(region: str, tool_context: ToolContext) -> str:
    """Describe key resources in an AWS account: EC2, Lambda, S3, RDS, DynamoDB,
    ECS clusters, and active CloudWatch alarms.

    Args:
        region: AWS region to inspect (e.g. "eu-central-1", "us-east-1").
    """
    result = _describe_account(boto3.Session(), region)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "describe_account", "args": {"region": region}}
    )
    return result


@tool(context=True)
def get_spending(days: int, tool_context: ToolContext) -> str:
    """Get AWS spending breakdown by service for the last N days.

    Args:
        days: Number of days to look back (1-90).
    """
    result = _get_spending(boto3.Session(), days)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "get_spending", "args": {"days": days}}
    )
    return result


@tool(context=True)
def search_logs(
    log_group: str, filter_pattern: str, minutes: int, tool_context: ToolContext
) -> str:
    """Search CloudWatch Logs for recent entries. Pass an empty log_group to
    list available log groups.

    Args:
        log_group: CloudWatch log group name. Pass empty string to list groups.
        filter_pattern: CloudWatch filter pattern (e.g. "ERROR", "timeout"). Empty for all.
        minutes: How many minutes back to search (1-1440).
    """
    session = boto3.Session()
    region = session.region_name or "eu-central-1"
    result = _search_logs(session, region, log_group, filter_pattern, minutes)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "search_logs", "args": {"log_group": log_group, "filter_pattern": filter_pattern, "minutes": minutes}}
    )
    return result
