###########
# Helpers #
###########

unref(value::T) where T = [value]
unref(node::Node, ::Type{T}) where T<:Rule = [node]
unref(node::Node, ::Type{ReferencedRule}) = node.children
unref(node::Node) = unref(node, node.ruleType)

function make_node(rule, value, first, last, children::Array)
  #println("make_node: $(rule.action)($rule, $value, first=$first, last=$last, children=$children)")
  return rule.action(rule, value, first, last, children)
end

###############
# ParserCache #
###############

abstract type ParserCache end

struct StandardCache <: ParserCache
  values::Dict{AbstractString, Node}

  function StandardCache()
    return new(Dict{AbstractString, Any}())
  end
end



###################
# parse (generic) #
###################

"""
    parse(grammar, text; cache::ParserCache=nothing, start=:start)
parses `text` according to `grammar` to yield a tuple consisting of Abstract Syntax Tree, final matched position and error (ast, pos, error) depending on outcome.
`start` specifies the symbol associated to the rule at the top of the AST. Specifying a `cache` different than `nothing` allows to reuse previous work, whenever the same rule is evaluated at the same position again.
"""
function parse(grammar::Grammar, text::AbstractString; cache=nothing, start=:start)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)

  rule = grammar.rules[start]
  (ast, pos, error) = parse(grammar, rule, text, 1, cache)

  if pos < length(text) + 1
    sequence = text[utf8ind[pos]:end]
    if length(sequence) > 15
      sequence = text[utf8ind[pos]:utf8ind[pos+15]]*"..."
    end
    error = Meta.ParseError("Entire string did not match at pos: $pos ($sequence)")
  end

  return (ast, pos, error)
end

"""
    parse(grammar, rule, text, pos, cache)
parses `text` according to `rule` within `grammar` starting with position `pos`. Specifying a `cache` different than `nothing` allows to reuse previous work, whenever the same rule has been matched at the same position before. If no `cache` is specified or no match in `cache` is found `parse` resorts to `parse_newcachekey`, because in an non-existent cache every cachekey is new.
"""
function parse(grammar::Grammar, rule::Rule, text::AbstractString, pos::Int, cache::Nothing)
  return parse_newcachekey(grammar, rule, text, pos, cache)
end

function parse(grammar::Grammar, rule::Rule, text::AbstractString, pos::Int, cache::StandardCache)
  cachekey::AbstractString = "$(object_id(rule))$pos"
  if haskey(cache.values, cachekey)
    # lookup cachekey
    cachedresult = cache.values[cachekey]
    (node, pos, error) = (cachedresult, cachedresult.last, nothing)
  else
    # parse new cachekey
    (node, pos, error) = parse_newcachekey(grammar, rule, text, pos, cache)

    # store new cachekey
    if node !== nothing
      cache.values[cachekey] = node
    end
  end

  return (node, pos, error)
end

function parse(grammar::Grammar, symbol::Symbol, text::AbstractString, pos::Int, cache::Union{StandardCache,Nothing})
  parse(grammar, grammar.rules[symbol], text, pos, cache)
end



##############################################
# parse_newcachekey (specific for each rule) #
##############################################

"""
    parse_newcachekey(grammar, rule, text, pos, cacheforsubnodes)
parses `text` according to `rule` within `grammar` starting with position `pos` without trying to lookup the complete match in the specified `cache`. Matches of children of the current `rule` along the `text` to parse will however be looked-up in `cache`.
"""
function parse_newcachekey(grammar::Grammar, rule::ReferencedRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  refrule = grammar.rules[rule.symbol]

  firstPos = pos
  (childNode, pos, error) = parse(grammar, refrule, text, pos, cache)

  if childNode !== nothing
    node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, [childNode])
    return (node, pos, error)
  else
    return (nothing, pos, error)
  end
end

function parse_newcachekey(grammar::Grammar, rule::OrRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  # Try branches in order (left to right). The first branch to match will be marked
  # as a success. If no branches match, then return an error.
  firstPos = pos
  for branch in rule.values
    (child, pos, error) = parse(grammar, branch, text, pos, cache)

    if error == nothing
      node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, unref(child))
      return (node, pos, error)
    end
  end

  # give error
  return (nothing, pos, Meta.ParseError("No match (OrRule) at pos: $pos"))
end

function parse_newcachekey(grammar::Grammar, rule::AndRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  firstPos = pos;

  # All items in sequence must match, otherwise give an error
  value = Any[]
  for item in rule.values
    (child, pos, error) = parse(grammar, item, text, pos, cache)

    # check for error
    if error !== nothing
      return (nothing, firstPos, error)
    end

    if child !== nothing
      append!(value, unref(child))
    end
  end

  node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, value)
  return (node, pos, nothing)
end

