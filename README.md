# MCP.jl

A Julia client for the Model Context Protocol (MCP) that allows communication with various MCP servers. This package simplifies integrating AI tools into your Julia applications through a consistent interface.

## Features

- Connect to multiple MCP servers simultaneously
- Manage tool discovery and invocation
- Support for Python and Node.js based MCP servers
- Environment variable handling for secure credential management
- Automatic server installation support
- Tested with many popular MCP servers
- Automatic MCP server discovery in directories

## Installation

```julia
# Add the package
using Pkg
Pkg.add(url="https://github.com/Cvikli/MCP.jl")

# Or clone directly
git clone https://github.com/Cvikli/MCP.jl
```

## Quick Example

```julia
using MCP

# Create a server collector
collector = MCPCollector()

# Add a Puppeteer server
add_server(collector, "puppeteer", "path/to/puppeteer/dist/index.js")

# Get available tools
tools = list_tools(collector, "puppeteer")
println([tool["name"] for tool in tools])

# Navigate to a website
response = call_tool(collector, "puppeteer", "puppeteer_navigate", Dict(
    "url" => "https://example.com",
    "allowDangerous" => true,
    "launchOptions" => Dict("headless" => false)
))

# Click elements
call_tool(collector, "puppeteer", "puppeteer_click", Dict(
    "selector" => "a:nth-of-type(2)"  # Click the second link
))

# Clean up
disconnect_all(collector)
```

## Auto-Discovery Example

```julia
using MCP

# Create a server collector
collector = MCPCollector()

# Discover MCP servers in a directory
explore_mcp_servers(collector, "./mcp", 
                   exclude_patterns=[".git", "venv"],
                   log_level=:info)

# List all discovered tools
for (server_id, tool_name, info) in get_all_tools(collector)
    println("$server_id: $tool_name")
end

# Use a discovered tool
call_tool(collector, "discovered_server_id", "tool_name", Dict("arg1" => "value1"))

# Clean up
disconnect_all(collector)
```

## Loading MCP Servers from Folders

MCP.jl can automatically discover and load MCP servers from a directory structure. It supports both Node.js and Python projects, including those with pyproject.toml configuration.

```julia
using MCP

# Create a collector
collector = MCPCollector()

# Explore a directory containing MCP servers
explore_mcp_servers_in_directory(collector, "mcp/")

# List all loaded clients
using MCP: list_clients
list_clients(collector)

# Now you can use any of the discovered tools
tools = list_tools(collector, "some_discovered_server")
```

The `explore_mcp_servers_in_directory` function will:

1. Scan the specified directory for potential MCP servers
2. Detect project types (Node.js or Python)
3. Parse configuration files (package.json, pyproject.toml)
4. Set up appropriate commands to run the servers
5. Install dependencies if needed
6. Verify that each server provides MCP tools

## Tested Servers

The MCP.jl should work with most of the servers that is in nodejs or python

MCP.jl has been tested with:

- **puppeteer**: Browser automation
- **time**: Timezone conversion services
- **coinmarket**: Cryptocurrency data
- **sentry**: Error monitoring
- **slack**: Messaging platform integration
- **web-browser**: Web browsing RAG

## API Reference

### Core Functions

- `MCPCollector()` - Create a new collector
- `add_server(collector, id, path, [env]; setup_command=nothing)` - Connect to an MCP server
- `list_tools(collector, server_id)` - List available tools
- `call_tool(collector, server_id, tool_name, arguments)` - Execute a tool
- `disconnect_all(collector)` - Close all server connections
- `explore_mcp_servers_in_directory(collector, directory; exclude_patterns=[])` - Discover MCP servers in a directory
- `list_clients(collector)` - List all loaded MCP server IDs

## Examples

Check the `test` directory for complete examples:

- `test_puppeteer.jl` - Web browser automation
- `test_coinmarket.jl` - Crypto market data retrieval
- `test.jl` - Basic server setup and configuration

## ROADMAP

- [x] NodeJS MCP server run by the MCPClient
- [x] Python MCP server run by the MCPClient
- [x] Other language MCP server to be run by MCPClient (you only need to setup it and then send the "run command")
- [x] MCP server exploration per folder
- [x] Initialization of the server could be automatized like installation and so on
- [ ] configuration deduction (So we should be able to know what are the required environment variables nd list them somehow) (I don't know where does this know but sounds like hardcoded...? https://claudedesktopconfiggenerator.com/)
- [x] Anthropic Desktop configuration could be used to initialize system
  - [x] mcp.json
  - [x] mcpServers
- [ ] Remote MCP usage?
- [ ] Transport layer support:
  - [x] stdio (so local servers should be supported)
  - [ ] SSE transportlayer support
  - [ ] Websocket
- [ ] MCP Standard compliance https://modelcontextprotocol.io/ test/mcp.json.example also shows great stuffs.
- [ ] https://claudedesktopconfiggenerator.com/ how does this able to generate the ENV tag too??

Note we have this to create julia MCP servers: https://github.com/JuliaSMLM/ModelContextProtocol.jl

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.

## License

MIT
