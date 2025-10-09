# MCP Schema Types

# Roles for content and annotations
@enum Role user assistant

# Annotations for content
struct Annotations
	audience::Union{Vector{String}, Nothing}
	priority::Union{Float64, Nothing}
	
	function Annotations(; audience=nothing, priority=nothing)
		# Validate priority if provided
		if priority !== nothing && !(0.0 <= priority <= 1.0)
			@warn "Priority should be between 0.0 and 1.0, got $priority"
			priority = max(0.0, min(1.0, priority))
		end
		new(audience, priority)
	end
end

# Add constructor for Annotations from Dict with validation
function Annotations(annotations_data::Dict{String, T}) where T
	audience = get(annotations_data, "audience", nothing)
	priority = get(annotations_data, "priority", nothing)
	
	# Validate audience if provided
	if audience !== nothing && !isa(audience, Vector{String})
		@warn "Audience should be a Vector{String}, got $(typeof(audience))"
		audience = nothing
	end
	
	return Annotations(; audience, priority)
end

abstract type ResourceContents end
struct TextResourceContents <: ResourceContents
	uri::String
	mimeType::Union{String, Nothing}
	text::String
end
struct BlobResourceContents <: ResourceContents
	uri::String
	mimeType::Union{String, Nothing}
	blob::String  # Base64-encoded
end

# Content types
abstract type Content end

@kwdef struct TextContent <: Content
	type::String = "text"
	text::String
	annotations::Union{Annotations, Nothing} = nothing
end

# Add constructor for TextContent from Dict
function TextContent(content_data::Dict{String, T}) where T
	annotations = if haskey(content_data, "annotations") && content_data["annotations"] !== nothing
		Annotations(content_data["annotations"])
	else
		nothing
	end
	
	return TextContent(
		type = get(content_data, "type", "text"),
		text = content_data["text"],
		annotations = annotations
	)
end

# Helper function to format base64 data for display
function format_data_url(data::AbstractString, mimeType::AbstractString, content_type::AbstractString)::String
    # If it already has the data URL prefix, return as is
    if startswith(data, "data:")
        return data
    end
    
    # If it's raw base64 data, add the proper prefix
    if !isempty(mimeType)
        return "data:$(mimeType);base64,$(data)"
    end
    
    # Fallback based on content type
    fallback_mime = content_type == "image" ? "image/png" : "audio/wav"
    return "data:$(fallback_mime);base64,$(data)"
end

@kwdef struct ImageContent <: Content
	type::String = "image"
	data::String  # Base64-encoded image data
	mimeType::String
	annotations::Union{Annotations, Nothing} = nothing
	
	# Inner constructor to format data URL
	function ImageContent(type, data, mimeType, annotations)
		formatted_data = format_data_url(data, mimeType, "image")
		new(type, formatted_data, mimeType, annotations)
	end
end

@kwdef struct AudioContent <: Content
	type::String = "audio"
	data::String  # Base64-encoded audio data
	mimeType::String
	annotations::Union{Annotations, Nothing} = nothing
	
	# Inner constructor to format data URL
	function AudioContent(type, data, mimeType, annotations)
		formatted_data = format_data_url(data, mimeType, "audio")
		new(type, formatted_data, mimeType, annotations)
	end
end

@kwdef struct EmbeddedResource <: Content
	type::String = "resource"
	resource::Union{TextResourceContents, BlobResourceContents}
	annotations::Union{Annotations, Nothing} = nothing
end

@kwdef struct CallToolResult
	content::Vector{Content} = Content[]
	isError::Union{Bool, Nothing} = nothing
	_meta::Union{Dict{String,Any}, Nothing} = nothing
end

# MCP Parse Error for better error handling
struct MCPParseError <: Exception
    message::String
    data::Any
end

# Base content parsing function with type dispatch - handle both Dict{String,Any} and Dict{String,String}
function parse_content(data::Dict{String, T}) where T
    content_type = get(data, "type", "text")
    
    if content_type == "text"
        return TextContent(data)
    elseif content_type == "image"
        return parse_image_content(data)
    elseif content_type == "audio"
        return parse_audio_content(data)
    elseif content_type == "resource"
        return parse_embedded_resource(data)
    else
        @warn "Unknown content type: $content_type, falling back to text"
        return TextContent(text = string(data))
    end
end

# Specialized parsing functions
function parse_image_content(data::Dict{String, T}) where T
    annotations = get(data, "annotations", nothing)
    if annotations !== nothing
        annotations = Annotations(annotations)
    end
    
    return ImageContent(
        data = get(data, "data", ""),
        mimeType = get(data, "mimeType", ""),
        annotations = annotations
    )
