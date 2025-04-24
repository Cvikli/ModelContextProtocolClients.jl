
add_server(collector, "puppeteer", "mcp/servers/src/puppeteer/dist/index.js")

# First get the tools list to confirm we're connected
tools = get_tools(collector, "puppeteer")
println("Available puppeteer tools: ", [tool["name"] for tool in tools])

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