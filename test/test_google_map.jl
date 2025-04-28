
add_server(collector, "google-maps", "mcp/servers/src/google-maps/dist/index.js", Dict("GOOGLE_MAPS_API_KEY" => ENV["GOOGLE_MAPS_API_KEY"]))

tools = list_tools(collector, "google-maps")
@show tools


response = call_tool(collector, "google-maps", "maps_geocode", Dict(
    "address" => "1600 Amphitheatre Parkway, Mountain View, CA"
))
response["result"]