@kwdef mutable struct MCPClient
	transport::Union{TransportLayer, Nothing} = nothing
	output_task::Union{Task, Nothing} = nothing
	req_id::Int=0
	tools_by_name::Vector{MCPToolSpecification} = Vector{MCPToolSpecification}()
	responses::Dict{RequestId, JSONRPCResponse} = Dict{RequestId, JSONRPCResponse}()
	notifications::Vector{Dict} = Vector{Dict}()
	pending_requests::Dict{RequestId, Bool} = Dict{RequestId, Bool}()
	buffer::String = ""
    log_level::Symbol=:info
end

# Accept a command and arguments
function MCPClient(command::Union{Cmd, String}, args::Vector{String}=String[]; 
                  transport_type::Symbol=:stdio,
                  env::Union{Dict{String,T}, Nothing}=nothing, 
                  stdout_handler::Function=(str)->println("SERVER: $str"),
                  auto_initialize::Bool=true,
                  client_name::String=JULIA_MCP_CLIENT,
                  client_version::String=MCPClient_VERSION,
                  setup_command::Union{String, Cmd, Nothing}=nothing,
                  log_level::Symbol=:info) where T
    # Create transport layer with process handling
    transport = create_transport(command, transport_type; args, env, setup_command)

    # Create client
    client = MCPClient(; transport, log_level)
    
    client.output_task = @async while true
        message = read_message(transport)
        message === nothing && break
        handle_server_output(client, message, stdout_handler)
    end
    auto_initialize && initialize(client; client_name, client_version)
    
    return client
end
get_env(client::MCPClient) = client.transport.env

# URL based constructor
function MCPClient(url::String, transport_type::Symbol; 
                  env::Union{Dict{String,T}, Nothing}=nothing, 
                  stdout_handler::Function=(str)->println("SERVER: $str"),
                  auto_initialize::Bool=true,
                  client_name::String=JULIA_MCP_CLIENT,
                  client_version::String=MCPClient_VERSION,
                  log_level::Symbol=:info,
                  setup_command::Union{String, Cmd, Nothing}=nothing) where T
    
    transport = create_transport(url, transport_type; env, setup_command)
    
    
    client = MCPClient(; transport, log_level)
    
    client.output_task = @async while true
        message = read_message(transport)
        message === nothing && sleep(0.01)  # Avoid busy waiting
        message === nothing && sleep(0.04)  # Avoid busy waiting
        message === nothing && sleep(0.05)  # Avoid busy waiting
        message === nothing && break
        handle_server_output(client, message, stdout_handler, log_level)
    end
    
    # Wait for connection to be established (up to 5 seconds)
    connection_timeout = 5.0
    start_time = time()
    
    # Wait until connected or timeout
    while !is_connected(transport) && (time() - start_time < connection_timeout)
        sleep(0.01)
    end
    
    # Auto-initialize if requested and connection is established
    if auto_initialize && is_connected(transport)
        client.log_level == :debug && @debug "Connection established, sending initialize request"
        initialize(client; client_name, client_version)
    elseif auto_initialize && !is_connected(transport)
        @warn "Connection not established within timeout, skipping initialization"
    end
    
    return client
end

function MCPClient(path::String; 
                  env::Union{Dict{String,T}, Nothing}=nothing, 
                  transport_type::Symbol=:stdio,
                  stdout_handler::Function=(str)->nothing,
                  auto_initialize::Bool=true,
                  client_name::String=JULIA_MCP_CLIENT,
                  client_version::String=MCPClient_VERSION,
                  setup_command::Union{String, Cmd, Nothing}=nothing,
                  log_level::Symbol=:info) where T
    executer = if endswith(path, ".py")
        "python3"
    elseif endswith(path, ".js")
        "node"
    else
        error("Server script must be a .py or .js file: $path")
    end

    return MCPClient(executer, [path]; env, stdout_handler, auto_initialize, client_name, client_version, setup_command, log_level, transport_type)
