using MCP
collector = MCPCollector()
add_server(collector, "coinmarket", "mcp/coinmarket-mcp-server/src/coinmarket_service/__init__.py", env=Dict("COINMARKET_API_KEY" => ENV["COINMARKET_API_KEY"]))
tools = list_tools(collector, "coinmarket")
println(tools)
# Call get_currency_listings tool (which requires no arguments)
response = call_tool(collector, "coinmarket", "get_currency_listings", Dict())
# Call get_quotes tool with specific cryptocurrency
response = call_tool(collector, "coinmarket", "get_quotes", Dict(
    "symbol" => "BTC"
))