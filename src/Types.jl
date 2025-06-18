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
	schema::Union{String, Nothing}
	additionalProperties::Union{Bool, Nothing}
	
end
# Constructor that enforces type = "object"
InputSchema(properties::Dict{String, Any}, required::Vector{String}) = InputSchema("object", properties, required, nothing, nothing)
InputSchema(type::String, properties::Dict{String, Any}, required::Vector{String}) = begin
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


# Constructor to parse result data from MCP responses
function CallToolResult(result_data::Dict{String, Any})
	content = Content[]
	
	# Handle nested result structure
	actual_result = if haskey(result_data, "result")
		result_data["result"]
	else
		result_data
	end
	
	# Parse content array if present
	if haskey(actual_result, "content") && isa(actual_result["content"], Vector)
		for item in actual_result["content"]
			if isa(item, Dict) && haskey(item, "type")
				if item["type"] == "text"
					push!(content, TextContent(
						text = get(item, "text", ""),
						annotations = get(item, "annotations", nothing)
					))
				elseif item["type"] == "image"
					push!(content, ImageContent(
						data = get(item, "data", ""),
						mimeType = get(item, "mimeType", ""),
						annotations = get(item, "annotations", nothing)
					))
				elseif item["type"] == "audio"
					push!(content, AudioContent(
						data = get(item, "data", ""),
						mimeType = get(item, "mimeType", ""),
						annotations = get(item, "annotations", nothing)
					))
				end
			end
		end
	elseif isa(actual_result, String)
		# Handle string result as text content
		push!(content, TextContent(text = actual_result))
	elseif isa(actual_result, Vector) && !isempty(actual_result) && isa(first(actual_result), String) && startswith(first(actual_result), "TextContent")
		# Handle the specific case where result is a string representation of TextContent
		text_content = join(actual_result, "\n")
		# Extract the actual text from the TextContent string representation
		if occursin("text='", text_content)
			text_match = match(r"text='([^']*)'", text_content)
			if text_match !== nothing
				push!(content, TextContent(text = text_match.captures[1]))
			else
				push!(content, TextContent(text = text_content))
			end
		else
			push!(content, TextContent(text = text_content))
		end
	else
		# Fallback: convert to string
		push!(content, TextContent(text = string(actual_result)))
	end
	
	CallToolResult(
		content = content,
		isError = get(result_data, "isError", nothing),
		_meta = get(result_data, "_meta", nothing)
	)
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

