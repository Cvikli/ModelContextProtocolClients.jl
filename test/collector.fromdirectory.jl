
using MCPClients
collector = MCPClientCollector()
explore_mcp_servers_in_directory(collector, "mcp/servers/src")

#%%
using MCPClients: list_clients
list_clients(collector)
#%%
