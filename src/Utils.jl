"""
    @retry [max_attempts=3] [delay=0.1] [on=Exception] expr

Retry executing `expr` up to `max_attempts` times with optional `delay` between attempts.
Only retries if exception type matches `on` (defaults to any Exception).

# Examples
```julia
# Basic retry with defaults (3 attempts, 0.1s delay)
@retry network_request()

# Custom attempts and delay
@retry max_attempts=5 delay=0.5 risky_operation()

# Only retry on specific exceptions
@retry max_attempts=3 on=NetworkError fetch_data()

# Exponential backoff
@retry max_attempts=4 delay=(attempt) -> 0.1 * 2^(attempt-1) api_call()
```
"""
macro retry(args...)
    # Parse arguments
    max_attempts = 3
    delay = 0.1
    exception_type = :Exception
    expr = nothing
    
    for arg in args
        if isa(arg, Expr) && arg.head == :(=)
            key, val = arg.args
            if key == :max_attempts
                max_attempts = val
            elseif key == :delay
                delay = val
            elseif key == :on
                exception_type = val
            end
        else
            expr = arg
        end
    end
    
    expr === nothing && error("@retry requires an expression to execute")
    
    return quote
        local result = nothing
        local last_exception = nothing
        
        for attempt in 1:$(esc(max_attempts))
            try
                result = $(esc(expr))
                break
            catch e
                last_exception = e
                if !(e isa $(esc(exception_type)))
                    rethrow(e)
                end
                
                if attempt < $(esc(max_attempts))
                    delay_val = $(esc(delay))
                    if isa(delay_val, Function)
                        sleep(delay_val(attempt))
                    else
                        sleep(delay_val)
                    end
                else
                    @error "Failed after $($(esc(max_attempts))) attempts" exception=e
                    rethrow(e)
                end
            end
        end
        result
    end
end
