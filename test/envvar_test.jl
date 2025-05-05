
# command = `TAVILY_API_KEY=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 npx -y tavily-mcp@0.1.4 --help`
command = `npx -y tavily-mcp@0.1.4`

# Create a minimal environment with only essential variables
essential_vars = ["PATH"]
minimal_env = Dict{String,String}()

# Copy only the essential variables that exist in the current environment
for var in essential_vars
    if haskey(ENV, var)
        minimal_env[var] = ENV[var]
    end
end

# Add your API key
minimal_env["TAVILY_API_KEY"] = "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"

# Use the minimal environment
process = Base.open(pipeline(setenv(command, minimal_env), stderr=stdout), "r+")
# process = Base.open(pipeline(command, stderr=stdout), "r+")








