using ModelContextProtocolClients
collector = MCPClientCollector()
add_server(collector, "google-maps", path="mcp/servers/src/google-maps/dist/index.js", env=Dict("GOOGLE_MAPS_API_KEY" => ENV["GOOGLE_MAPS_API_KEY"]), setup_command=`bash -c "cd mcp/servers/src/google-maps && npm install && npm run build"`)

tools = list_tools(collector, "google-maps")
@show tools


response = call_tool(collector, "google-maps", "maps_geocode", Dict(
    "address" => "1600 Amphitheatre Parkway, Mountain View, CA"
))
response["result"]