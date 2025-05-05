using HTTP
using JSON
using WebSockets

export TransportLayer, StdioTransport, SSETransport, WebSocketTransport
export read_message, write_message, close_transport

abstract type TransportLayer end

# Stdio Transport
struct StdioTransport <: TransportLayer
    process::Base.Process
end

function StdioTransport(command::Union{Cmd, String}, args::Vector{String}=String[]; 
                        env::Union{Dict{String,String}, Nothing}=nothing,
                        setup_command::Union{String, Cmd, Nothing}=nothing)
    # Create command
    cmd = command isa Cmd ? command : `$command $args`
    process = nothing
    
    try
        process = env === nothing ?
            Base.open(pipeline(cmd, stderr=stdout), "r+") :
            Base.open(pipeline(setenv(cmd, env), stderr=stdout), "r+")
    catch e
        if setup_command !== nothing
            @info "Initial process failed, we fallback to run the setup command"
            install_cmd = setup_command isa Cmd ? setup_command : `$setup_command`
            run(install_cmd)
            # Retry process creation after setup
            @show cmd
            process = env === nothing ?
                Base.open(pipeline(cmd, stderr=stdout), "r+") :
                Base.open(pipeline(setenv(cmd, env), stderr=stdout), "r+")
        else
            @info "The run command failed, and we cannot run the setup_command as it wasn't provided, so we give up"
            rethrow(e)
        end
    end
    
    return StdioTransport(process)
end

function read_message(transport::StdioTransport)
    !process_running(transport.process) && return nothing
    !eof(transport.process) ? readline(transport.process) : nothing
end

function write_message(transport::StdioTransport, message::String)
    write(transport.process, message * "\n")
    flush(transport.process)
end

function close_transport(transport::StdioTransport)
    try kill(transport.process) catch end
end

function process_running(process::Base.Process)
    try
        process_exited(process) && return false
        return true
    catch
        return false
    end
end

# SSE Transport
mutable struct SSETransport <: TransportLayer
    url::String
    client::Union{HTTP.Streams.Stream, Nothing}
    buffer::Channel{String}
    task::Union{Task, Nothing}
    session_id::Union{String, Nothing}
    message_endpoint::Union{String, Nothing}  # Store the message endpoint URL
end

function SSETransport(url::String)
    SSETransport(url, nothing, Channel{String}(100), nothing, nothing, nothing)
end

function start_sse_client(transport::SSETransport)
    transport.task = @async begin
        HTTP.open("GET", transport.url) do stream
            transport.client = stream
            current_event = ""
            current_data = ""
            buffer = IOBuffer()
            
            # Use a buffer to read larger chunks at once
            while !eof(stream)
                write(buffer, readavailable(stream))
                seekstart(buffer)
                
                while !eof(buffer)
                    line = readline(buffer)
                    # @show line
                    if startswith(line, "event:")
                        current_event = strip(line[7:end])
                    elseif startswith(line, "data:") || (line !== "" && !isempty(current_data))
                        # Accumulate data lines for the same event
                        if !isempty(current_data)
                            current_data *= line
                        else
                            current_data = strip(line[6:end])
                        end
                    elseif line == "" && !isempty(current_data)  # Empty line marks end of event
                        # Process complete event
                        if current_event == "endpoint"
                            # The server sends the full URI with the session_id as a query parameter
                            @info "Received endpoint event: $current_data"
                            session_id_match = match(r"sessionId=([^&\s]+)", current_data)
                            if session_id_match !== nothing
                                transport.session_id = session_id_match.captures[1]
                                # Store the message endpoint for later use
                                transport.message_endpoint = current_data
                                @info "SSE session established with ID: $(transport.session_id)"
                            else
                                @warn "Failed to extract session_id from endpoint $current_data"
                            end
                        elseif current_event == "message"
                            # Regular message event
                            @debug "Received message event: $current_data"
                            # Try to validate if it's complete JSON before putting in buffer
                            try
                                # Just check if it parses, don't store the result
                                JSON.parse(current_data)
                                put!(transport.buffer, current_data)
                            catch e
                                @warn "Received incomplete JSON in message event, skipping: $(typeof(e))"
                                @debug "Incomplete JSON content: $current_data"
                            end
                        else
                            @debug "Received unknown event type: $current_event with $current_data"
                        end
                        
                        # Reset for next event
                        current_event = ""
                        current_data = ""
                    else
                        @warn "Prepare our protocol to handle this event too"
                        @show current_event
                        @show current_data
                        @warn "Received unknown event type: $line"
                    end
                end
                
                # Reset buffer for next chunk
                seekstart(buffer)
                truncate(buffer, 0)
                sleep(0.01)
            end
        end
    end
end

