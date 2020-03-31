struct MatchRule{T} end

# default transform is to do nothing
transform(fn::Function, value) = value
transform(fn::Function, vector::Vector) = [transform(fn,n) for n in nodes]

fndefault(node,children,label) = Node(node.name,node.value,node.first,node.last,children,node.ruleType)

function transform(fn::Function, node::Node)
  transformedchildren = [transform(fn, child) for child in node.children]

  if hasmethod(fn, (Node, Any, MatchRule{Symbol(node.name)}))
    label = MatchRule{Symbol(node.name)}()
  elseif hasmethod(fn, (Node, Any, MatchRule{:default}))
    label = MatchRule{:default}()
  else
    return fndefault(node,transformedchildren,nothing)
  end

  return fn(node, transformedchildren, label)
end
