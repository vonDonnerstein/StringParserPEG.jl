using Base.Test
using StringParserPEG

include("../examples/calc1.jl")
@test transformed == 9

include("../examples/calc2.jl")
@test ast == 9

@test StringParserPEG.grammargrammar == Grammar(StringParserPEG.grammargrammar_string)