function read_message(transport::SSETransport)
    if transport.client === nothing
        @info "Starting SSE client connection"
        start_sse_client(transport)
        
        # Wait a short time for the session to be established
        if transport.session_id === nothing
            @info "Waiting for SSE session to be established..."
            for i in 1:30  # Wait up to 15 seconds
                sleep(0.1)
                if transport.session_id !== nothing
                    @info "SSE session established after $(i*0.5) seconds"
                    break
                end
            end
            
            if transport.session_id === nothing
                @warn "Failed to establish SSE session within timeout"
            end
        end
    end
    
    if isready(transport.buffer)
        return take!(transport.buffer)
    end
    
    return nothing
end

function write_message(transport::SSETransport, message::String)
    println("CLIENT: $message")
    # SSE is unidirectional, so we need to make a separate HTTP request
    if transport.session_id === nothing
        @error "Cannot send message: No session_id available"
        @info "Current transport state: client=$(transport.client !== nothing), task_running=$(transport.task !== nothing && !istaskdone(transport.task))"
        
        # Try to reconnect if the client is not connected
        if transport.client === nothing || (transport.task !== nothing && istaskdone(transport.task))
            @info "Attempting to reconnect SSE client before sending message"
            start_sse_client(transport)
            
            # Wait for session establishment
            for i in 1:10
                sleep(0.5)
                if transport.session_id !== nothing
                    @info "SSE session re-established"
                    break
                end
            end
        end
        
        # If still no session, we can't proceed
        # if transport.session_id === nothing
        #     println(stderr, "Stacktrace:")
        #     Base.show_backtrace(stderr, stacktrace())
        #     return
        # end
    end
    
    # Determine the message endpoint URL
    message_url = if transport.message_endpoint !== nothing
        # Use the endpoint provided by the server, but ensure it's an absolute URL
        if startswith(transport.message_endpoint, "/")
            # It's a relative URL, so prepend the base URL
            base_url = replace(transport.url, r"/sse/?.*$" => "")
            base_url * transport.message_endpoint
        else
            # It's already an absolute URL
            transport.message_endpoint
        end
    else
        # Construct the URL based on the server's expected pattern
        base_url = replace(transport.url, r"/sse/?$" => "")
        joinpath(base_url, "messages/") * "?sessionId=" * transport.session_id
    end
    @show message_url
    
    @info "Sending message to: $message_url"
    try
        response = HTTP.post(message_url, 
                ["Content-Type" => "application/json"], 
                message)
        @debug "POST response: $(String(response.body)) ($(response.status))"
    catch e
        @error "Error sending message to SSE server" exception=e url=message_url
    end
end

function close_transport(transport::SSETransport)
    transport.session_id = nothing
    if transport.task !== nothing && !istaskdone(transport.task)
        try 
            schedule(transport.task, InterruptException(); error=true)
            sleep(0.1)
        catch e
            @debug "Error while interrupting SSE task: $e"
        end
    end
    
    if transport.client !== nothing
        try 
            close(transport.client)
            transport.client = nothing
        catch e
            @debug "Error while closing SSE client: $e"
        end
    end
    
    while isready(transport.buffer)
        try take!(transport.buffer) catch end
    end
end

# WebSocket Transport
mutable struct WebSocketTransport <: TransportLayer
    url::String
    ws::Union{WebSocket, Nothing}
    buffer::Channel{String}
    task::Union{Task, Nothing}
end

function WebSocketTransport(url::String)
    WebSocketTransport(url, nothing, Channel{String}(100), nothing)
end

function start_websocket_client(transport::WebSocketTransport)
    transport.task = @async begin
        try
            open(transport.url) do ws
                transport.ws = ws
                while !eof(ws)
                    data = String(WebSockets.receive(ws))
                    put!(transport.buffer, data)
                end
            end
        catch e
            @error "WebSocket connection error" exception=e
        end
    end
end

function read_message(transport::WebSocketTransport)
    if transport.ws === nothing
        start_websocket_client(transport)
    end
    
    if isready(transport.buffer)
        return take!(transport.buffer)
    end
    
    return nothing
end

function write_message(transport::WebSocketTransport, message::String)
    WebSockets.send(transport.ws, message)
end

function close_transport(transport::WebSocketTransport)
    if transport.task !== nothing && !istaskdone(transport.task)
        try schedule(transport.task, InterruptException(); error=true) catch end
    end
    if transport.ws !== nothing
        try close(transport.ws) catch end
    end
end



# Transport factory function
function create_transport(url::String, transport_type::Symbol; 
    args::Vector{String}=String[], 
    env::Union{Dict{String,String}, Nothing}=nothing,
    setup_command::Union{String, Cmd, Nothing}=nothing)
    if transport_type == :websocket
        return WebSocketTransport(url)
    elseif transport_type == :sse
        return SSETransport(url)
    elseif transport_type == :stdio
        return StdioTransport(url, args; env=env, setup_command=setup_command)
    else
        error("Unsupported transport type: $transport_type. Use :websocket, :sse, or :stdio")
    end
end