end

function parse_audio_content(data::Dict{String, T}) where T
    annotations = get(data, "annotations", nothing)
    if annotations !== nothing
        annotations = Annotations(annotations)
    end
    
    return AudioContent(
        data = get(data, "data", ""),
        mimeType = get(data, "mimeType", ""),
        annotations = annotations
    )
end

function parse_embedded_resource(data::Dict{String, T}) where T
    resource_data = data["resource"]
    resource = if haskey(resource_data, "text")
        TextResourceContents(
            resource_data["uri"],
            get(resource_data, "mimeType", nothing),
            resource_data["text"]
        )
    else
        BlobResourceContents(
            resource_data["uri"],
            get(resource_data, "mimeType", nothing),
            resource_data["blob"]
        )
    end
    
    annotations = get(data, "annotations", nothing)
    if annotations !== nothing
        annotations = Annotations(annotations)
    end
    
    return EmbeddedResource(resource = resource, annotations = annotations)
end

# Safe content parsing with error handling
function safe_parse_content(data::Any)
    try
        if isa(data, Dict)
            return parse_content(data)
        else
            return TextContent(text = string(data))
        end
    catch e
        @warn "Failed to parse content" exception=e data=data
        return TextContent(text = "Parse error: $(string(data))")
    end
end

# Improved result content parsing with multiple dispatch
function parse_result_content(result::Dict{String, T})::Vector{Content} where T
    if haskey(result, "content") && isa(result["content"], Vector)
        return [safe_parse_content(item) for item in result["content"]]
    else
        # Fallback for unexpected format
        return [TextContent(text = JSON.json(result))]
    end
end

function parse_result_content(result::String)::Vector{Content}
    # Handle complex string format like "[TextContent(...), ImageContent(...)]"
    if startswith(result, "[") && endswith(result, "]")
        # Try to parse as structured content string (fallback for legacy formats)
        parsed_content = parse_content_string_fallback(result)
        return isempty(parsed_content) ? [TextContent(text = result)] : parsed_content
    else
        # Simple string result
        return [TextContent(text = result)]
    end
end

function parse_result_content(result::Vector)::Vector{Content}
    # For vector results, try to parse each element
    contents = Content[]
    for item in result
        if isa(item, Dict)
            push!(contents, safe_parse_content(item))
        elseif isa(item, String)
            push!(contents, TextContent(text = item))
        end
    end
    return contents
end

# Fallback for any other type
function parse_result_content(result::Any)::Vector{Content}
    return [TextContent(text = string(result))]
end

# Legacy string parsing fallback (improved regex patterns)
function parse_content_string_fallback(content_str::String)::Vector{Content}
    contents = Content[]
    
    # Improved pattern matching for TextContent - handle escaped quotes and capture full text
    if occursin("TextContent", content_str)
        # Pattern that properly handles escaped quotes by matching until unescaped quote
        # This uses a negative lookbehind to ensure we don't stop at escaped quotes
        text_pattern = r"TextContent\([^)]*text='((?:[^'\\]|\\.)*)'"
        text_matches = eachmatch(text_pattern, content_str)
        for m in text_matches
            # Unescape the captured text
            text = replace(m.captures[1], "\\'" => "'", "\\\"" => "\"", "\\n" => "\n", "\\r" => "\r", "\\t" => "\t")
            push!(contents, TextContent(; text = text))
        end
        
        # Also try double quotes if single quotes didn't work
        if isempty(text_matches)
            text_pattern_double = r"TextContent\([^)]*text=\"((?:[^\"\\]|\\.)*)\""
            text_matches = eachmatch(text_pattern_double, content_str)
            for m in text_matches
                text = replace(m.captures[1], "\\'" => "'", "\\\"" => "\"", "\\n" => "\n", "\\r" => "\r", "\\t" => "\t")
                push!(contents, TextContent(; text = text))
            end
        end
    end
    
    # Improved pattern matching for ImageContent
    if occursin("ImageContent", content_str)
        # Extract image content with better pattern matching
        data_pattern = r"data='([^']+)'"
        mime_pattern = r"mimeType='([^']+)'"
        
        # Find ImageContent blocks
        image_blocks = eachmatch(r"ImageContent\([^)]+\)", content_str)
        for block in image_blocks
            block_str = block.match
            data_match = match(data_pattern, block_str)
            mime_match = match(mime_pattern, block_str)
            
            if data_match !== nothing && mime_match !== nothing
                push!(contents, ImageContent(
                    data = data_match.captures[1],
                    mimeType = mime_match.captures[1]
                ))
            end
        end
    end
    
    return contents
