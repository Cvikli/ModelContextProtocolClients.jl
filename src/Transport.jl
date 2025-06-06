using HTTP
using JSON
using WebSockets

export TransportLayer, StdioTransport, SSETransport, WebSocketTransport
export read_message, write_message, close_transport

abstract type TransportLayer end

# Stdio Transport
mutable struct StdioTransport{T} <: TransportLayer
    process::Union{Base.Process, Nothing}
    command::Union{Cmd, Nothing}
    setup_command::Union{String, Cmd, Nothing}
    env::T  # env is a Dict{String,Any?}
end

function StdioTransport(command::Union{Cmd, String}, args::Vector{String}, env::T, setup_command::Union{String, Cmd, Nothing}=nothing) where T
    return StdioTransport{T}(nothing, command isa Cmd ? command : `$command $args`, setup_command, env)
end

function open_transport(transport::StdioTransport)
    transport.process = transport.env === nothing ?
        Base.open(pipeline(transport.command, stderr=stdout), "r+") :
        Base.open(pipeline(setenv(transport.command, merge(Dict("PATH" => ENV["PATH"]), transport.env)), stderr=stdout), "r+")
    return transport
end

is_connected(transport::StdioTransport) = !process_running(transport.process)
function read_message(transport::StdioTransport)
    return process_running(transport.process) && !eof(transport.process) ? readline(transport.process) : nothing
end

function check_process_exited(transport::StdioTransport)
    sleep(0.4)
    if process_exited(transport.process)
        @error "Process failed to start. Check for missing modules or bad command."
        if transport.setup_command !== nothing
            @info "Initial process failed, we fallback to run the setup command"
            install_cmd = transport.setup_command isa Cmd ? transport.setup_command : `$transport.setup_command`
            run(install_cmd)
            # Retry process creation after setup
            env = transport.env
            process = env === nothing ?
                Base.open(pipeline(transport.command, stderr=stdout), "r+") :
                Base.open(pipeline(setenv(transport.command, env), stderr=stdout), "r+")
        else
            @info "We couldn't start the process and the fallback method to the setup_command isn't availabel as the setup_command wasn't provided, so we give up"
            throw(ErrorException("Failed to start process"))
        end
    else
        @info "Process is running" process=transport.process
    end
end
function write_message(transport::StdioTransport, message::String)
    write(transport.process, message * "\n")
    flush(transport.process)
end

function close_transport(transport::StdioTransport)
    try kill(transport.process) catch e; @warn "Error while killing process: $e"; end
end

function process_running(process::Base.Process)
    try
        process !== nothing && process_exited(process) && return false
        return true
    catch
        return false
    end
end

# SSE Transport
mutable struct SSETransport{T} <: TransportLayer
    url::String
    client::Union{HTTP.Streams.Stream, Nothing}
    buffer::Channel{String}
    task::Union{Task, Nothing}
    session_id::Union{String, Nothing}
    message_endpoint::Union{String, Nothing}  # Store the message endpoint URL
    resolved_endpoint::Union{String, Nothing} # Store the fully resolved endpoint URL
    env::T
end

function SSETransport(url::String, env::T) where T
    return SSETransport{T}(url, nothing, Channel{String}(100), nothing, nothing, nothing, nothing, env)
end

function open_transport(transport::SSETransport)
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
                    elseif startswith(line, "Internal Server Error")
                        @error "$line"
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
                                # Resolve the endpoint URL once
                                resolve_message_endpoint(transport)
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
    return transport
end
is_connected(transport::SSETransport)       = transport.session_id !== nothing
check_process_exited(transport::SSETransport) = transport.client !== nothing

# Helper to resolve the message endpoint URL (only called once when endpoint is established)
function resolve_message_endpoint(transport::SSETransport)
    if transport.message_endpoint !== nothing
        if startswith(transport.message_endpoint, "/")
            base_url = replace(transport.url, r"/sse/?.*$" => "")
            transport.resolved_endpoint = base_url * transport.message_endpoint
        else
            transport.resolved_endpoint = transport.message_endpoint
        end
    else
        base_url = replace(transport.url, r"/sse/?$" => "")
        transport.resolved_endpoint = joinpath(base_url, "messages/") * "?sessionId=" * transport.session_id
    end
    @info "Resolved message endpoint: $(transport.resolved_endpoint)"
end


# Simple helper function to wait for a condition with timeout
function wait_for_condition(condition::Function, timeout_seconds::Float64=5.0; message::String="")
    start_time = time()
    
    while (time() - start_time < timeout_seconds)
        condition() && return true
        sleep(0.1)
    end
    
    !isempty(message) && @warn message
    return false
end

function read_message(transport::SSETransport)
    if !is_connected(transport)
        open_transport(transport)
        if wait_for_condition(() -> is_connected(transport), 3.0, message="Failed to establish SSE session within timeout")
            @info "SSE session established"
        end
    end
    
    isready(transport.buffer) && return take!(transport.buffer)
    return nothing
end

function write_message(transport::SSETransport, message::String)
    # println("CLIENT: $message")
    if !is_connected(transport)
        open_transport(transport)
        if wait_for_condition(() -> is_connected(transport), 5.0, message="Failed to re-establish SSE session")
            @info "SSE session re-established"
        end
    end
    
    # @info "Sending message to: $transport.resolved_endpoint"
    response = HTTP.post(transport.resolved_endpoint, ["Content-Type" => "application/json"], message)
    @debug "POST response: $(String(response.body)) ($(response.status))"
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
mutable struct WebSocketTransport{T} <: TransportLayer
    url::String
    ws::Union{WebSocket, Nothing}
    buffer::Channel{String}
    task::Union{Task, Nothing}
    env::T
end

function WebSocketTransport(url::String, env::T) where T
    return WebSocketTransport{T}(url, nothing, Channel{String}(100), nothing, env)
end

function open_transport(transport::WebSocketTransport)
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
    return transport
end

is_connected(transport::WebSocketTransport) = transport.ws !== nothing
check_process_exited(transport::WebSocketTransport) = transport.ws !== nothing


function read_message(transport::WebSocketTransport)
    is_connected(transport) || open_transport(transport)

    isready(transport.buffer) && return take!(transport.buffer)
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
function create_transport(url::Union{String, Cmd}, transport_type::Symbol; 
    args::Vector{String}=String[], 
    env::Union{Dict{String,T}, Nothing}=nothing,
    setup_command::Union{String, Cmd, Nothing}=nothing) where T
    if transport_type == :websocket
        return open_transport(WebSocketTransport(url, env))
    elseif transport_type == :sse
        return open_transport(SSETransport(url, env))
    elseif transport_type == :stdio
        return open_transport(StdioTransport(url, args, env, setup_command))
    end
    
    return error("Unsupported transport type: $transport_type. Use :websocket, :sse, or :stdio")
end

transport_type(transport::WebSocketTransport) = :websocket
transport_type(transport::SSETransport) = :sse
transport_type(transport::StdioTransport) = :stdio
