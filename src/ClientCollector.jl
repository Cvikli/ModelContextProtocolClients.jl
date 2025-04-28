@kwdef struct MCPCollector
	servers::Dict{String, MCPClient} = Dict{String, MCPClient}()
end

# Add server with a path
function add_server(collector::MCPCollector, server_id::String, path::String; 
                   env::Union{Dict{String, String}, Nothing}=nothing, 
                   stdout_handler::Function=(str)->println("SERVER: $str"),
                   auto_initialize::Bool=true,
                   client_name::String="julia-mcp-client",
                   client_version::String=MCP.MCP_VERSION)
    collector.servers[server_id] = MCPClient(path; 
                                           env=env, 
                                           stdout_handler=stdout_handler,
                                           auto_initialize=auto_initialize,
                                           client_name=client_name,
                                           client_version=client_version)
end

remove_server(collector::MCPCollector, server_id::String) = haskey(collector.servers, server_id) && (close(collector.servers[server_id]); delete!(collector.servers, server_id))
disconnect_all(collector::MCPCollector) = (for (_, client) in collector.servers; close(client); end; empty!(collector.servers))

# Add server with command and args
function add_server(collector::MCPCollector, server_id::String, command::String, args::Vector{String}; 
                   env::Union{Dict{String, String}, Nothing}=nothing, 
                   stdout_handler::Function=(str)->println("SERVER: $str"),
                   auto_initialize::Bool=true,
                   client_name::String="julia-mcp-client",
                   client_version::String=MCP.MCP_VERSION)
    collector.servers[server_id] = MCPClient(command, args; 
                                           env=env, 
                                           stdout_handler=stdout_handler,
                                           auto_initialize=auto_initialize,
                                           client_name=client_name,
                                           client_version=client_version)
end

get_all_tools(collector::MCPCollector) = [(server_id, tool_name, info) for (server_id, client) in collector.servers for (tool_name, info) in client.tools_by_name]
list_tools(collector::MCPCollector, server_id::String) = isempty(collector.servers[server_id].tools_by_name) ? list_tools(collector.servers[server_id]) : collector.servers[server_id].tools_by_name

function call_tool(collector::MCPCollector, server_id::String, tool_name::String, arguments::Dict)
	!haskey(collector.servers, server_id) && error("Server $server_id not found or added")
	return call_tool(collector.servers[server_id], tool_name, arguments)
end

function load_mcp_servers_config(collector::MCPCollector, config_path::String;
                                auto_initialize::Bool=true,
                                client_name::String="julia-mcp-client",
                                client_version::String=MCP.MCP_VERSION)
	config = JSON.parse(read(config_path, String))
	
	# Check if we have the "mcp" key structure
	if haskey(config, "mcp") && haskey(config["mcp"], "servers")
		servers_config = config["mcp"]["servers"]
	elseif haskey(config, "mcpServers")
		servers_config = config["mcpServers"]
	else
		error("Invalid MCP server configuration format. Expected 'mcp.servers' or 'mcpServers' key.")
	end
	
	for (server_id, server_config) in servers_config
		command = server_config["command"]
		args = server_config["args"]
		env = get(server_config, "env", nothing)
		
		# Convert env to Dict{String,String} if present
		env_dict = env === nothing ? nothing : Dict{String,String}(k => string(v) for (k,v) in env)
		
		# Add server using the command and args directly
		add_server(collector, server_id, command, args; 
				  env=env_dict,
				  auto_initialize=auto_initialize,
				  client_name=client_name,
				  client_version=client_version)
	end
	
	return collector
end