end

# Improved CallToolResult constructor
function CallToolResult(result_data::Dict{String, T}) where T
    # Check for new result_json format first (preferred)
    if haskey(result_data, "result_json") && result_data["result_json"] !== nothing
        result_json = result_data["result_json"]
        
        # Parse the result_json array directly - initialize content first
        content = Content[]
        
        if isa(result_json, Vector)
            for item in result_json
                if isa(item, Dict)
                    content_type = get(item, "type", "text")
                    
                    if content_type == "text"
                        push!(content, TextContent(item))
                    elseif content_type == "image"
                        push!(content, parse_image_content(item))
                    elseif content_type == "audio"
                        push!(content, parse_audio_content(item))
                    elseif content_type == "resource"
                        push!(content, parse_embedded_resource(item))
                    else
                        @warn "Unknown content type in result_json: $content_type"
                        push!(content, TextContent(text = string(item)))
                    end
                else
                    # Fallback for non-dict items
                    push!(content, TextContent(text = string(item)))
                end
            end
        else
            # Fallback if result_json is not a vector
            content = [TextContent(text = string(result_json))]
        end
        
        return CallToolResult(
            content = content,
            isError = get(result_data, "isError", false),
            _meta = get(result_data, "_meta", nothing)
        )
    end
    
    # Fallback to old parsing logic for backward compatibility
    actual_result = get(result_data, "result", result_data)
    
    # Parse content based on type using multiple dispatch
    content = parse_result_content(actual_result)
    
    return CallToolResult(
        content = content,
        isError = get(result_data, "isError", false),
        _meta = get(result_data, "_meta", nothing)
    )
end

# Validation functions
function validate_content(content::TextContent)
    isempty(content.text) && throw(ArgumentError("TextContent text cannot be empty"))
    return true
end

function validate_content(content::ImageContent)
    isempty(content.data) && throw(ArgumentError("ImageContent data cannot be empty"))
    isempty(content.mimeType) && throw(ArgumentError("ImageContent mimeType cannot be empty"))
    return true
end

function validate_content(content::AudioContent)
    isempty(content.data) && throw(ArgumentError("AudioContent data cannot be empty"))
    isempty(content.mimeType) && throw(ArgumentError("AudioContent mimeType cannot be empty"))
    return true
end

# Dispatch-based result2string for different content types
mcp_result2string(content::TextContent)::String = content.text
mcp_result2string(content::Union{ImageContent, AudioContent, EmbeddedResource})::Union{String, Nothing} = nothing

# CallToolResult formatting - only concatenate non-nothing text results
function mcp_result2string(result::Union{CallToolResult, Nothing})::String
    result === nothing && return "No result"
    
    text_parts = String[]
    
    # Extract only text content using dispatch
    for content in result.content
        text_result = mcp_result2string(content)
        if text_result !== nothing
            push!(text_parts, text_result)
        end
    end
    
    return join(text_parts, "\n")
end


# Extract base64 image data from MCP tool results
function mcp_resultimg2base64(tool::CallToolResult)::Vector{String}
    images = String[]
    tool === nothing && return images
    for content in tool.content
        if isa(content, ImageContent)
            push!(images, content.data)
        end
    end
    return images
end

# Extract base64 audio data from MCP tool results  
function mcp_resultaudio2base64(tool::CallToolResult)::Vector{String}
    audios = String[]
    tool === nothing && return audios
    for content in tool.content
        if isa(content, AudioContent)
            push!(audios, content.data)
        end
    end
    return audios
end

# # Pretty printing for debugging
# function Base.show(io::IO, ::MIME"text/plain", content::TextContent)
#     print(io, "TextContent(")
#     if length(content.text) > 50
#         print(io, "\"", first(content.text, 47), "...\"")
#     else
#         print(io, "\"", content.text, "\"")
#     end
#     content.annotations !== nothing && print(io, ", annotations=", content.annotations)
#     print(io, ")")
# end

# function Base.show(io::IO, ::MIME"text/plain", content::ImageContent)
#     print(io, "ImageContent(mimeType=\"", content.mimeType, "\"")
#     print(io, ", size=", length(content.data), " bytes")
#     content.annotations !== nothing && print(io, ", annotations=", content.annotations)
#     print(io, ")")
# end

# function Base.show(io::IO, ::MIME"text/plain", content::AudioContent)
#     print(io, "AudioContent(mimeType=\"", content.mimeType, "\"")
#     print(io, ", size=", length(content.data), " bytes")
#     content.annotations !== nothing && print(io, ", annotations=", content.annotations)
#     print(io, ")")
# end

