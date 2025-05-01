using MCPClients
using MCPClients: initialize, send_request

# Create a client for the fetch server
client = MCPClient(`python3 -m mcp_server_fetch`)

# Initialize the client (this also sends the initialized notification)
init_response = initialize(client)
println("Initialize response: ", init_response)

# Give the server a moment to process the initialized notification
sleep(0.5)

# List available tools
tools_response = send_request(client, method="tools/list", params=Dict())
println("Tools list: ", tools_response)

# Close the client when done
close(client)
