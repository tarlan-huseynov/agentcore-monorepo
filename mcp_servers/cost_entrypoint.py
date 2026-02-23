"""Cost Explorer MCP Server entry point for AgentCore Runtime.

Runs the awslabs Cost Explorer MCP Server with streamable-http transport
so AgentCore Gateway can route tool calls to it.
"""

import os

os.environ.setdefault("AWS_REGION", os.environ.get("AWS_REGION", "us-east-1"))

from awslabs.cost_explorer_mcp_server.server import app  # noqa: E402

app.run(transport="streamable-http")