# Tool-related types
abstract type AbstractMCPTool end

struct InputSchema
	type::String  # Always "object" for MCP tools
	properties::Union{Dict{String,Any}, Nothing}
	required::Union{Vector{String}, Nothing}
	schema::Union{String, Nothing}
	additionalProperties::Union{Bool, Nothing}
	
end
# Constructor that enforces type = "object"
InputSchema(properties::Dict{String, T}, required::Vector{String}) where T = InputSchema("object", properties, required, nothing, nothing)
InputSchema(type::String, properties::Dict{String, T}, required::Vector{String}) where T = begin
	type != "object" && @warn "InputSchema type should be 'object' for MCP tools, got '$type'"
	InputSchema(type, properties, required, nothing, nothing)
end
InputSchema(data::Dict) = begin
	schema = get(data, "\$schema", nothing)
	type = data["type"]
	properties = get(data, "properties", nothing)
	required = get(data, "required", nothing)
	additionalProperties = get(data, "additionalProperties", nothing)
	
	InputSchema(type, properties, required, schema, additionalProperties)
end

# Tool annotations based on MCP schema
struct ToolAnnotations
	title::Union{String, Nothing}
	readOnlyHint::Union{Bool, Nothing}
	destructiveHint::Union{Bool, Nothing}
	idempotentHint::Union{Bool, Nothing}
	openWorldHint::Union{Bool, Nothing}
	
	function ToolAnnotations(; title=nothing, readOnlyHint=nothing, destructiveHint=nothing, 
						   idempotentHint=nothing, openWorldHint=nothing)
		# Validate hints if provided
		if readOnlyHint !== nothing && destructiveHint !== nothing && readOnlyHint && destructiveHint
			@warn "Tool cannot be both readOnly and destructive"
			destructiveHint = false
		end
		new(title, readOnlyHint, destructiveHint, idempotentHint, openWorldHint)
	end
end

# Enhanced constructor for ToolAnnotations from Dict with validation
function ToolAnnotations(annotations_data::Dict{String, T}) where T
	title = get(annotations_data, "title", nothing)
	readOnlyHint = get(annotations_data, "readOnlyHint", nothing)
	destructiveHint = get(annotations_data, "destructiveHint", nothing)
	idempotentHint = get(annotations_data, "idempotentHint", nothing)
	openWorldHint = get(annotations_data, "openWorldHint", nothing)
	
	return ToolAnnotations(; title, readOnlyHint, destructiveHint, idempotentHint, openWorldHint)
end

struct MCPToolSpecification <: AbstractMCPTool
	server_id::String # TODO WE ACTUALLY don't have this data???

	name::String
	description::Union{String, Nothing}
	input_schema::InputSchema
	annotations::Union{ToolAnnotations, Nothing}
	env::Dict{String, Any}
end

# Constructor for MCPToolSpecification from tool dictionary
MCPToolSpecification(server_id::String, tool_dict::Dict{String, T}, env::Union{Dict{String, T2}, Nothing}) where {T, T2} = begin
	name = tool_dict["name"]
	description = get(tool_dict, "description", nothing)
	input_schema = InputSchema(tool_dict["inputSchema"])
	
	# Parse annotations if present
	annotations = if haskey(tool_dict, "annotations") && tool_dict["annotations"] !== nothing
		ToolAnnotations(tool_dict["annotations"])
	else
		nothing
	end
	final_env = env === nothing ? Dict{String, Any}() : Dict{String, Any}(env)

	MCPToolSpecification(server_id, name, description, input_schema, annotations, final_env)
end

@kwdef struct Resource
	uri::String
	name::String
	description::Union{String, Nothing} = nothing
	mimeType::Union{String, Nothing} = nothing
	annotations::Union{Annotations, Nothing} = nothing
	size::Union{Int, Nothing} = nothing
end

const RequestId = Union{String, Int}  # JSON-RPC Types

@kwdef struct JSONRPCRequest
	jsonrpc::String = "2.0"
	id::RequestId
	method::String
	params::Union{Dict{String,Any}, Nothing} = nothing
end

@kwdef struct JSONRPCResponse
	jsonrpc::String = "2.0"
	id::RequestId
	result::Union{Dict{String,Any}, Nothing} = nothing
end

@kwdef struct JSONRPCError
	jsonrpc::String = "2.0"
	id::RequestId
	error::Dict{String,Any}
end

# Logging and Progress Types
@enum LoggingLevel debug info notice warning error critical alert emergency
const ProgressToken = Union{String, Int}

