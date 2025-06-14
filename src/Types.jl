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
function Annotations(annotations_data::Dict{String, Any})
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
function TextContent(content_data::Dict{String, Any})
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

@kwdef struct ImageContent <: Content
	type::String = "image"
	data::String  # Base64-encoded image data
	mimeType::String
	annotations::Union{Annotations, Nothing} = nothing
end

@kwdef struct AudioContent <: Content
	type::String = "audio"
	data::String  # Base64-encoded audio data
	mimeType::String
	annotations::Union{Annotations, Nothing} = nothing
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



# Tool-related types
abstract type AbstractMCPTool end

struct InputSchema
	type::String  # Always "object" for MCP tools
	properties::Union{Dict{String,Any}, Nothing}
	required::Union{Vector{String}, Nothing}
	
	# Constructor that enforces type = "object"
	InputSchema(properties=nothing, required=nothing) = new("object", properties, required)
	InputSchema(type::String, properties, required) = begin
		type != "object" && @warn "InputSchema type should be 'object' for MCP tools, got '$type'"
		new(type, properties, required)
	end
	InputSchema(input_schema_data::Dict{String, Any}) = InputSchema(
		get(input_schema_data, "properties", nothing),
		get(input_schema_data, "required", nothing)
	)
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
function ToolAnnotations(annotations_data::Dict{String, Any})
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
MCPToolSpecification(server_id::String, tool_dict::Dict{String, Any}, env::Union{Dict{String, T}, Nothing}) where T = begin
	name = tool_dict["name"]
	description = get(tool_dict, "description", nothing)
	in_schema = tool_dict["inputSchema"]  # Fixed typo: was "in_shecma"
	input_schema = InputSchema(in_schema["type"], get(in_schema, "properties", nothing), get(in_schema, "required", nothing))
	
	# Parse annotations if present
	annotations = if haskey(tool_dict, "annotations") && tool_dict["annotations"] !== nothing
		ann_dict = tool_dict["annotations"]
		ToolAnnotations(
			title = get(ann_dict, "title", nothing),
			readOnlyHint = get(ann_dict, "readOnlyHint", nothing),
			destructiveHint = get(ann_dict, "destructiveHint", nothing),
			idempotentHint = get(ann_dict, "idempotentHint", nothing),
			openWorldHint = get(ann_dict, "openWorldHint", nothing)
		)
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

