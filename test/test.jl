using MCP

mkpath("mcp")  # Create mcp directory if it doesn't exist

# Only clone repositories if they don't already exist
!isdir("mcp/coinmarket-mcp-server") && run(`git clone https://github.com/anjor/coinmarket-mcp-server mcp/coinmarket-mcp-server`)
!isdir("mcp/mcp-server-rag-web-browser") && run(`git clone https://github.com/apify/mcp-server-rag-web-browser mcp/mcp-server-rag-web-browser`)
!isdir("mcp/slack-mcp-server") && run(`git clone https://github.com/AVIMBU/slack-mcp-server.git mcp/slack-mcp-server`)
!isdir("mcp/servers") && run(`git clone https://github.com/modelcontextprotocol/servers.git mcp/servers`)
!isdir("mcp/ashra-mcp") && run(`git clone https://github.com/getrupt/ashra-mcp mcp/ashra-mcp`)
!isdir("mcp/mcp-twitter-noauth") && run(`git clone https://github.com/baryhuang/mcp-twitter-noauth.git mcp/mcp-twitter-noauth`)
!isdir("mcp/gdrive-mcp-server") && run(`git clone https://github.com/felores/gdrive-mcp-server.git mcp/gdrive-mcp-server`)

collector = MCPCollector()

# Add servers with environment variables
# Uncomment the servers you want to test

# add_server(collector, "slack", "mcp/slack-mcp-server/dist/index.js")

# add_server(collector, "raw-web-browser", "mcp/mcp-server-rag-web-browser/dist/index.js", 
#           Dict("APIFY_TOKEN" => ENV["APIFY_TOKEN"]))

# add_server(collector, "time", "mcp/servers/src/time/src/mcp_server_time/__main__.py") # DOESN'T WORKING!!

# SENTRY_TOKEN from environment or fallback
# add_server(collector, "sentry", "mcp/servers/src/sentry/src/mcp_server_sentry/__main__.py", 
#           Dict("SENTRY_TOKEN" => ENV["SENTRY_TOKEN"]))

# COINMARKET_API_KEY from environment or fallback
# add_server(collector, "coinmarket", "mcp/coinmarket-mcp-server/src/coinmarket_service/server.py", 
#           Dict("COINMARKET_API_KEY" => ENV["COINMARKET_API_KEY"]))
# add_server(collector, "mcp-bitte", "https://mcp.bitte.ai/sse")
# add_server(collector, "twitter", "mcp/mcp-twitter-noauth/src/mcp_server_twitter_noauth/__init__.py")
# add_server(collector, "git", "mcp/servers/src/git/src/mcp_server_git/__main__.py")
# add_server(collector, "fetch", "mcp/servers/src/fetch/src/mcp_server_fetch/__main__.py")
client = MCPClient(`python3 -m mcp_server_fetch`)
# client = MCPClient(`node mcp/servers/src/google-maps/dist/index.js`, env=Dict("GOOGLE_MAPS_API_KEY" => ENV["GOOGLE_MAPS_API_KEY"]))

# tools = list_tools(collector, "mcp-bitte")
# tools = list_tools(collector, "raw-web-browser")
# tools = list_tools(collector, "google-maps")
# tools = list_tools(collector, "time")
# tools = list_tools(collector, "sentry")
# tools = list_tools(collector, "slack")
# tools = list_tools(collector, "twitter")
# sleep(1)
# tools = list_tools(collector, "git")
# tools = list_tools(collector, "fetch")
# disconnect_all(collector)
# @show send_request(client, """
# {
#   "jsonrpc": "2.0",
#   "method": "initialize",
#   "params": {
#     "protocolVersion": "0.1.0",
#     "clientInfo": {
#       "name": "test_client",
#       "version": "1.0.0"
#     },
#     "capabilities": {}
#   },
#   "id": 1
# }
# """)
@show send_request(client, method="initialize", params=Dict())

# @show send_request(client, """
# {
#   "jsonrpc": "2.0",
#   "method": "initialized",
#   "params": {}
# }
# """)
@show send_request(client, method="tools/list", params=Dict())
# @show send_request(client, """
# {
#   "jsonrpc": "2.0",
#   "id": "1",
#   "method": "tools/list",
#   "params": {}
# }
# """)
#%%
send_request(client, """
{
  "jsonrpc": "2.0",
  "method": "initialized",
  "params": {}í
}
""")

#%%

#%%
using MCP: send_request
send_request(collector.servers["git"], """
{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "tools/list",
  "params": {}
}
""")
#%%
send_request(collector.servers["twitter"], """
{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "git/git_status",
  "params": {
    "repo_path": "mcp/servers"
  }
}
""")
#%%
tools
#%%
using JSON
JSON.parse(response["result"]["content"][1]["text"])
#%%
#%%
