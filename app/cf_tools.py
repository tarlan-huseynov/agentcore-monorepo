"""CloudFormation infrastructure management tools.

Eight tools for creating, modifying, and managing AWS infrastructure
via CloudFormation from natural language:
- list_stacks: Discover deployed stacks
- describe_stack: Status, parameters, outputs, resources, events
- get_template: Retrieve current CF template JSON
- create_stack: Validate + deploy new infrastructure
- create_change_set: Preview changes to existing stack
- execute_change_set: Apply previewed changes
- delete_stack: Tear down agent-created stacks
- stack_events: Monitor deployment progress
"""

from __future__ import annotations

import json
import logging
import time
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError
from strands import tool
from strands.types.tools import ToolContext

logger = logging.getLogger(__name__)

AGENT_TAG_KEY = "ManagedBy"
AGENT_TAG_VALUE = "agentcore-bootstrapper"
MAX_TEMPLATE_BODY_BYTES = 51_200


def _fmt_ts(ts: object, fmt: str = "%Y-%m-%d %H:%M UTC") -> str:
    """Format a boto3 datetime or pass through a string."""
    return ts.strftime(fmt) if hasattr(ts, "strftime") else str(ts)


def _check_template_size(template_body: str) -> str | None:
    """Return an error string if template exceeds the API size limit, else None."""
    if len(template_body.encode("utf-8")) > MAX_TEMPLATE_BODY_BYTES:
        return (
            f"Error: Template body exceeds {MAX_TEMPLATE_BODY_BYTES} bytes. "
            "Use S3 for larger templates."
        )
    return None


def _parse_cf_params(parameters_json: str) -> list[dict] | str:
    """Parse parameters JSON into CloudFormation parameter dicts.

    Returns a list on success, or an error string on failure.
    """
    try:
        params_list = json.loads(parameters_json) if parameters_json else []
    except json.JSONDecodeError as e:
        return f"Invalid parameters JSON: {e}"
    return [
        {"ParameterKey": p["ParameterKey"], "ParameterValue": p["ParameterValue"]}
        for p in params_list
    ]


# ---------------------------------------------------------------------------
# Pure business-logic helpers (no framework dependency)
# ---------------------------------------------------------------------------


def _list_stacks(session: boto3.Session, region: str, agent_only: bool = True) -> str:
    """List CloudFormation stacks, optionally filtered to agent-created ones."""
    try:
        cf = session.client("cloudformation", region_name=region)
        resp = cf.describe_stacks()
        stacks = resp.get("Stacks", [])
    except ClientError as e:
        return f"Error listing stacks: {e}"

    if agent_only:
        stacks = [
            s for s in stacks
            if any(
                t.get("Key") == AGENT_TAG_KEY and t.get("Value") == AGENT_TAG_VALUE
                for t in s.get("Tags", [])
            )
        ]

    if not stacks:
        label = "agent-created " if agent_only else ""
        return f"No {label}CloudFormation stacks found in {region}."

    lines = [f"CloudFormation Stacks in {region} ({'agent-created only' if agent_only else 'all'}):"]
    for s in stacks:
        name = s["StackName"]
        status = s["StackStatus"]
        created = _fmt_ts(s.get("CreationTime", ""))
        desc = s.get("Description", "")
        lines.append(f"  - {name}: {status} (created {created})")
        if desc:
            lines.append(f"    {desc}")

        outputs = s.get("Outputs", [])
        if outputs:
            for o in outputs[:5]:
                lines.append(f"    Output: {o['OutputKey']} = {o['OutputValue']}")
    return "\n".join(lines)


