using Test
using StringParserPEG

include("../examples/calc1.jl")
@test transformed == 9

include("../examples/calc2.jl")
@test ast == 9

@test parse(Grammar("""start => '<<' & *(char) & '>>'; char  => r(.)r"""),"<<abc>>")[3] != nothing

@test parse(Grammar("""start => '<<' & *(char) & '>>'; char  => !('>>') & r(.)r"""),"<<abc>>")[3] == nothing

@test StringParserPEG.grammargrammar == Grammar(StringParserPEG.grammargrammar_string)
