module MCP

using JSON
using HTTP
using WebSockets: WebSocket, open, close
using WebSockets

# Get the package version from Project.toml
const MCP_VERSION = "1.1.0"


include("Transport.jl")
include("Client.jl")
include("ClientCollector.jl")

export MCPClient, MCPCollector, TransportLayer, StdioTransport, SSETransport, WebSocketTransport
export add_server, remove_server, disconnect_all, get_all_tools, list_tools, call_tool
export load_mcp_servers_config, send_request, explore_mcp_servers_in_directory
export read_message, write_message, close_transport

end # module MCP
