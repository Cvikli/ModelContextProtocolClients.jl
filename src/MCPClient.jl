
@kwdef mutable struct MCPClient
	command::Union{String, Nothing} = nothing
	path::Union{String, Nothing} = nothing
	process::Union{Process, Nothing} = nothing
	transport::Union{TransportLayer, Nothing} = nothing
	output_task::Union{Task, Nothing} = nothing
	env::Union{Dict{String,String}, Nothing} = nothing
	req_id::Int=0
	tools_by_name::Vector{Dict{String, Any}} = Vector{Dict{String, Any}}()
	responses::Dict{Int, Dict} = Dict{Int, Dict}()
	notifications::Vector{Dict} = Vector{Dict}()
	pending_requests::Dict{Int, Bool} = Dict{Int, Bool}()
	buffer::String = ""
	setup_command::Union{String, Cmd, Nothing} = nothing
    log_level::Symbol=:info
end

# Overload: Accept a command and arguments (stdio transport)
function MCPClient(command::Union{Cmd, String}, args::Vector{String}=String[]; 
                  env::Union{Dict{String,String}, Nothing}=nothing, 
                  stdout_handler::Function=(str)->println("SERVER: $str"),
                  auto_initialize::Bool=true,
                  client_name::String="julia-mcp-client",
                  client_version::String=MCPclient_VERSION,
                  setup_command::Union{String, Cmd, Nothing}=nothing,
                  log_level::Symbol=:info)
    # Create transport layer with process handling
    transport = StdioTransport(command, args; env=env, setup_command=setup_command)

    # Create client
    client = MCPClient(
        command=string(command),
        path=command isa Cmd ? "" : join(args, " "),
        process=transport.process,
        transport=transport,
        env=env,
        setup_command=setup_command,
        log_level=log_level
    )
    
    client.output_task = @async while true
        message = read_message(transport)
        message === nothing && break
        handle_server_output(client, message, stdout_handler)
    end
    
    # Auto-initialize if requested
    if auto_initialize
        initialize(client, client_name=client_name, client_version=client_version)
    end
    
    return client
end

# WebSocket transport constructor
function MCPClient(url::String, transport_type::Symbol; 
                  stdout_handler::Function=(str)->println("SERVER: $str"),
                  auto_initialize::Bool=true,
                  client_name::String="julia-mcp-client",
                  client_version::String=MCPclient_VERSION,
                  log_level::Symbol=:info)
    
    transport = if transport_type == :websocket
        WebSocketTransport(url)
    elseif transport_type == :sse
        SSETransport(url)
    else
        error("Unsupported transport type: $transport_type. Use :websocket or :sse")
    end
    
    # Create client
    client = MCPClient(
        transport=transport,
        log_level=log_level
        # Don't set path explicitly since it defaults to nothing
    )
    
    client.output_task = @async while true
        message = read_message(transport)
        message === nothing && sleep(0.1)  # Avoid busy waiting
        message === nothing && continue
        handle_server_output(client, message, stdout_handler, log_level)
    end
    
    # Wait for connection to be established (up to 5 seconds)
    connection_timeout = 5.0
    start_time = time()
    
    # Check connection based on transport type
    is_connected() = transport_type == :sse ? 
                     transport.session_id !== nothing : 
                     transport.ws !== nothing
    
    # Wait until connected or timeout
    while !is_connected() && (time() - start_time < connection_timeout)
        sleep(0.01)
    end
    
    # Auto-initialize if requested and connection is established
    if auto_initialize && is_connected()
        client.log_level == :debug && @debug "Connection established, sending initialize request"
        initialize(client, client_name=client_name, client_version=client_version)
    elseif auto_initialize && !is_connected()
        @warn "Connection not established within timeout, skipping initialization"
    end
    
    return client
end

function MCPClient(path::String; 
                  env::Union{Dict{String,String}, Nothing}=nothing, 
                  stdout_handler::Function=(str)->nothing,
                  auto_initialize::Bool=true,
                  client_name::String="julia-mcp-client",
                  client_version::String=MCPclient_VERSION,
                  setup_command::Union{String, Cmd, Nothing}=nothing,
                  log_level::Symbol=:info)
    !isfile(path) && error("Server script not found: $path")
    command = if endswith(path, ".py")
        "python3"
    elseif endswith(path, ".js")
        "node"
    else
        error("Server script must be a .py or .js file: $path")
    end

    return MCPClient(command, [path]; 
                    env=env, 
                    stdout_handler=stdout_handler, 
                    auto_initialize=auto_initialize,
                    client_name=client_name,
                    client_version=client_version,
                    setup_command=setup_command,
                    log_level=log_level)
end

function handle_server_output(client::MCPClient, line::String, stdout_handler::Function, log_level::Symbol=:info)
	log_level == :debug && stdout_handler(line)
	
	client.buffer *= line
	try
		# @show "hey"
		response = JSON.parse(client.buffer)
		# @show response
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
	
	if client.output_task !== nothing && client.output_task.state != :done
		Base.schedule(client.output_task, InterruptException(); error=true)
	end
end

function restart_with_env(client::MCPClient, env::Dict{String,String})
	close(client)
	
	if client.command !== nothing && client.path !== nothing
		process = open(pipeline(setenv(`$(client.command) $(client.path)`, env), stderr=stdout), "r+")
		transport = StdioTransport(process)
		
		client.process = process
		client.transport = transport
		client.output_task = @async while true
			message = read_message(transport)
			message === nothing && break
			println("SERVER: $message")
		end
		client.req_id = 0
	else
		error("Cannot restart client with new environment - no command/path available")
	end
	
	return client
end

# Client level functions
function list_tools(client::MCPClient)
	response = send_request(client, method="tools/list")
	
	# Parse tools from response
	if response !== nothing && 
	   haskey(response, "result") && 
	   haskey(response["result"], "tools")
		client.tools_by_name = [tool for tool in response["result"]["tools"]]
	end
	
	return client.tools_by_name
end

function initialize(client::MCPClient; 
                   protocol_version::String="0.1.0", 
                   client_name::String="julia-mcp-client", 
                   client_version::String=MCPclient_VERSION, 
                   capabilities::Dict=Dict())
    params = Dict(
        "protocolVersion" => protocol_version,
        "clientInfo" => Dict(
            "name" => client_name,
            "version" => client_version
        ),
        "capabilities" => capabilities
    )
    
    response = send_request(client, method="initialize", params=params)
    
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

function send_request(client::MCPClient; method::String, params::Dict=Dict())
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
