"""Cost Explorer MCP Server entry point for AgentCore Runtime.

Runs the awslabs Cost Explorer MCP Server with streamable-http transport
so AgentCore Gateway can route tool calls to it.

AgentCore requires MCP servers to be stateless HTTP on 0.0.0.0:8000/mcp.

IMPORTANT: The pre-built `app` object in awslabs.cost_explorer_mcp_server.server
is created with the FastMCP default host="127.0.0.1". When FastMCP is constructed
with a localhost host value, it automatically enables DNS rebinding protection
(TransportSecuritySettings with allowed_hosts restricted to localhost). Mutating
app.settings.host = "0.0.0.0" after the fact changes the bind address but does
NOT clear the localhost-only TransportSecuritySettings, causing the middleware to
reject every incoming request from AgentCore with a 400/403 before the MCP
handler ever sees it. The fix is to also clear transport_security so that the
StreamableHTTPSessionManager receives security_settings=None (no restriction).

See: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html
"""

import os

os.environ.setdefault("AWS_REGION", os.environ.get("AWS_REGION", "us-east-1"))

from awslabs.cost_explorer_mcp_server.server import app  # noqa: E402

# AgentCore Runtime expects stateless HTTP on 0.0.0.0:8000/mcp.
#
# Must also clear transport_security: FastMCP sets DNS rebinding protection
# (allowed_hosts: localhost only) when constructed with the default host
# "127.0.0.1". Clearing it here allows requests from any host, which is
# required for AgentCore Gateway to reach this server.
app.settings.host = "0.0.0.0"
app.settings.port = 8000
app.settings.stateless_http = True
app.settings.transport_security = None

app.run(transport="streamable-http")
