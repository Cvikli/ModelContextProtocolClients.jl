using MCP
collector = MCPClientCollector()
load_mcp_servers_config(collector, "test/mcp1.json")

#%%
using MCP: list_clients
list_clients(collector)

#%%
tools = list_tools(collector, "context7-mcp")
println(tools)

#%%
response = call_tool(collector, "context7-mcp", "resolve-library-id", Dict(
    "libraryName" => "mongodb"
))
println(response)

#%%
response = call_tool(collector, "context7-mcp", "get_context", Dict())