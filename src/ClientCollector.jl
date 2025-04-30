@kwdef struct MCPCollector
	servers::Dict{String, MCPClient} = Dict{String, MCPClient}()
end
list_clients(collector::MCPCollector) = collect(keys(collector.servers))

# Add server with a path
function add_server(collector::MCPCollector, server_id::String, path::String; 
                   env::Union{Dict{String, String}, Nothing}=nothing, 
                   stdout_handler::Function=(str)->println("SERVER: $str"),
                   auto_initialize::Bool=true,
                   client_name::String="julia-mcp-client",
                   client_version::String=MCP.MCP_VERSION,
                   setup_command::Union{String, Cmd, Nothing}=nothing)
    collector.servers[server_id] = MCPClient(path; 
                                           env=env, 
                                           stdout_handler=stdout_handler,
                                           auto_initialize=auto_initialize,
                                           client_name=client_name,
                                           client_version=client_version,
                                           setup_command=setup_command)
end

function add_server(collector::MCPCollector, server_id::String, command::String, args::Vector{String}; 
                   env::Union{Dict{String, String}, Nothing}=nothing, 
                   stdout_handler::Function=(str)->println("SERVER: $str"),
                   auto_initialize::Bool=true,
                   client_name::String="julia-mcp-client",
                   client_version::String=MCP.MCP_VERSION,
                   setup_command::Union{String, Cmd, Nothing}=nothing)
    collector.servers[server_id] = MCPClient(command, args; 
                                           env=env, 
                                           stdout_handler=stdout_handler,
                                           auto_initialize=auto_initialize,
                                           client_name=client_name,
                                           client_version=client_version,
                                           setup_command=setup_command)
end

# Add server with a URL (WebSocket or SSE)
function add_server(collector::MCPCollector, server_id::String, url::String, transport_type::Symbol; 
                   stdout_handler::Function=(str)->println("SERVER: $str"),
                   auto_initialize::Bool=true,
                   client_name::String="julia-mcp-client",
                   client_version::String=MCP.MCP_VERSION)
    collector.servers[server_id] = MCPClient(url, transport_type; 
                                           stdout_handler=stdout_handler,
                                           auto_initialize=auto_initialize,
                                           client_name=client_name,
                                           client_version=client_version)
end

remove_server(collector::MCPCollector, server_id::String) = haskey(collector.servers, server_id) && (close(collector.servers[server_id]); delete!(collector.servers, server_id))
disconnect_all(collector::MCPCollector) = (for (_, client) in collector.servers; close(client); end; empty!(collector.servers))


get_all_tools(collector::MCPCollector) = [(server_id, tool_name, info) for (server_id, client) in collector.servers for (tool_name, info) in client.tools_by_name]
list_tools(collector::MCPCollector, server_id::String) = isempty(collector.servers[server_id].tools_by_name) ? list_tools(collector.servers[server_id]) : collector.servers[server_id].tools_by_name

function call_tool(collector::MCPCollector, server_id::String, tool_name::String, arguments::Dict)
	!haskey(collector.servers, server_id) && error("Server $server_id not found or added")
	return call_tool(collector.servers[server_id], tool_name, arguments)
end

# Supporting
# - claude_desktop_config.json
# - mcp.json
function load_mcp_servers_config(collector::MCPCollector, config_path::String;
                                auto_initialize::Bool=true,
                                client_name::String="julia-mcp-client",
                                client_version::String=MCP.MCP_VERSION,
                                log_level::Symbol=:info)
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
		# Check if this is a URL-based server (WebSocket or SSE)
		if haskey(server_config, "url")
			url = server_config["url"]
			transport_type = if haskey(server_config, "transport")
				Symbol(server_config["transport"])
			elseif occursin("/sse", url)
				:sse
			elseif occursin("ws://", url) || occursin("wss://", url)
				:websocket
			else
				:websocket  # Default to WebSocket
			end
			
			add_server(collector, server_id, url, transport_type;
					  auto_initialize=auto_initialize,
					  client_name=client_name,
					  client_version=client_version)
		else
			# Standard command-based server
			command = server_config["command"]
			args = String.(get(server_config, "args", String[]))
			env = get(server_config, "env", nothing)
			
			# Convert env to Dict{String,String} if present
			env_dict = env === nothing ? nothing : Dict{String,String}(k => string(v) for (k,v) in env)
			
			# Add server using the command and args directly
			add_server(collector, server_id, command, args; 
					  env=env_dict,
					  auto_initialize=auto_initialize,
					  client_name=client_name,
					  client_version=client_version,
					  setup_command=nothing)
		end
	end

	# Print loaded servers
	println("Loaded servers:")
	for (server_id, client) in collector.servers
		if client.transport !== nothing
			println(" - $server_id: $(typeof(client.transport))")
		else
			println(" - $server_id: $(client.command) $(client.path)")
		end
	end
	
	return collector
end

function explore_mcp_servers_in_directory(collector::MCPCollector, directory::String; 
                              exclude_patterns::Vector{String}=String[".git", "node_modules"],
                              auto_initialize::Bool=true,
                              stdout_handler::Function=(str)->println("SERVER: $str"),
                              client_name::String="julia-mcp-client",
                              client_version::String=MCP.MCP_VERSION,
                              log_level::Symbol=:info)
    !isdir(directory) && error("Directory not found: $directory")

    folders_n_files = readdir(directory, join=true) # Get all folders_n_files in the directory (non-recursive)

    # Filter out non-directories and excluded patterns
    project_dirs = filter(folders_n_files) do file
      !isdir(file) && return false

      for pattern in exclude_patterns 
        occursin(Regex(replace(pattern, "*" => ".*")), basename(file)) && return false
      end

      return true
    end

    # Try to load each potential MCP server
    loaded_servers = 0
    for project_dir in project_dirs
      server_id = basename(project_dir)

      if haskey(collector.servers, server_id)
        @info "Server with ID '$server_id' already exists, skipping: $project_dir"
        continue
      end

      # Detect project type
      is_nodejs = isfile(joinpath(project_dir, "package.json"))
      is_python = isfile(joinpath(project_dir, "pyproject.toml"))

      # Initialize command, args and setup_command
      command = nothing
      args = String[]
      setup_command = nothing

      if is_nodejs
        command = "node"
        args = String["$(project_dir)/dist/index.js"]
        setup_command = "cd $(project_dir) && npm run build"
      elseif is_python
        # Handle Python projects
        pyproject_path = joinpath(project_dir, "pyproject.toml")
        pyproject_content = read(pyproject_path, String)
        # Extract project name
        project_name_match = match(r"\[project\]\s*name\s*=\s*\"([^\"]+)\"", pyproject_content)
        project_name = project_name_match !== nothing ? project_name_match.captures[1] : nothing

        command = "python3"
        args = String["-m", project_name]
        setup_command = "cd $(project_dir) && pip install -e ."
      end

      # Skip if no command found
      if command === nothing
        @info "No entry point found for project: $project_dir"
        continue
      end
      
      # Add the server
      add_server(collector, server_id, command, args; 
                stdout_handler=stdout_handler,
                auto_initialize=auto_initialize,
                client_name=client_name,
                client_version=client_version,
                setup_command=setup_command)
      
      @info "Successfully loaded MCP server '$server_id'"
      loaded_servers += 1
    end
    
    @info "Explored directory: $directory. Found $loaded_servers MCP servers."
    return collector
end