def _describe_stack(session: boto3.Session, region: str, stack_name: str) -> str:
    """Describe a stack: status, parameters, outputs, resources, recent events."""
    cf = session.client("cloudformation", region_name=region)

    try:
        resp = cf.describe_stacks(StackName=stack_name)
        stacks = resp.get("Stacks", [])
        if not stacks:
            return f"Stack '{stack_name}' not found."
        stack = stacks[0]
    except ClientError as e:
        return f"Error describing stack '{stack_name}': {e}"

    sections = []

    # Basic info
    sections.append(f"Stack: {stack['StackName']}")
    sections.append(f"Status: {stack['StackStatus']}")
    if stack.get("StackStatusReason"):
        sections.append(f"Reason: {stack['StackStatusReason']}")
    sections.append(f"Created: {stack.get('CreationTime', 'N/A')}")
    if stack.get("LastUpdatedTime"):
        sections.append(f"Updated: {stack['LastUpdatedTime']}")
    if stack.get("Description"):
        sections.append(f"Description: {stack['Description']}")

    # Parameters
    params = stack.get("Parameters", [])
    if params:
        sections.append("\nParameters:")
        for p in params:
            sections.append(f"  {p['ParameterKey']} = {p.get('ParameterValue', '****')}")

    # Outputs
    outputs = stack.get("Outputs", [])
    if outputs:
        sections.append("\nOutputs:")
        for o in outputs:
            desc = f" ({o['Description']})" if o.get("Description") else ""
            sections.append(f"  {o['OutputKey']} = {o['OutputValue']}{desc}")

    # Resources
    try:
        resp = cf.list_stack_resources(StackName=stack_name)
        resources = resp.get("StackResourceSummaries", [])
        if resources:
            sections.append(f"\nResources ({len(resources)}):")
            for r in resources:
                physical = r.get("PhysicalResourceId", "pending")
                sections.append(
                    f"  - {r['LogicalResourceId']} ({r['ResourceType']}): "
                    f"{r['ResourceStatus']} [{physical}]"
                )
    except ClientError:
        pass

    # Recent events (last 10)
    try:
        resp = cf.describe_stack_events(StackName=stack_name)
        events = resp.get("StackEvents", [])[:10]
        if events:
            sections.append("\nRecent Events:")
            for ev in events:
                ts = _fmt_ts(ev.get("Timestamp", ""), "%H:%M:%S")
                reason = f" - {ev['ResourceStatusReason']}" if ev.get("ResourceStatusReason") else ""
                sections.append(
                    f"  [{ts}] {ev.get('LogicalResourceId', '?')} "
                    f"({ev.get('ResourceType', '?')}): {ev.get('ResourceStatus', '?')}{reason}"
                )
    except ClientError:
        pass

    return "\n".join(sections)


def _get_template(session: boto3.Session, region: str, stack_name: str) -> str:
    """Retrieve the current CloudFormation template for a stack."""
    try:
        cf = session.client("cloudformation", region_name=region)
        resp = cf.get_template(StackName=stack_name, TemplateStage="Processed")
        body = resp.get("TemplateBody", {})
        if isinstance(body, dict):
            return json.dumps(body, indent=2)
        return str(body)
    except ClientError as e:
        return f"Error retrieving template for '{stack_name}': {e}"


def _create_stack(
    session: boto3.Session,
    region: str,
    stack_name: str,
    template_body: str,
    parameters_json: str = "[]",
) -> str:
    """Validate and create a new CloudFormation stack."""
    if err := _check_template_size(template_body):
        return err

    cf = session.client("cloudformation", region_name=region)

    try:
        cf.validate_template(TemplateBody=template_body)
    except ClientError as e:
        return f"Template validation failed: {e}"

    cf_params = _parse_cf_params(parameters_json)
    if isinstance(cf_params, str):
        return cf_params

    tags = [
        {"Key": AGENT_TAG_KEY, "Value": AGENT_TAG_VALUE},
        {"Key": "CreatedAt", "Value": datetime.now(timezone.utc).isoformat()},
    ]

    try:
        resp = cf.create_stack(
            StackName=stack_name,
            TemplateBody=template_body,
            Parameters=cf_params,
            Tags=tags,
            Capabilities=["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"],
            OnFailure="DELETE",
        )
        stack_id = resp["StackId"]
        return (
            f"Stack '{stack_name}' creation initiated.\n"
            f"Stack ID: {stack_id}\n"
            f"Status: CREATE_IN_PROGRESS\n\n"
            f"Use describe_stack or stack_events to monitor progress."
        )
    except ClientError as e:
        return f"Error creating stack '{stack_name}': {e}"


def _create_change_set(
    session: boto3.Session,
    region: str,
    stack_name: str,
    template_body: str,
    parameters_json: str = "[]",
    description: str = "",
) -> str:
    """Create and wait for a change set to preview stack modifications."""
    if err := _check_template_size(template_body):
        return err

    cf = session.client("cloudformation", region_name=region)

    try:
        cf.validate_template(TemplateBody=template_body)
    except ClientError as e:
        return f"Template validation failed: {e}"

    cf_params = _parse_cf_params(parameters_json)
    if isinstance(cf_params, str):
        return cf_params

    change_set_name = f"agent-cs-{uuid.uuid4().hex[:8]}"

    try:
        cf.create_change_set(
            StackName=stack_name,
            ChangeSetName=change_set_name,
            TemplateBody=template_body,
            Parameters=cf_params,
            Description=description or "Change set created by infrastructure agent",
            Capabilities=["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"],
            ChangeSetType="UPDATE",
        )
    except ClientError as e:
        return f"Error creating change set: {e}"

    # Poll until ready (3s interval, 60s max)
    deadline = time.monotonic() + 60
    status = "CREATE_PENDING"
    status_reason = ""
    changes = []

    while time.monotonic() < deadline:
        time.sleep(3)
        try:
            resp = cf.describe_change_set(
                StackName=stack_name,
                ChangeSetName=change_set_name,
            )
            status = resp.get("Status", "UNKNOWN")
            status_reason = resp.get("StatusReason", "")
            changes = resp.get("Changes", [])

            if status in ("CREATE_COMPLETE", "FAILED"):
                break
        except ClientError as e:
            return f"Error polling change set: {e}"

    if status == "FAILED":
        # "No changes" is reported as FAILED with specific reason
        if "didn't contain changes" in status_reason or "No updates" in status_reason:
            return (
                f"Change set '{change_set_name}': No changes detected.\n"
                f"The template is identical to the current stack configuration."
            )
        return f"Change set '{change_set_name}' FAILED: {status_reason}"

    if status != "CREATE_COMPLETE":
        return f"Change set '{change_set_name}' timed out in status: {status}"

    # Format changes preview
    lines = [
        f"Change set '{change_set_name}' ready for stack '{stack_name}'.",
        f"Status: {status}",
        f"\nProposed changes ({len(changes)}):",
    ]
    for c in changes:
        rc = c.get("ResourceChange", {})
        action = rc.get("Action", "?")
        logical_id = rc.get("LogicalResourceId", "?")
        resource_type = rc.get("ResourceType", "?")
        replacement = rc.get("Replacement", "False")
        detail = " [REPLACEMENT]" if replacement == "True" else ""
        lines.append(f"  - {action}: {logical_id} ({resource_type}){detail}")

    lines.append(f"\nTo apply: use execute_change_set with change_set_name='{change_set_name}'")
    return "\n".join(lines)


