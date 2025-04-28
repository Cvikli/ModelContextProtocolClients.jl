# MCP.jl

A Julia client for the Model Context Protocol (MCP) that allows communication with various MCP servers. This package simplifies integrating AI tools into your Julia applications through a consistent interface.

## Features

- Connect to multiple MCP servers simultaneously
- Manage tool discovery and invocation
- Support for Python and Node.js based MCP servers  
- Environment variable handling for secure credential management
- Tested with many popular MCP servers

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

## Tested Servers

The MCP.jl should work with most of the servers that is in nodejs (python MCP servers are just buggy yet.)

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
- `add_server(collector, id, path, [env])` - Connect to an MCP server
- `list_tools(collector, server_id)` - List available tools
- `call_tool(collector, server_id, tool_name, arguments)` - Execute a tool
- `disconnect_all(collector)` - Close all server connections

## Examples

Check the `test` directory for complete examples:

- `test_puppeteer.jl` - Web browser automation
- `test_coinmarket.jl` - Crypto market data retrieval
- `test.jl` - Basic server setup and configuration

## ROADMAP

- [ ] Python MCP server
- [ ] MCP server exploration
  - [ ] Initialization of the server could be automatized like installation and so on
  - [ ] configuration deduction (So we should be able to know what are the required environment variables nd list them somehow)
  - [ ] Python and nodejs server could be handled more seamlessly
- [ ] Anthropic Desktop configuration could be used to initialize system
- [ ] Remote MCP usage?
- [ ] Transport layer support:
  - [x] stdio (so local servers should be supported)
  - [ ] SSE transportlayer support?
  - [ ] Websocket?
- [ ] More language? 
- [ ] MCP Standard compliance https://modelcontextprotocol.io/

Note we have this to create julia MCP servers: https://github.com/JuliaSMLM/ModelContextProtocol.jl

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.

## License

MIT
