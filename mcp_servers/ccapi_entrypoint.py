"""CCAPI MCP Server entry point for AgentCore Runtime.

Runs the awslabs Cloud Control API MCP Server with streamable-http transport
so AgentCore Gateway can route tool calls to it.
"""

import os

os.environ.setdefault("SECURITY_SCANNING", "enabled")
os.environ.setdefault("DEFAULT_TAGS", "enabled")

from awslabs.ccapi_mcp_server.server import mcp  # noqa: E402

mcp.run(transport="streamable-http")