function parse_newcachekey(grammar::Grammar, rule::Terminal, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  local size::Int = length(rule.value)

  if startswith(text[utf8ind[pos]:end],rule.value)
    node = make_node(rule, text[utf8ind[pos]:utf8ind[pos+size-1]], pos, pos+size, [])
    return (node, pos+size, nothing)
  end

  len = min(pos+size-1, length(text))
  return (nothing, pos, Meta.ParseError("'$(text[utf8ind[pos]:utf8ind[len]])' does not match '$(rule.value)'. At pos: $pos"))
end

function parse_newcachekey(grammar::Grammar, rule::OneOrMoreRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  firstPos = pos
  (child, pos, error) = parse(grammar, rule.value, text, pos, cache)

  # make sure there is at least one
  if child === nothing
    return (nothing, pos, Meta.ParseError("No match (OneOrMoreRule) at pos: $pos"))
  end

  # and continue making matches for as long as we can
  children = unref(child)
  while error == nothing
    (child, pos, error) = parse(grammar, rule.value, text, pos, cache)

    if error === nothing && child !== nothing
      children = [children;collect(unref(child))]
    end
  end

  node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, children)
  return (node, pos, nothing)
end

function parse_newcachekey(grammar::Grammar, rule::ZeroOrMoreRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  firstPos::Int = pos
  children::Array = Any[]

  error = nothing
  prepos = -1
  while error == nothing && pos != prepos
    prepos = pos

    (child, pos, error) = parse(grammar, rule.value, text, pos, cache)

    if error === nothing && child !== nothing
      append!(children, unref(child))
    end
  end

  if length(children) > 0
    node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, children)
  else
    node = nothing
  end

  return (node, pos, nothing)
end

function parse_newcachekey(grammar::Grammar, rule::RegexRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  firstPos = pos

  # use regex match
  pattern = Regex("^$(rule.value.pattern)")
  if occursin(pattern, text[utf8ind[firstPos]:end])
    value = match(pattern, text[utf8ind[firstPos]:end])

    if length(value.match) == 0
      # this means that we didn't match, but the regex was optional, so we don't want to give an
      # error
      return (nothing, firstPos, nothing)
    else
      pos += length(value.match)
      node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, [])

      return (node, pos, nothing)
    end
  else
    return (nothing, firstPos, Meta.ParseError("Could not match RegEx at pos: $pos"))
  end
end

function parse_newcachekey(grammar::Grammar, rule::OptionalRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  (child, pos, error) = parse(grammar, rule.value, text, pos, cache)
  firstPos = pos

  if child !== nothing
    node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, unref(child))
    return (node, pos, error)
  end

  # no error, but we also don't move the position or return a valid node
  return (nothing, firstPos, nothing)
end

function parse_newcachekey(grammar::Grammar, rule::ListRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  firstPos = pos

  # number of occurances
  count = 0

  error = nothing
  children = Any[]

  # continue making matches for as long as we can
  while error === nothing
    (child, pos, error) = parse(grammar, rule.entry, text, pos, cache)

    if child !== nothing
      append!(children, unref(child))
      (dchild, pos, error) = parse(grammar, rule.delim, text, pos, cache)
    else
      break
    end

    count += 1
  end

  if count < rule.min
    return (nothing, pos, Meta.ParseError("No match (ListRule) at pos: $pos"))
  end

  node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, children)
  return (node, pos, nothing)
end

function parse_newcachekey(grammar::Grammar, rule::SuppressRule, text::AbstractString, pos::Int, cache)
  # use rule contained in the SuppressRule to parse, but don't return anything
  (_, pos, error) = parse_newcachekey(grammar, rule.value, text, pos, cache)
  return (nothing, pos, error)
end

function parse_newcachekey(grammar::Grammar, rule::LookAheadRule, text::AbstractString, pos::Int, cache)
    (_, newPos, error) = parse_newcachekey(grammar, rule.value, text, pos, cache)
    if error !== nothing
        return (nothing, newPos, error)
    else
        return (nothing, pos, nothing)
    end
end

function parse_newcachekey(grammar::Grammar, rule::NotRule, text::AbstractString, pos::Int, cache)
  # try to parse rule
  (child, newpos, error) = parse(grammar, rule.entry, text, pos, cache)

  # if we match, it's an error
  if error == nothing
    error = Meta.ParseError("No match (NotRule) at pos: $pos")
  else
    # otherwise, return a success
    error = nothing
  end

  return (nothing, pos, error)
end

function parse_newcachekey(grammar::Grammar, rule::EmptyRule, text::AbstractString, pos::Int, cache)
  # need to explicitely call rule's action because nothing is consumed
  if rule.action != nothing
    rule.action(rule, "", pos, pos, [])
  end

  return (nothing, pos, nothing)
end

function parse_newcachekey(grammar::Grammar, rule::EndOfFileRule, text::AbstractString, pos::Int, cache)
  # need to explicitely call rule's action because nothing is consumed
  if pos == length(text)
    #rule.action(rule, value, first, last, children)
    rule.action(rule, "", length(text), length(text), [])
  end

  return (nothing, pos, nothing)
end

function parse_newcachekey(grammar::Grammar, rule::IntegerRule, text::AbstractString, pos::Int, cache)
  utf8ind = collect(eachindex(text)); push!(utf8ind,ncodeunits(text)+1)
  #rexpr = r"^[-+]?[0-9]+([eE][-+]?[0-9]+)?"
  # Julia treats anything with 'e' to be a float, so for now follow suit
  rexpr = r"^[-+]?[0-9]+"
  firstPos = pos

  # use regex match
  if occursin(rexpr, text[utf8ind[firstPos]:end])
    value = match(rexpr, text[utf8ind[firstPos]:end])

    if length(value.match) != 0
      pos += length(value.match)
      node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, [])

      return (node, pos, nothing)
    end
  else
    return (nothing, firstPos, Meta.ParseError("Could not match IntegerRule at pos: $pos"))
  end
end

function parse_newcachekey(grammar::Grammar, rule::FloatRule, text::AbstractString, pos::Int, cache)
  rexpr = r"^[-+]?[0-9]*\.[0-9]+([eE][-+]?[0-9]+)?"
  firstPos = pos

  # use regex match
  if occursin(rexpr, text[utf8ind[firstPos]:end])
    value = match(rexpr, text[utf8ind[firstPos]:end])

    if length(value.match) != 0
      pos += length(value.match)
      node = make_node(rule, text[utf8ind[firstPos]:utf8ind[pos-1]], firstPos, pos, [])

      return (node, pos, nothing)
    end
  else
    return (nothing, firstPos, Meta.ParseError("Could not match FloatRule at pos: $pos"))
  end
end
