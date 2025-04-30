
using HTTP
using JSON
using WebSockets

export TransportLayer, StdioTransport, SSETransport, WebSocketTransport
export read_message, write_message, close_transport

abstract type TransportLayer end

# Stdio Transport (existing implementation)
struct StdioTransport <: TransportLayer
    process::Base.Process
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
end

function SSETransport(url::String)
    SSETransport(url, nothing, Channel{String}(100), nothing)
end

function start_sse_client(transport::SSETransport)
    transport.task = @async begin
        try
            HTTP.open("GET", transport.url) do stream
                transport.client = stream
                while !eof(stream)
                    line = readline(stream)
                    if startswith(line, "")
                        data = line[7:end]
                        put!(transport.buffer, data)
                    end
                end
            end
        catch e
            @error "SSE connection error" exception=e
        end
    end
end

function read_message(transport::SSETransport)
    if transport.client === nothing
        start_sse_client(transport)
    end
    
    if isready(transport.buffer)
        return take!(transport.buffer)
    end
    
    return nothing
end

function write_message(transport::SSETransport, message::String)
    # SSE is unidirectional, so we need to make a separate HTTP request
    HTTP.post(replace(transport.url, "/sse" => "/jsonrpc"), 
              ["Content-Type" => "application/json"], 
              message)
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
    ws::Union{WebSockets.WebSocket, Nothing}
    buffer::Channel{String}
    task::Union{Task, Nothing}
end

function WebSocketTransport(url::String)
    WebSocketTransport(url, nothing, Channel{String}(100), nothing)
end

function start_websocket_client(transport::WebSocketTransport)
    transport.task = @async begin
        try
            WebSockets.open(transport.url) do ws
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
        try WebSockets.close(transport.ws) catch end
    end
end
