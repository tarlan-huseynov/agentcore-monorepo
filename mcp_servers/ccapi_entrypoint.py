"""CCAPI MCP Server entry point for AgentCore Runtime.

Runs the awslabs Cloud Control API MCP Server with streamable-http transport
so AgentCore Gateway can route tool calls to it.

AgentCore requires MCP servers to be stateless HTTP on 0.0.0.0:8000/mcp.

IMPORTANT: The pre-built `mcp` object in awslabs.ccapi_mcp_server.server is
created with the FastMCP default host="127.0.0.1". When FastMCP is constructed
with a localhost host value, it automatically enables DNS rebinding protection
(TransportSecuritySettings with allowed_hosts restricted to localhost). Mutating
mcp.settings.host = "0.0.0.0" after the fact changes the bind address but does
NOT clear the localhost-only TransportSecuritySettings, causing the middleware to
reject every incoming request from AgentCore with a 400/403 before the MCP
handler ever sees it. The fix is to also clear transport_security so that the
StreamableHTTPSessionManager receives security_settings=None (no restriction).

SchemaManager cache directory: The original awslabs.ccapi_mcp_server package uses
os.path.dirname(__file__)/.schemas as its schema cache. In AgentCore Runtime, the
package is extracted from a ZIP to a read-only directory (/var/task), causing a
PermissionError at import time. The packaging script (scripts/package_mcp.sh)
applies mcp_servers/patches/ccapi/ on top of the pip install to replace
schema_manager.py with a version that uses /tmp/.ccapi_schemas instead.

See: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html
"""

import os

os.environ.setdefault("SECURITY_SCANNING", "enabled")
os.environ.setdefault("DEFAULT_TAGS", "enabled")

from awslabs.ccapi_mcp_server.context import Context  # noqa: E402
from awslabs.ccapi_mcp_server.server import mcp  # noqa: E402

# Initialize the Context singleton — required by tools that call Context.readonly_mode().
# The upstream server.py normally does this in its CLI main() which we bypass.
Context.initialize(readonly_mode=False)

# AgentCore Runtime expects stateless HTTP on 0.0.0.0:8000/mcp.
#
# Must also clear transport_security: FastMCP sets DNS rebinding protection
# (allowed_hosts: localhost only) when constructed with the default host
# "127.0.0.1". Clearing it here allows requests from any host, which is
# required for AgentCore Gateway to reach this server.
mcp.settings.host = "0.0.0.0"
mcp.settings.port = 8000
mcp.settings.stateless_http = True
mcp.settings.transport_security = None

mcp.run(transport="streamable-http")
