module MCP

using JSON

# Get the package version from Project.toml
const MCP_VERSION = "1.0.2"

include("Client.jl")
include("ClientCollector.jl")

export MCPClient, MCPCollector, add_server, remove_server, disconnect_all, get_all_tools, list_tools, list_tools, call_tool, load_mcp_servers_config, send_request, explore_mcp_servers_in_directory, load_mcp_servers_config

end # module MCP
