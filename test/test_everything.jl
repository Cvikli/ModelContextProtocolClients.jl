using ModelContextProtocolClients

# Ensure MCP server code is cloned
!isdir("mcp/servers") && run(`git clone https://github.com/modelcontextprotocol/servers.git mcp/servers`)

# Create server collector
collector = MCPClientCollector()

# Add everything server
add_server(collector, "everything", 
           path="mcp/servers/src/everything/dist/index.js", 
           setup_command=`bash -c "cd mcp/servers/src/everything && npm install && npm run build"`)

# Get available tools list
tools = list_tools(collector, "everything")
println("Available tools list:")
for tool in tools
    println("- $(tool.name): $(tool.description)")
end

# Test echo tool
println("\nTesting echo tool:")
echo_response = call_tool(collector, "everything", "echo", Dict(
    "message" => "Hello, I am MCP client!"
))
println("Echo response: ", echo_response)

# Test add tool
println("\nTesting add tool:")
add_response = call_tool(collector, "everything", "add", Dict(
    "a" => 42,
    "b" => 58
))
println("Add response: ", add_response)

# Test printEnv tool
println("\nTesting printEnv tool:")
env_response = call_tool(collector, "everything", "printEnv", Dict())
println("PrintEnv response: ", env_response)

# Test getTinyImage tool
println("\nTesting getTinyImage tool:")
image_response = call_tool(collector, "everything", "getTinyImage", Dict())
println("GetTinyImage response type: ", typeof(image_response))

# Test long-running operation with progress updates
println("\nTesting longRunningOperation tool (will take a few seconds):")
long_response = call_tool(collector, "everything", "longRunningOperation", Dict(
    "duration" => 5,
    "steps" => 5
))
println("LongRunningOperation response: ", long_response)

# Test annotatedMessage tool
println("\nTesting annotatedMessage tool:")
annotated_response = call_tool(collector, "everything", "annotatedMessage", Dict(
    "messageType" => "success",
    "includeImage" => true  # Temporarily disabled image to simplify testing
))
println("AnnotatedMessage response: ", annotated_response)

# Cleanup
disconnect_all(collector)
println("\nTesting completed and disconnected.") 