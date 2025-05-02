
using ModelContextProtocolClient
collector = MCPClientCollector()
explore_mcp_servers_in_directory(collector, "mcp/servers/src")

#%%
using ModelContextProtocolClient: list_clients
list_clients(collector)
#%%
