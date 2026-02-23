"""Cost Explorer MCP Server entry point for AgentCore Runtime.

Runs the awslabs Cost Explorer MCP Server with streamable-http transport
so AgentCore Gateway can route tool calls to it.

AgentCore requires MCP servers to be stateless HTTP on 0.0.0.0:8000/mcp.
The pre-built FastMCP instance doesn't set these, so we configure them here.
See: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html
"""

import os

os.environ.setdefault("AWS_REGION", os.environ.get("AWS_REGION", "us-east-1"))

from awslabs.cost_explorer_mcp_server.server import app  # noqa: E402

# AgentCore Runtime expects stateless HTTP on 0.0.0.0:8000/mcp
app.settings.host = "0.0.0.0"
app.settings.port = 8000
app.settings.stateless_http = True

app.run(transport="streamable-http")
