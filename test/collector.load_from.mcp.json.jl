using ModelContextProtocolClients
collector = MCPClientCollector()
load_mcp_servers_config(collector, "test/mcp.json")

#%%
using ModelContextProtocolClients: list_clients
list_clients(collector)

#%%
tools = list_tools(collector, "tavily")
using ModelContextProtocolClients: print_tools
print_tools(tools)

#%%
response = call_tool(collector, "puppeteer", "puppeteer_navigate", Dict(
    "url" => "https://www.google.com",
    "allowDangerous" => true,
    "launchOptions" => Dict("headless" => false,
    "args" => ["--no-sandbox", "--disable-setuid-sandbox"])
))
println(response)

#%%
response = call_tool(collector, "context7-mcp", "resolve-library-id", Dict(
    "libraryName" => "mongodb"
))
println(response)

#%%
response = call_tool(collector, "context7-mcp", "get_context", Dict())