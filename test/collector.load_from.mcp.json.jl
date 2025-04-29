
using MCP
collector = MCPCollector()
load_mcp_servers_config(collector, "test/mcp.json")

#%%
using MCP: list_clients
list_clients(collector)
