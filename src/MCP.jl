module MCP

using JSON

include("Client.jl")
include("ClientCollector.jl")

export MCPClient, MCPCollector, add_server, remove_server, disconnect_all, get_all_tools, get_tools, list_tools, call_tool, load_mcp_servers_config

end # module MCP
