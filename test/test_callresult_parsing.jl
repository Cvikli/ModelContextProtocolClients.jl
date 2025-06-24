using Test
using ModelContextProtocolClients
using ModelContextProtocolClients: validate_content

@testset "CallToolResult Parsing Tests" begin
    @testset "Screenshot Result Parsing" begin
        # Example result from puppeteer screenshot
        result_data = Dict{String, Any}(
            "result" => "[TextContent(type='text', text=\"Screenshot 'test_screenshot' taken at 100x100\", annotations=None), ImageContent(type='image', data='iVBORw0KGgoAAAANSUhEUgAAAGQAAABkCAIAAAD/gAIDAAABLGlDQ1BTa2lhAAAokX2QvUrDABSFv5SCWFQUHRwcMrapTX9sIxTBhKToJK1CUqc0/UFs05BG9AEcfQg3Z0Fc9AEcBcHJQd9AHFwjSZAUJJ7p49wD994DmXWArARjx/daTUU0zI44946AQCTLnrqkS4Dv1zj7Uvgnl6b5Xn9qA5+A7xlmB4QesDaM+SLkbsxXIZ/7rg/CdcjeYUsF4Q7ID2e4O8O264X5N6AxHp3Zyd0s9J2jNmAAGzSZMGHIiD5F2pxygkWREjpb6GgoyEjU2aWKwjYydUpUqKJRRkOnTAUVhVo0U1GRwz7jlZcm7KwEQfCYePsFuF2C3H3i5Q9g+QOeHhIv6di1PCuyskBmMICvG1g0YfUZcse/xab8Kv75VWQPB5tNRMpIlKj9AGcITPQLJ23dAAAJCUlEQvr4nO2df0xTSR7Av6Wv8mhAHkpCSzChwMXtxUt4CVHKlkQK/thiclzjagRMPMv+IerdRq3J8fMuhd0oYGJglZWT7Ab1VhdZk7U9iVDWRMQNe4sYTDXZpAhCMQJ9WpSHFLg/+mhLabsdC/LD+fzVzsybzvt0Zt73Tdspj2FezczMAAAA8Pl8gUBAEERQUBCsOmZmZqampmw229u3b+2nzOPxACA19WM/ayAcpkiSXLNmzWK2donh8XgEQRAEERwcPD4+Pjk56Th3P+F6kFAoXN2mXOHxeO92vkH2PkUQxOI0bPkSEhLC5/ORDgni8/kfTp9ygyRJpJEYJBAIFrM9yxqCIJA6V9AHOABd8Xj6NE1HR0fPTw9alVGC/8w/falUqlAo9u3bJxaL3Qu/x4atAJKSkpRKpf3x3r17N27c6JqLZTnZvHmzXC53POXz+du2bZNIJI4ULItDKpWmpqa6zffBwcEqlWr9+vX2px/07O5KdHT0gwcPPGYlJia2trYCAG9qCi3kX2VMTExs3pzkZ2E8DBHAshDAshDAshDAV0N3BAJBVFTU9PT04OCgWxaWNYeUlJTk5GT7Cur4+Hh7e3t3d7cjFw9DJ3K5XCaT2U3ZF7wyMjI2bdrkKIBlcQiFwi1btsxPd03EsjhEIpHHdIqiwsPD7Y+xLA4fq4COLCwLASwLASwLASwLASwLASwLASwLASwLASyL49WrV96yrFar/QGWxfH8+fOBgYH56T09PZOTk/bHWJaT27dvWywW15T+/n6DweB4ij/dmfPpDkEQNE2LxeLp6em+vr6HDx+6FsaLf3Ow2WydnZ3ecvEwRADLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQgDLQuA9fcjKDhm7HptZf4oSEbGJtCR08duEznuSZb51Ypdaz/hTlKC1d+4VJJOL3yhk8DBEAMtCYEm+GCJRHslODPOSGSqRxSzHMbhEsiLpfZqy7JjFfyEbywybzUMMwwIVKRLHiKnA3oVl/JUjG9NWeaT8R5P9GkomqLRnj8so1xKs8dKJk3VdFhsAALnpYEWVmg4FYE1NpUe+aDR09bpffsmPlPnFlYW7pdQ7nfcylkVQsqy0iPOXm54BAMD9XzV/kN0sSnHoYnsunzz+lX7YXliaX6ykuYCD7f3FgykAYB/rz+To/3v739+fVUvRo5NlPcGTH+WcPqWe3d6E7ajQnLs/G36wxivaYs4UAP15jTZjdp8dgpLGuu+544rxm7xP/2lgbMjtWYqeNdz1n4oio8cJnvqjKi+bdo41UrJbe/ruvU/PGwEAxu6Vl1785PpxOpQ1fVde0mjmCsnLqjUK58giIkR/omm5lE5OkUpEIlEEOWzsaDP80GgwzQoy/lBv+FyhQpw339N3Sk3fZCb5E5RGKht+1mXHzk0cMmgy089wW59EKKtaG3YZj+7IudILAACUoqL5+rEkykNtc2Hul+/OLGrjGiE91nyvIoNadTuGiBSFVYU0dyGz6EvV+9UnOFMQofxXZb4fpgCASso+mBEx+2zo8TOL7/LzWcYTvAvU1hPVxR0ZhQYWAMa69He5dHFWxek82nc8wDwzmnrNjA3IUBJCKQC7o3HLMMMC8FCasRSyQlMKvtYqPP4kmRDTXn6qLDtSqW1L17S4dIfYnNOncqQeVTHGptrycw2GDq937yysjAmeFEnlijTUoDRUmraNJlsMjpOnEtNoD7E+a7pR9tnh8rYhtOoPHTokFAo9Zlmt1gsXLqyQOQsAAJj7VUe1BtduwtzQHK3pcrtosD0XP1PPMSVOVKhyD+fn5Si30lLvk9vVq1dfvHgxP/3p06f19fX2xytE1pCh/O9lHWNuqZa2UnV5i9klhTXd1Tv9haYc0w0++1/r99/WVH996cdWQ3WuBLwwOjqq0+lev37tmtjf33/r1i2bjRuxK0GWzdxUduTML1yvonYWanOlXBbbdeZwcVOvsyzzzORwRWUczM/wFZ26MTIyUltb69jmdWJi4tq1a2NjzrdoBcgyNWpO2oNSAIhRVZ8tKqiqca4O/nbxb4UXTZ6mcZZhGL8WZ+dQV1c3MjIyMDBQU1PjlrUkEby+5M8fn/N+wScTsivOHrbH8exvV0oKL5u4HMnBU5XZCSSA4nhVUcdshGn+rrjkE0VdroQEUhQrocBo71zsT+UarbhCk01HIrTOarXqdLo3b97Mz1qSOIs1Pbhn8pHP0NyNm82s1xbNxp8gOVBZkMVNOlTyYe2h6/IvuwAAwHyltPgv8kuqWBBvzVHE6Ll7b7C0VeYkVeagts/jTL/chyHzU1XJpVmrIlXBP5QSZ3+kZHlFzhuj3stfnDcwNiATsqu/LUtD6Ur+s4xljXXVf/nV7FxFyo4ez06YO3RjlQUapSMY6Kotr3/AAoBoa+HNn1sr8hRib8MmUkJnqFVJItSlwFX940yWMfb8OuS8mpGUSCKJnbNeinQjvapl+cGqW3VYTK5fb/S/MM91mzaMbz70noWErzgrOjo6M3NXXd0FbwWEQqFIJEL92wwHVqt1aAhxcQCRsLCw9PT05ubm8fHxwGvzKisuLm7nzp2Tk15XfeRyuccdBZEYHBxsaWnxFgQuCPHx8Ts27Lhx40bgVXkehlFRUUqlMiQkxNthKSkpgZuyd96srKzF/nuW+Ph4tVodeD0eZK1bty43Nzc4ONjbMQKBIDk5OfDXtrN27VqapheqNm9QFLVnzx6SDOgjaXdZcXFx+/fv931MVFSUY+fTBcHjX5EsOBs2bNi+fXsgf53jLothmOnpad/H/G4BVKampha2Qm+8fPkykMa7yxodHa2urnbs6+ORwcHBBbm4OOjr61vA2rzx5MmTO3fuBPLGeJ7gGxoaRkZGfBzW3t7+zi/pxsDAgLc/j1hAjEbjzZs3A6zEsyyLxaLT6RybbM2nu7u7ubmZYfz64qMPHj161NTUFGAlv0tnZ6derw+8Hl+3OwKB4MCBv/oISgEgPDw8kKDU93gPnLCwMJlM1tLSsiDzLL43RADfGyLwf0sLDSDXraJPAAAAAElFTkSuQmCC', mimeType='image/png', annotations=None)]"
        )
        
        result = CallToolResult(result_data)
        
        @test length(result.content) == 2
        @test result.content[1] isa TextContent
        @test result.content[2] isa ImageContent
        
        # Test text content
        text_content = result.content[1]
        @test text_content.text == "Screenshot 'test_screenshot' taken at 100x100"
        
        # Test image content
        image_content = result.content[2]
        @test image_content.mimeType == "image/png"
        @test startswith(image_content.data, "iVBORw0KGgoAAAANSUhEUgAAAGQAAABk")
    end
    
    @testset "Structured Content Array Result" begin
        result_data = Dict{String, Any}(
            "content" => [
                Dict("type" => "text", "text" => "Hello world"),
                Dict("type" => "image", "data" => "base64data", "mimeType" => "image/jpeg")
            ]
        )
        
        result = CallToolResult(result_data)
        
        @test length(result.content) == 2
        @test result.content[1] isa TextContent
        @test result.content[1].text == "Hello world"
        @test result.content[2] isa ImageContent
        @test result.content[2].data == "base64data"
        @test result.content[2].mimeType == "image/jpeg"
    end
    
    @testset "Simple Text Result" begin
        result_data = Dict{String, Any}("result" => "[TextContent(type='text', text=\"Simple text result\", annotations=None),]")
        result = CallToolResult(result_data)
        
        @test length(result.content) == 1
        @test result.content[1] isa TextContent
        @test result.content[1].text == "Simple text result"
    end
    @testset "Multiple Text Result" begin
        result_data = Dict{String, Any}("result" => "[TextContent(type='text', text=\"Simple text result\", annotations=None), TextContent(type='text', text=\"Simple text result 2\", annotations=None)]")
        result = CallToolResult(result_data)
        
        @test length(result.content) == 2
        @test result.content[1] isa TextContent
        @test result.content[1].text == "Simple text result"
        @test result.content[2] isa TextContent
        @test result.content[2].text == "Simple text result 2"
    end
    
    @testset "Content Array Result" begin
        result_data = Dict{String, Any}(
            "content" => [
                Dict("type" => "text", "text" => "Hello world"),
                Dict("type" => "image", "data" => "base64data", "mimeType" => "image/jpeg")
            ]
        )
        
        result = CallToolResult(result_data)
        
        @test length(result.content) == 2
        @test result.content[1] isa TextContent
        @test result.content[1].text == "Hello world"
        @test result.content[2] isa ImageContent
        @test result.content[2].data == "base64data"
        @test result.content[2].mimeType == "image/jpeg"
    end    
    @testset "Content Validation" begin
        # Test TextContent validation
        text_content = TextContent(text = "Valid text")
        @test validate_content(text_content) == true
        
        # Test ImageContent validation
        image_content = ImageContent(data = "validdata", mimeType = "image/png")
        @test validate_content(image_content) == true
        
        # Test validation failures
        @test_throws ArgumentError validate_content(TextContent(text = ""))
        @test_throws ArgumentError validate_content(ImageContent(data = "", mimeType = "image/png"))
        @test_throws ArgumentError validate_content(ImageContent(data = "data", mimeType = ""))
    end
end