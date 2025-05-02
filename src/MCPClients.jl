module ModelContextProtocolClient

using JSON
using HTTP
import Base: Process
using WebSockets: WebSocket, open, close
using WebSockets

# Get the package version from Project.toml
const MCPClient_VERSION = "0.8.0"


include("Transport.jl")
include("MCPClient.jl")
include("MCPClientCollector.jl")

export MCPClient, MCPClientCollector, TransportLayer, StdioTransport, SSETransport, WebSocketTransport
export add_server, remove_server, disconnect_all, get_all_tools, list_tools, call_tool
export load_mcp_servers_config, send_request, explore_mcp_servers_in_directory
export read_message, write_message, close_transport


end # module ModelContextProtocolClient
