
using MCP
collector = MCPCollector()
explore_mcp_servers_in_directory(collector, "mcp/servers/src")

#%%
using MCP: list_clients
list_clients(collector)
#%%
