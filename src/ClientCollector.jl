@kwdef struct MCPCollector
	servers::Dict{String, MCPClient} = Dict{String, MCPClient}()
end

add_server(collector::MCPCollector, server_id::String, path::String, env::Union{Dict{String, String}, Nothing}=nothing, stdout_handler::Function=(str)->println("SERVER: $str")) = collector.servers[server_id] = MCPClient(path; env, stdout_handler)
remove_server(collector::MCPCollector, server_id::String) = haskey(collector.servers, server_id) && (close(collector.servers[server_id]); delete!(collector.servers, server_id))
disconnect_all(collector::MCPCollector) = (for (_, client) in collector.servers; close(client); end; empty!(collector.servers))

get_all_tools(collector::MCPCollector) = [(server_id, tool_name, info) for (server_id, client) in collector.servers for (tool_name, info) in client.tools_by_name]
list_tools(collector::MCPCollector, server_id::String) = isempty(collector.servers[server_id].tools_by_name) ? list_tools(collector.servers[server_id]) : collector.servers[server_id].tools_by_name

function call_tool(collector::MCPCollector, server_id::String, tool_name::String, arguments::Dict)
	!haskey(collector.servers, server_id) && error("Server $server_id not found or added")
	return call_tool(collector.servers[server_id], tool_name, arguments)
end

function load_mcp_servers_config(collector::MCPCollector, config_path::String)
	config = JSON.parse(read(config_path, String))
	
	for (server_id, server_config) in config["mcpServers"]
		command = server_config["command"]
		args = server_config["args"]
		env = get(server_config, "env", nothing)
		
		# Convert env to Dict{String,String} if present
		env_dict = env === nothing ? nothing : Dict{String,String}(k => string(v) for (k,v) in env)
		
		# Create command array and join with spaces
		cmd_array = [command, args...]
		cmd_str = join(cmd_array, " ")
		
		# Create MCPClient
		add_server(collector, server_id, cmd_str; env=env_dict)
	end
	
	return collector
end