def _execute_change_set(
    session: boto3.Session,
    region: str,
    stack_name: str,
    change_set_name: str,
) -> str:
    """Execute a previously created change set."""
    try:
        cf = session.client("cloudformation", region_name=region)
        cf.execute_change_set(
            StackName=stack_name,
            ChangeSetName=change_set_name,
        )
        return (
            f"Change set '{change_set_name}' execution started on stack '{stack_name}'.\n"
            f"Status: UPDATE_IN_PROGRESS\n\n"
            f"Use describe_stack or stack_events to monitor progress."
        )
    except ClientError as e:
        return f"Error executing change set: {e}"


def _delete_stack(session: boto3.Session, region: str, stack_name: str) -> str:
    """Delete a stack, but only if it was created by the agent (tag check)."""
    try:
        cf = session.client("cloudformation", region_name=region)
        resp = cf.describe_stacks(StackName=stack_name)
        stacks = resp.get("Stacks", [])
        if not stacks:
            return f"Stack '{stack_name}' not found."
        stack = stacks[0]
    except ClientError as e:
        return f"Error: {e}"

    # Safety: only delete agent-tagged stacks
    tags = {t["Key"]: t["Value"] for t in stack.get("Tags", [])}
    if tags.get(AGENT_TAG_KEY) != AGENT_TAG_VALUE:
        return (
            f"Refused: Stack '{stack_name}' was not created by this agent "
            f"(missing tag {AGENT_TAG_KEY}={AGENT_TAG_VALUE}). "
            f"Manual deletion required via AWS Console or CLI."
        )

    try:
        cf.delete_stack(StackName=stack_name)
        return (
            f"Stack '{stack_name}' deletion initiated.\n"
            f"Status: DELETE_IN_PROGRESS\n\n"
            f"Use stack_events to monitor progress."
        )
    except ClientError as e:
        return f"Error deleting stack '{stack_name}': {e}"


def _stack_events(
    session: boto3.Session,
    region: str,
    stack_name: str,
    limit: int = 20,
) -> str:
    """Get recent stack events for monitoring deployment progress."""
    limit = max(1, min(limit, 50))
    try:
        cf = session.client("cloudformation", region_name=region)
        resp = cf.describe_stack_events(StackName=stack_name)
        events = resp.get("StackEvents", [])[:limit]
    except ClientError as e:
        return f"Error getting events for '{stack_name}': {e}"

    if not events:
        return f"No events found for stack '{stack_name}'."

    lines = [f"Stack Events for '{stack_name}' (latest {len(events)}):"]
    for ev in events:
        ts = _fmt_ts(ev.get("Timestamp", ""), "%Y-%m-%d %H:%M:%S")
        status = ev.get("ResourceStatus", "?")
        logical_id = ev.get("LogicalResourceId", "?")
        resource_type = ev.get("ResourceType", "?")
        reason = ev.get("ResourceStatusReason", "")
        reason_str = f" - {reason}" if reason else ""
        lines.append(f"  [{ts}] {logical_id} ({resource_type}): {status}{reason_str}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# @tool wrappers (Strands Agent interface)
# ---------------------------------------------------------------------------


@tool(context=True)
def list_stacks(region: str, agent_only: str, tool_context: ToolContext) -> str:
    """List CloudFormation stacks. Set agent_only to "true" to show only stacks
    created by this agent, or "false" to show all stacks.

    Args:
        region: AWS region (e.g. "us-east-1", "eu-central-1").
        agent_only: "true" to filter to agent-created stacks, "false" for all.
    """
    filter_agent = agent_only.lower().strip() != "false"
    result = _list_stacks(boto3.Session(), region, agent_only=filter_agent)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "list_stacks", "args": {"region": region, "agent_only": agent_only}}
    )
    return result


