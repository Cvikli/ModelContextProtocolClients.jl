using ModelContextProtocolClients

# Create a collector
collector = MCPClientCollector()

# Add a WebSocket server
add_server(collector, "websocket_server", "ws://localhost:8080/ws", :websocket)

# List available tools
tools = list_tools(collector, "websocket_server")
println("Available tools:")
for tool in tools
    println(" - $(tool["name"]): $(get(tool, "description", "No description"))")
end

# Call a tool
response = call_tool(collector, "websocket_server", "example_tool", Dict(
    "param1" => "value1",
    "param2" => 42
))

println("Tool response: ", response)

# Clean up
disconnect_all(collector)