end

function handle_server_output(client::MCPClient, line::String, stdout_handler::Function, log_level::Symbol=:info)
	log_level == :debug && stdout_handler(line)
	
	client.buffer *= line
    # @show client.buffer
	try
		parsed_json = JSON.parse(client.buffer)
		
		# Process valid JSON-RPC response
		if haskey(parsed_json, "id") && haskey(parsed_json, "jsonrpc")
			# Convert to JSONRPCResponse or JSONRPCError
			req_id = parsed_json["id"]
			
			if haskey(parsed_json, "result")
				# Success response
				response = JSONRPCResponse(
					jsonrpc = parsed_json["jsonrpc"],
					id = req_id,
					result = parsed_json["result"]
				)
			elseif haskey(parsed_json, "error")
				# Error response
				response = JSONRPCError(
					jsonrpc = parsed_json["jsonrpc"],
					id = req_id,
					error = parsed_json["error"]
				)
			else
				@warn "Unknown response format: $parsed_json"
				return
			end
			
			client.responses[req_id] = response
			client.buffer = ""
			client.pending_requests[req_id] = false
			
		elseif haskey(parsed_json, "jsonrpc") && haskey(parsed_json, "method")
			# Convert to JSONRPCNotification
			notification = JSONRPCNotification(
				jsonrpc = parsed_json["jsonrpc"],
				method = parsed_json["method"],
				params = get(parsed_json, "params", nothing)
			)
			
			push!(client.notifications, notification)
			
			if notification.method == "notifications/cancelled"
				reason = get(notification.params, "reason", "Unknown reason")
				@warn "Request cancelled: $reason"
				close(client)
			else
				# Log other notifications at info level
                @info "Notification received: $(response)"
			end
			client.buffer = ""
		else
			@warn "Unknown message format: $parsed_json"
		end
	catch e
		# Reset buffer if it gets too large
		if length(client.buffer) > 10000
			@warn "Buffer too large, resetting. Error: $e"
			client.buffer = ""
		end
	end
end

function Base.close(client::MCPClient)
	if client.transport !== nothing
		close_transport(client.transport)
	elseif client.process !== nothing
		try kill(client.process) catch end
	end
	
	if client.output_task !== nothing && client.output_task.state != :done && client.output_task.state != :failed
		Base.schedule(client.output_task, InterruptException(); error=true)
	end
end

function get_mcp_client_copy(client::MCPClient, env::Dict{String,T}) where T # TODO this should be assigned and use the MCPClient constructor
    if (isa(client.transport, WebSocketTransport) || isa(client.transport, SSETransport)) && client.transport.url !== nothing # URL-based client (WebSocket or SSE)
        return MCPClient(client.transport.url, transport_type(client.transport); env, 
                  setup_command=client.transport.setup_command, 
                  log_level=client.log_level)
    elseif isa(client.transport, StdioTransport) && client.transport.command !== nothing # Command-based client
        return MCPClient(client.transport.command, String[]; 
                  env, transport_type=transport_type(client.transport), 
                  setup_command=client.transport.setup_command, 
                  log_level=client.log_level)
    end
	
	return error("Cannot restart client with new environment - no command/path or SSE/WebSocket URL available")
end

# Client level functions
function list_tools(client::MCPClient, server_id::String="")
    !isempty(client.tools_by_name) && return client.tools_by_name

    response = send_request(client, method="tools/list")
    
    (response === nothing || response.result === nothing || !haskey(response.result, "tools")) && return client.tools_by_name
    client.tools_by_name = [MCPToolSpecification(server_id, tool_dict, get_env(client)) for tool_dict in response.result["tools"]]
    return client.tools_by_name
