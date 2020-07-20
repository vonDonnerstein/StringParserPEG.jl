using Test
using StringParserPEG

include("../examples/calc1.jl")
@test transformed == 9

include("../examples/calc2.jl")
@test ast == 9

@test parse(Grammar("""start => '<<' & *(char) & '>>'; char  => r(.)r"""),"<<abc>>")[3] != nothing

@test parse(Grammar("""start => '<<' & *(char) & '>>'; char  => !('>>') & r(.)r"""),"<<abc>>")[3] == nothing

@test length(parse(Grammar("start => +(r([\\s\\S])r)"),"大家好!")[1].children) == 4

@test StringParserPEG.grammargrammar == Grammar(StringParserPEG.grammargrammar_string)

@test length(parse(Grammar("start => *(r(.*)r)"),"...")[1].children) == 1
@test length(parse(Grammar("start => *(*('.'))"),"...")[1].children) == 1
