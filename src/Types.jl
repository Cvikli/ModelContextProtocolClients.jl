# MCP Schema Types

# Roles for content and annotations
@enum Role user assistant

# Annotations for content
@kwdef struct Annotations
	audience::Union{Vector{Symbol}, Nothing} = nothing  # TODO: Role type!
	priority::Union{Float64, Nothing} = nothing
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
@kwdef struct ToolAnnotations
	title::Union{String, Nothing} = nothing
	readOnlyHint::Union{Bool, Nothing} = nothing
	destructiveHint::Union{Bool, Nothing} = nothing  
	idempotentHint::Union{Bool, Nothing} = nothing
	openWorldHint::Union{Bool, Nothing} = nothing
end
ToolAnnotations(annotations_data::Dict{String, Any}) = ToolAnnotations(
    title = get(annotations_data, "title", nothing),
    readOnlyHint = get(annotations_data, "readOnlyHint", nothing),
    destructiveHint = get(annotations_data, "destructiveHint", nothing),
    idempotentHint = get(annotations_data, "idempotentHint", nothing),
    openWorldHint = get(annotations_data, "openWorldHint", nothing)
)

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

