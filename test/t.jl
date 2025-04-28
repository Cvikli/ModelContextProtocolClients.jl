
client = MCPClient(`python3 -m mcp_server_fetch`)
@show send_request(client, method="initialize", params=Dict())
@show send_request(client, method="tools/list", params=Dict())