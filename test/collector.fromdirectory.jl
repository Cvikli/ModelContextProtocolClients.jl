
using ModelContextProtocolClients
collector = MCPClientCollector()
explore_mcp_servers_in_directory(collector, "mcp/servers/src")

#%%
using ModelContextProtocolClients: list_clients
list_clients(collector)
#%%
