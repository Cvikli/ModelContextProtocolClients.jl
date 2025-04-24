using MCP


mkpath("mcp")  # Create mcp directory if it doesn't exist

# Only clone repositories if they don't already exist
!isdir("mcp/coinmarket-mcp-server") && run(`git clone https://github.com/anjor/coinmarket-mcp-server mcp/coinmarket-mcp-server`)
!isdir("mcp/mcp-server-rag-web-browser") && run(`git clone https://github.com/apify/mcp-server-rag-web-browser mcp/mcp-server-rag-web-browser`)
!isdir("mcp/slack-mcp-server") && run(`git clone https://github.com/AVIMBU/slack-mcp-server.git mcp/slack-mcp-server`)
!isdir("mcp/servers") && run(`git clone https://github.com/modelcontextprotocol/servers.git mcp/servers`)
!isdir("mcp/ashra-mcp") && run(`git clone https://github.com/getrupt/ashra-mcp mcp/ashra-mcp`)


collector = MCPCollector()

# add_server(collector, "slack", "mcp/slack-mcp-server/dist/index.js")
# add_server(collector, "raw-web-browser", "mcp/mcp-server-rag-web-browser/dist/index.js", Dict("APIFY_TOKEN" => "YOUR APIKEY"))
# add_server(collector, "time", "mcp/servers/src/time/src/mcp_server_time/__main__.py") # DOESN'T WORKING!!
# add_server(collector, "sentry", "mcp/servers/src/sentry/src/mcp_server_sentry/__main__.py", Dict("SENTRY_TOKEN" => "YOUR APIKEY"))
# add_server(collector, "coinmarket", "mcp/coinmarket-mcp-server/src/coinmarket_service/server.py", Dict("COINMARKET_API_KEY" => "YOUR APIKEY"))
# add_server(collector, "mcp-bitte", "https://mcp.bitte.ai/sse")

# tools = get_tools(collector, "mcp-bitte")
# tools = get_tools(collector, "raw-web-browser")
# tools = get_tools(collector, "google-maps")
# tools = get_tools(collector, "time")
# tools = get_tools(collector, "sentry")
# tools = get_tools(collector, "slack")

# disconnect_all(collector)

#%%
tools
#%%
using JSON
JSON.parse(response["result"]["content"][1]["text"])
#%%
