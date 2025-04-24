import Base: Process

@kwdef mutable struct MCPClient
	command::String
	path::String
	process::Process
	output_task::Task
	env::Union{Dict{String,String}, Nothing}
	req_id::Int=0
	tools_by_name::Vector{Dict{String, Any}} = Vector{Dict{String, Any}}()
	responses::Dict{Int, Dict} = Dict{Int, Dict}()
	notifications::Vector{Dict} = Vector{Dict}()
	pending_requests::Dict{Int, Bool} = Dict{Int, Bool}()
	buffer::String = ""
end

function MCPClient(path::String; env::Union{Dict{String,String}, Nothing}=nothing, stdout_handler::Function=(str)->println("SERVER: $str"))
	!isfile(path) && error("Server script not found: $path")
	command = if endswith(path, ".py")
		module_path = dirname(path)
		module_name = basename(module_path)
		# "python3 -m $module_name"
		"python3"  # Just the command, arguments will be passed separately
	elseif endswith(path, ".js")
		"node"
	else
		error("Server script must be a .py or .js file: $path")
	end

	process = env === nothing ? 
		open(pipeline(`$command $path`, stderr=stdout), "r+") : 
		open(pipeline(setenv(`$command $path`, env), stderr=stdout), "r+")
	
	client = MCPClient(command=command, path=path, process=process, env=env, output_task=Task(() -> nothing))
	
	client.output_task = @async while !eof(process)
		line = readline(process)
		handle_server_output(client, line, stdout_handler)
	end
	
	return client
end

function handle_server_output(client::MCPClient, line::String, stdout_handler::Function)
	# Always log output
	stdout_handler(line)
	
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
			client.buffer = ""
		end
	catch
		# Reset buffer if it gets too large
		length(client.buffer) > 10000 && (client.buffer = "")
	end
end

function Base.close(client::MCPClient)
	try kill(client.process) catch end
	client.output_task.state != :done && Base.schedule(client.output_task, InterruptException(); error=true)
end

function restart_with_env(client::MCPClient, env::Dict{String,String})
	close(client)
	process = open(pipeline(setenv(`$(client.command) $(client.path)`, env), stderr=stdout), "r+")
	output_task = @async while !eof(process) println("SERVER: $(readline(process))") end
	
	client.process = process
	client.output_task = output_task
	client.req_id = 0
	
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

call_tool(client::MCPClient, raw_request::String)                = send_request(client, raw_request)
call_tool(client::MCPClient, tool_name::String, arguments::Dict) = send_request(client, method="tools/call", params=Dict("name" => tool_name, "arguments" => arguments))

function send_request(client::MCPClient; method::String, params::Dict=Dict())
	req_id = (client.req_id += 1)
	
	# Mark request as pending
	client.pending_requests[req_id] = true
	
	json_str = """{"jsonrpc":"2.0","id":$(req_id),"method":"$method","params":$(JSON.json(params))}"""
	@show json_str
	
	write(client.process, json_str * "\n") # Send the request
	flush(client.process)
	
	# Wait for response with timeout
	timeout = 5.0  # 5 second timeout
	start_time = time()
	
	while client.pending_requests[req_id] && (time() - start_time < timeout)
		sleep(0.1)  # Brief pause to allow response processing
	end
	
	# Return response if we got one
	if haskey(client.responses, req_id)
		result = client.responses[req_id]
		return result
	end
	
	return nothing  # No response received within timeout
end

function send_request(client::MCPClient, json_str::String)
	write(client.process, json_str * "\n") # for safety we send a newline (as what if the user forget that)
	flush(client.process)
	sleep(0.5)  # Allow time for server to respond
end
