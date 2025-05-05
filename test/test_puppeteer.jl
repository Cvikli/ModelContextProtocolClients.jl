using ModelContextProtocolClients

!isdir("mcp/servers") && run(`git clone https://github.com/modelcontextprotocol/servers.git mcp/servers`)

# Create a server collector
collector = MCPClientCollector()

# Add a Puppeteer server
add_server(collector, "puppeteer", path="mcp/servers/src/puppeteer/dist/index.js", setup_command=`bash -c "cd mcp/servers/src/puppeteer && npm install && npm run build"`)

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

# Navigate to a website with sandbox disabled
nav_response = call_tool(collector, "puppeteer", "puppeteer_navigate", Dict(
    "url" => "https://example.com",
    "allowDangerous" => true,
    "launchOptions" => Dict(
        "headless" => false,
        "args" => ["--no-sandbox", "--disable-setuid-sandbox"]
    )
))
println("Navigation result: ", nav_response)

# Take a screenshot
# screenshot_response = call_tool(collector, "puppeteer", "puppeteer_screenshot", Dict(
#     "name" => "example_screenshot",
#     "width" => 1200,
#     "height" => 800
# ))
# println("Screenshot result: ", screenshot_response)

# Get page content using evaluate
content_response = call_tool(collector, "puppeteer", "puppeteer_evaluate", Dict(
    "script" => "document.body.innerText"
))
println("Page content: ", content_response)

# Click a link
click_response = call_tool(collector, "puppeteer", "puppeteer_click", Dict(
    "selector" => "a"  # Click the first link on the page
))
println("Click result: ", click_response)
sleep(0.5)
click_response = call_tool(collector, "puppeteer", "puppeteer_click", Dict("selector" => "a"))
println("Click result: ", click_response)
sleep(0.5)
click_response = call_tool(collector, "puppeteer", "puppeteer_click", Dict("selector" => "a"))
println("Click result: ", click_response)
sleep(0.2)
click_response = call_tool(collector, "puppeteer", "puppeteer_click", Dict("selector" => "a:nth-of-type(2)"))
println("Click result: ", click_response)
#%%

# Navigate to a website with sandbox disabled
nav_response = call_tool(collector, "puppeteer", "puppeteer_navigate", Dict(
    "url" => "https://example.com",
    "allowDangerous" => true,
    "launchOptions" => Dict(
        "headless" => false,
        "args" => ["--no-sandbox", "--disable-setuid-sandbox"]
    )
))
#%%
click_response = call_tool(collector, "puppeteer", "puppeteer_click", Dict("selector" => "a"))
#%%

nav_response["result"]
click_response["result"]