end
function print_tools(tools_array::Vector{MCPToolSpecification})
    for (i, tool) in enumerate(tools_array)
        name = tool.name
        desc = tool.description
        schema = tool.input_schema
        props = schema.properties
        required = schema.required

        
        println("\n$name: $desc")
        println("  Required params: $(join(required, ", "))")
        
        println("  Parameters:")
        for (param, details) in props
            type_str = details.type
            param_desc = details.description
            req_str = param in required ? "[REQUIRED]" : "[optional]"
            println("    • $param ($type_str) $req_str: $param_desc")
        end
        
        i < length(tools_array) && println("---")
    end
end

function initialize(client::MCPClient; 
                   protocol_version::String="0.1.0", 
                   client_name::String=JULIA_MCP_CLIENT, 
                   client_version::String=MCPClient_VERSION, 
                   capabilities::Dict=Dict())
    params = Dict(
        "protocolVersion" => protocol_version,
        "clientInfo" => Dict(
            "name"    => client_name,
            "version" => client_version
        ),
        "capabilities" => capabilities
    )
    check_process_exited(client.transport)
    println("initialize $params")
    response = send_request(client, method="initialize", params=params)
    
    # Send initialized notification after successful initialization
    response !== nothing && send_notification(client, method="notifications/initialized")
    
    return response
end

function send_notification(client::MCPClient; method::String, params::Dict=Dict())
    # Could create a JSONRPCNotification type and use it here
    notification = Dict(
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params
    )
    
    json_str = JSON.json(notification)
    write_message(client.transport, json_str)
    
    return Dict("result" => "notification sent")
end

function list_resources(client::MCPClient)
    response = send_request(client, method="resources/list")
    
    (response === nothing || response.result === nothing || !haskey(response.result, "resources")) && return Resource[]
    
    resources = Resource[]
    for resource_data in response.result["resources"]
        push!(resources, Resource(
            uri = resource_data["uri"],
            name = resource_data["name"],
            description = get(resource_data, "description", nothing),
            mimeType = get(resource_data, "mimeType", nothing),
            annotations = get(resource_data, "annotations", nothing),
            size = get(resource_data, "size", nothing)
        ))
    end
    
    return resources
end

read_resource(client::MCPClient, uri::String) = send_request(client, method="resources/read", params=Dict("uri" => uri))
subscribe_resource(client::MCPClient, uri::String) = send_request(client, method="resources/subscribe", params=Dict("uri" => uri))
unsubscribe_resource(client::MCPClient, uri::String) = send_request(client, method="resources/unsubscribe", params=Dict("uri" => uri))

function send_request(client::MCPClient; method::String, params::Dict=Dict())
    req_id = (client.req_id += 1)
    client.pending_requests[req_id] = true
    
    # Use keyword constructor for @kwdef struct
    request = JSONRPCRequest(id=req_id, method=method, params=isempty(params) ? nothing : params)
    json_str = JSON.json(request)
    
    write_message(client.transport, json_str)
    
    # Wait for response with timeout
    timeout = 5.0
    start_time = time()
    
    while client.pending_requests[req_id] && (time() - start_time < timeout)
        sleep(0.1)
    end
    
    return haskey(client.responses, req_id) ? client.responses[req_id] : nothing
end

call_tool(client::MCPClient, raw_js_request::String) = write_message(client.transport, raw_js_request)
function call_tool(client::MCPClient, tool_name::String, arguments::Dict)
    response = send_request(client, method="tools/call", params=Dict("name" => tool_name, "arguments" => arguments))
    
    (response === nothing || response.result === nothing || !haskey(response.result, "content")) && return nothing
    
    content = Content[]
    for item in response.result["content"]
        if item["type"] == "text"
            push!(content, TextContent(text=item["text"], annotations=get(item, "annotations", nothing)))
        elseif item["type"] == "image"
            push!(content, ImageContent(data=item["data"], mimeType=item["mimeType"], annotations=get(item, "annotations", nothing)))
        # Add other content types as needed
        end
    end
    
    return CallToolResult(content, get(response.result, "isError", nothing), get(response.result, "_meta", nothing))
end
