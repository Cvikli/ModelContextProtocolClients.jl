using ModelContextProtocolClient
client = MCPClient("https://mcp.bitte.ai/sse", :sse)
tools = list_tools(client)
println(tools)


