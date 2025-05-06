@kwdef mutable struct MCPClient
	transport::Union{TransportLayer, Nothing} = nothing
	output_task::Union{Task, Nothing} = nothing
	req_id::Int=0
	tools_by_name::Vector{Dict{String, Any}} = Vector{Dict{String, Any}}()
	responses::Dict{Int, Dict} = Dict{Int, Dict}()
	notifications::Vector{Dict} = Vector{Dict}()
	pending_requests::Dict{Int, Bool} = Dict{Int, Bool}()
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
		# @show "hey"
		response = JSON.parse(client.buffer)
		# Process valid JSON-RPC response
		if haskey(response, "id") && haskey(response, "jsonrpc") # if "id" is present, it's a response: https://modelcontextprotocol.io/docs/concepts/transports#responses
			req_id = response["id"]
			client.responses[req_id] = response
			client.pending_requests[req_id] = false
			client.buffer = ""
		elseif haskey(response, "jsonrpc") # if no "id" is present, it's a notification: https://modelcontextprotocol.io/docs/concepts/transports#notifications
			push!(client.notifications, response)
            if haskey(response, "method") && response["method"] == "notifications/cancelled"
				@warn "Request cancelled: $(get(response["params"], "reason", "Unknown reason"))"
                close(client)
			else
				# Log other notifications at info level
                @info "Notification received: $(response)"
			end
			client.buffer = ""
		else
			@warn "unknown message: $response"
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
        @show client.output_task
		Base.schedule(client.output_task, InterruptException(); error=true)
	end
end

function get_mcp_client_copy(client::MCPClient, env::Dict{String,T}) where T # TODO this should be assigned and use the MCPClient constructor
    return if (isa(client.transport, WebSocketTransport) || isa(client.transport, SSETransport)) && client.transport.url !== nothing # URL-based client (WebSocket or SSE)
        MCPClient(client.transport.url, transport_type(client.transport); env, 
                  setup_command=client.transport.setup_command, 
                  log_level=client.log_level)
    elseif isa(client.transport, StdioTransport) && client.transport.command !== nothing # Command-based client
        MCPClient(client.transport.command, String[]; 
                  env, 
                  transport_type=transport_type(client.transport), 
                  setup_command=client.transport.setup_command, 
                  log_level=client.log_level)
    end
	
	error("Cannot restart client with new environment - no command/path or SSE/WebSocket URL available")
end

# Client level functions
function list_tools(client::MCPClient)
    !isempty(client.tools_by_name) && return client.tools_by_name

    response = send_request(client, method="tools/list")
    # Parse tools from response
    if response !== nothing && 
        haskey(response, "result") && 
        haskey(response["result"], "tools")
        client.tools_by_name = [tool for tool in response["result"]["tools"]]
    end
	return client.tools_by_name
end
function print_tools(tools_array::Vector{Dict{String, Any}})
    for (i, tool) in enumerate(tools_array)
        name = tool["name"]
        desc = tool["description"]
        schema = tool["inputSchema"]
        props = schema["properties"]
        required = schema["required"]

        
        println("\n$name: $desc")
        println("  Required params: $(join(required, ", "))")
        
        println("  Parameters:")
        for (param, details) in props
            type_str = get(details, "type", "unknown")
            param_desc = get(details, "description", "")
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
    @show "initialize"
    response = send_request(client, method="initialize", params=params)
    @show response
    
    # Send initialized notification after successful initialization
    response !== nothing && send_notification(client, method="notifications/initialized")
    
    return response
end

function send_notification(client::MCPClient; method::String, params::Dict=Dict())
    json_str = """{"jsonrpc":"2.0","method":"$method","params":$(JSON.json(params))}"""
    
    # Use transport layer for all communication
    write_message(client.transport, json_str)
    
    return Dict("result" => "notification sent")
end

list_resources(client::MCPClient)=@assert "unimplemented"
call_tool(client::MCPClient, raw_request::String)                = send_request(client, raw_request)
call_tool(client::MCPClient, tool_name::String, arguments::Dict) = send_request(client, method="tools/call", params=Dict("name" => tool_name, "arguments" => arguments))

function send_request(client::MCPClient; method::String, params::Dict=Dict()) ## TODO can we leave out the params if empty?
	req_id = (client.req_id += 1)
	
	client.pending_requests[req_id] = true
	
	json_str = """{"jsonrpc":"2.0","id":$(req_id),"method":"$method","params":$(JSON.json(params))}"""
	
	write_message(client.transport, json_str)
	
	# Wait for response with timeout
	timeout = 5.0  # 5 second timeout
	start_time = time()
	
	while client.pending_requests[req_id] && (time() - start_time < timeout)
		sleep(0.1)  # Brief pause to allow response processing
	end
	
	# Return response if we got one
	return haskey(client.responses, req_id) ? client.responses[req_id] : nothing
end

function send_request(client::MCPClient, json_str::String)
	# Use transport layer for all communication
	write_message(client.transport, json_str)
end
