@kwdef struct MCPClientCollector
	servers::Dict{String, MCPClient} = Dict{String, MCPClient}()
end
list_clients(collector::MCPClientCollector) = collect(keys(collector.servers))

# Unified add_server function that handles all cases based on provided kwargs
add_server(collector::MCPClientCollector, server_id::String, client::MCPClient) = return collector.servers[server_id] = client
function add_server(collector::MCPClientCollector, server_id::String;
                    # Common parameters
                    stdout_handler::Function=(str)->println("SERVER: $str"),
                    auto_initialize::Bool=true,
                    client_name::String=JULIA_MCP_CLIENT,
                    client_version::String=MCPClient_VERSION,
                    setup_command::Union{String, Cmd, Nothing}=nothing,
                    log_level::Symbol=:info,
                    # Path-based parameters
                    path::Union{String, Nothing}=nothing,
                    transport_type::Symbol=:stdio,
                    # Command-based parameters
                    command::Union{String, Nothing}=nothing,
                    args::Vector{String}=String[],
                    env::Union{Dict{String, String}, Nothing}=nothing,
                    # URL-based parameters
                    url::Union{String, Nothing}=nothing)
    
    return collector.servers[server_id] = if url !== nothing # URL-based client (WebSocket or SSE)
        MCPClient(url, transport_type; stdout_handler, 
                  auto_initialize, client_name, 
                  client_version, setup_command, log_level)
    elseif path !== nothing # Path-based client
        MCPClient(path; 
                  env, transport_type, stdout_handler,
                  auto_initialize, client_name, 
                  client_version, setup_command, log_level)
    elseif command !== nothing # Command-based client
        MCPClient(command, args; 
                  env, transport_type, stdout_handler, 
                  auto_initialize, client_name, 
                  client_version, setup_command, log_level)
    end
    error("Invalid parameters: must provide either 'url', 'path', or 'command'")
end

remove_server(collector::MCPClientCollector, server_id::String) = haskey(collector.servers, server_id) && (close(collector.servers[server_id]); delete!(collector.servers, server_id))
disconnect_all(collector::MCPClientCollector)                   = (for (_, client) in collector.servers; close(client); end; empty!(collector.servers))


get_all_tools(collector::MCPClientCollector)                 = [(server_id, tool_name, info) for (server_id, client) in collector.servers for (tool_name, info) in client.tools_by_name]
list_all_tools(collector::MCPClientCollector)                = Dict(server_id=>list_tools(client) for (server_id, client) in collector.servers)
list_tools(collector::MCPClientCollector, server_id::String) = isempty(collector.servers[server_id].tools_by_name) ? list_tools(collector.servers[server_id]) : collector.servers[server_id].tools_by_name

function call_tool(collector::MCPClientCollector, server_id::String, tool_name::String, arguments::Dict)
	!haskey(collector.servers, server_id) && error("Server $server_id not found or added")
	return call_tool(collector.servers[server_id], tool_name, arguments)
end

# Supporting
# - claude_desktop_config.json
# - mcp.json
function load_mcp_servers_config(collector::MCPClientCollector, config_path::String;
                                workdir_prefix::String="",
                                auto_initialize::Bool=true,
                                client_name::String=JULIA_MCP_CLIENT,
                                client_version::String=MCPClient_VERSION,
                                log_level::Symbol=:info,
                                setup_command::Union{String, Cmd, Nothing}=nothing)
	config = JSON.parse(read(config_path, String))
	
	# Check if we have the "mcp" key structure
	if haskey(config, "mcp") && haskey(config["mcp"], "servers")
		servers_config = config["mcp"]["servers"]
	elseif haskey(config, "mcpServers")
		servers_config = config["mcpServers"]
	else
		error("Invalid MCP server configuration format. Expected 'mcp.servers' or 'mcpServers' key in the config file.")
	end

	cd(isempty(workdir_prefix) ? "." : workdir_prefix) do 
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
          :stdio  # Default to WebSocket
        end
        
        add_server(collector, server_id; url, transport_type, auto_initialize, client_name, client_version, setup_command, log_level)
      else
        # Clone from gitUrl if specified and directory doesn't exist
        dir = joinpath(workdir_prefix, server_id)
        haskey(server_config, "gitUrl") && !isdir(dir) && run(`git clone $(server_config["gitUrl"]) $dir`)
        # Standard command-based server
        command = server_config["command"]
        args = String.(get(server_config, "args", String[]))
        env = get(server_config, "env", nothing)
        setup_command = get(server_config, "setup_command", nothing)
        
        # Convert env to Dict{String,String} if present
        env_dict = env === nothing ? nothing : Dict{String,String}(k => string(v) for (k,v) in env)
        
        @show env_dict
        # Add server using the command and args directly
        add_server(collector, server_id; command, args, auto_initialize, client_name, client_version, setup_command, log_level, env=env_dict)
      end
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

function explore_mcp_servers_in_directory(collector::MCPClientCollector, directory::String; 
                              exclude_patterns::Vector{String}=String[".git", "node_modules"],
                              auto_initialize::Bool=true,
                              stdout_handler::Function=(str)->println("SERVER: $str"),
                              client_name::String=JULIA_MCP_CLIENT,
                              client_version::String=MCPClient_VERSION,
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
      add_server(collector, server_id; command, args, stdout_handler, auto_initialize, client_name, client_version, setup_command)
      
      @info "Successfully loaded MCP server '$server_id'"
      loaded_servers += 1
    end
    
    @info "Explored directory: $directory. Found $loaded_servers MCP servers."
    return collector
end
