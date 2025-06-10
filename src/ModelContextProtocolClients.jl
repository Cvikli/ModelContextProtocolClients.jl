module ModelContextProtocolClients

using JSON
using HTTP
import Base: Process
using WebSockets: WebSocket, open, close
using WebSockets

# Get the package version from Project.toml
const JULIA_MCP_CLIENT  = "julia-mcp-client"
const MCPClient_VERSION = "0.8.0"


include("Types.jl")
include("JSON-RPC.jl")
include("Transport.jl")
include("MCPClient.jl")
include("MCPClientCollector.jl")

# Core client functionality
export MCPClient, MCPClientCollector, TransportLayer, StdioTransport, SSETransport, WebSocketTransport
export add_server, remove_server, disconnect_all, get_all_tools, list_tools, call_tool
export load_mcp_servers_config, send_request, explore_mcp_servers_in_directory
export read_message, write_message, close_transport

# MCP Schema Types
export Role, Annotations, Content, AbstractMCPTool
export TextContent, ImageContent, AudioContent, EmbeddedResource
export Resource, ResourceContents, TextResourceContents, BlobResourceContents
export InputSchema, ToolAnnotations, MCPToolSpecification, CallToolResult
export RequestId, JSONRPCRequest, JSONRPCResponse, JSONRPCError
export LoggingLevel, ProgressToken

end # module ModelContextProtocolClients
