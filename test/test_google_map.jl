
add_server(collector, "google-maps", "mcp/servers/src/google-maps/dist/index.js", Dict("GOOGLE_MAPS_API_KEY" => "YOUR APIKEY"))
println(tools)

response = call_tool(collector, "google-maps", "maps_geocode", Dict(
    "address" => "1600 Amphitheatre Parkway, Mountain View, CA"
))
response["result"]