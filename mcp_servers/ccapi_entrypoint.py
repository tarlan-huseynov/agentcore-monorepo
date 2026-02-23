"""CCAPI MCP Server entry point for AgentCore Runtime.

Runs the awslabs Cloud Control API MCP Server with streamable-http transport
so AgentCore Gateway can route tool calls to it.

AgentCore requires MCP servers to be stateless HTTP on 0.0.0.0:8000/mcp.
The pre-built FastMCP instance doesn't set these, so we configure them here.
See: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html
"""

import os

os.environ.setdefault("SECURITY_SCANNING", "enabled")
os.environ.setdefault("DEFAULT_TAGS", "enabled")

from awslabs.ccapi_mcp_server.server import mcp  # noqa: E402

# AgentCore Runtime expects stateless HTTP on 0.0.0.0:8000/mcp
mcp.settings.host = "0.0.0.0"
mcp.settings.port = 8000
mcp.settings.stateless_http = True

mcp.run(transport="streamable-http")
