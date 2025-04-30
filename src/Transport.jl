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
            open(pipeline(cmd, stderr=stdout), "r+") :
            open(pipeline(setenv(cmd, env), stderr=stdout), "r+")
    catch e
        @warn "The run command failed, and we cannot run the setup_command as it wasn't provided, so we give up"
        if setup_command !== nothing
            @info "Initial process failed, we fallback to run the setup command"
            install_cmd = setup_command isa Cmd ? setup_command : `sh -c $setup_command`
            run(install_cmd)
            # Retry process creation after setup
            process = env === nothing ?
                open(pipeline(cmd, stderr=stdout), "r+") :
                open(pipeline(setenv(cmd, env), stderr=stdout), "r+")
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
end

function SSETransport(url::String)
    SSETransport(url, nothing, Channel{String}(100), nothing, nothing)
end

function start_sse_client(transport::SSETransport)
    transport.task = @async begin
        try
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
                        if startswith(line, "event:")
                            current_event = strip(line[7:end])
                        elseif startswith(line, "data:")
                            current_data = strip(line[6:end])
                        elseif line == "" && !isempty(current_data)  # Allow empty event
                            # Process complete event
                            if current_event == "endpoint"
                                # The endpoint event contains the session_id
                                if occursin("session_id=", current_data)
                                    transport.session_id = match(r"session_id=([^&]+)", current_data).captures[1]
                                    @info "SSE session established with ID: $(transport.session_id)"
                                end
                            elseif current_event == "message"
                                # Regular message event
                                put!(transport.buffer, current_data)
                            end
                            
                            # Reset for next event
                            current_event = ""
                            current_data = ""
                        end
                    end
                    
                    # Reset buffer for next chunk
                    seekstart(buffer)
                    truncate(buffer, 0)
                    sleep(0.01)
                end
            end
        catch e
            @error "SSE connection error" exception=e
            # Try to reconnect if no session was established
            if transport.session_id === nothing
                sleep(2)
                @info "Attempting to reconnect SSE client"
                start_sse_client(transport)
            end
        end
    end
end

function read_message(transport::SSETransport)
    if transport.client === nothing
        start_sse_client(transport)
        
        # Wait a short time for the session to be established
        if transport.session_id === nothing
            for _ in 1:10  # Wait up to 5 seconds
                sleep(0.1)
                transport.session_id !== nothing && break
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
    # The server expects messages at the /messages/ endpoint with session_id parameter
    if transport.session_id === nothing
        @error "Cannot send message: No session_id available"
        # Print a nicely formatted stacktrace
        println(stderr, "Stacktrace:")
        Base.show_backtrace(stderr, stacktrace())
        return
    end
    
    message_url = replace(transport.url, "/sse" => "/messages/") 
    # Add session_id as query parameter
    if !occursin("?", message_url)
        message_url = message_url * "?session_id=" * transport.session_id
    else
        message_url = message_url * "&session_id=" * transport.session_id
    end
    
    try
        HTTP.post(message_url, 
                ["Content-Type" => "application/json"], 
                message)
    catch ew
        @error "Error sending message to SSE server" exception=e url=message_url
    end
end

function close_transport(transport::SSETransport)
    if transport.task !== nothing && !istaskdone(transport.task)
        try schedule(transport.task, InterruptException(); error=true) catch end
    end
    if transport.client !== nothing
        try close(transport.client) catch end
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