@tool(context=True)
def describe_stack(region: str, stack_name: str, tool_context: ToolContext) -> str:
    """Describe a CloudFormation stack in detail: status, parameters, outputs,
    resources, and recent events.

    Args:
        region: AWS region (e.g. "us-east-1").
        stack_name: Name or ID of the CloudFormation stack.
    """
    result = _describe_stack(boto3.Session(), region, stack_name)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "describe_stack", "args": {"region": region, "stack_name": stack_name}}
    )
    return result


@tool(context=True)
def get_template(region: str, stack_name: str, tool_context: ToolContext) -> str:
    """Retrieve the current CloudFormation template JSON for an existing stack.
    Use this to get the current template before making modifications.

    Args:
        region: AWS region (e.g. "us-east-1").
        stack_name: Name or ID of the CloudFormation stack.
    """
    result = _get_template(boto3.Session(), region, stack_name)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "get_template", "args": {"region": region, "stack_name": stack_name}}
    )
    return result


@tool(context=True)
def create_stack(
    region: str,
    stack_name: str,
    template_body: str,
    parameters_json: str,
    tool_context: ToolContext,
) -> str:
    """Create a new CloudFormation stack. The template is validated before deployment.
    The stack is tagged as agent-managed. On failure the stack auto-deletes.

    Args:
        region: AWS region (e.g. "us-east-1").
        stack_name: Name for the new stack (must be unique in the region).
        template_body: Complete CloudFormation template as a JSON string.
        parameters_json: Stack parameters as a JSON array of objects with ParameterKey and ParameterValue. Use "[]" for no parameters.
    """
    result = _create_stack(boto3.Session(), region, stack_name, template_body, parameters_json)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "create_stack", "args": {"region": region, "stack_name": stack_name}}
    )
    return result


@tool(context=True)
def create_change_set(
    region: str,
    stack_name: str,
    template_body: str,
    parameters_json: str,
    description: str,
    tool_context: ToolContext,
) -> str:
    """Create a change set to preview modifications to an existing stack. The change
    set is created and polled until ready. Review the changes before executing.

    Args:
        region: AWS region (e.g. "us-east-1").
        stack_name: Name of the existing stack to modify.
        template_body: Updated CloudFormation template as a JSON string.
        parameters_json: Stack parameters as a JSON array of objects with ParameterKey and ParameterValue. Use "[]" for no parameters.
        description: Human-readable description of what this change does.
    """
    result = _create_change_set(
        boto3.Session(), region, stack_name, template_body, parameters_json, description
    )
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "create_change_set", "args": {"region": region, "stack_name": stack_name, "description": description}}
    )
    return result


@tool(context=True)
def execute_change_set(
    region: str,
    stack_name: str,
    change_set_name: str,
    tool_context: ToolContext,
) -> str:
    """Execute a previously created change set to apply changes to a stack.

    Args:
        region: AWS region (e.g. "us-east-1").
        stack_name: Name of the stack the change set belongs to.
        change_set_name: Name of the change set to execute.
    """
    result = _execute_change_set(boto3.Session(), region, stack_name, change_set_name)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "execute_change_set", "args": {"region": region, "stack_name": stack_name, "change_set_name": change_set_name}}
    )
    return result


@tool(context=True)
def delete_stack(region: str, stack_name: str, tool_context: ToolContext) -> str:
    """Delete a CloudFormation stack. Only works on stacks created by this agent
    (tagged with ManagedBy=agentcore-bootstrapper). Refuses to delete untagged stacks.

    Args:
        region: AWS region (e.g. "us-east-1").
        stack_name: Name of the stack to delete.
    """
    result = _delete_stack(boto3.Session(), region, stack_name)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "delete_stack", "args": {"region": region, "stack_name": stack_name}}
    )
    return result


@tool(context=True)
def stack_events(
    region: str, stack_name: str, limit: str, tool_context: ToolContext
) -> str:
    """Get recent CloudFormation stack events. Useful for monitoring deployment
    progress or diagnosing failures.

    Args:
        region: AWS region (e.g. "us-east-1").
        stack_name: Name or ID of the CloudFormation stack.
        limit: Maximum number of events to return (1-50, default 20).
    """
    try:
        limit_int = int(limit)
    except (ValueError, TypeError):
        limit_int = 20
    result = _stack_events(boto3.Session(), region, stack_name, limit_int)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "stack_events", "args": {"region": region, "stack_name": stack_name, "limit": limit}}
    )
    return result
