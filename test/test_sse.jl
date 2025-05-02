using ModelContextProtocolClient

# Create a collector
collector = MCPClientCollector()

# Add an SSE server
add_server(collector, "sse_server", "http://0.0.0.0:8080/sse", :sse)

# List available tools
tools = list_tools(collector, "sse_server")
println("Available tools:")
for tool in tools
    println(" - $(tool["name"]): $(get(tool, "description", "No description"))")
end

# Call a tool
response = call_tool(collector, "sse_server", "example_tool", Dict(
    "param1" => "value1",
    "param2" => 42
))

println("Tool response: ", response)

# Clean up
disconnect_all(collector)

#%%

for tool in tools
    println(" - $(tool["name"]): $(get(tool, "description", "No description"))")
end