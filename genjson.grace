import "mgcollections" as collections
import "util" as util
import "io" as io

method wrap(v) {
    match(v)
        case { _ : String -> JSString.new(v) }
        case { _ -> v }
}
class JSObj.new {
    def data = collections.map.new
    method put(key, val) {
        data.put(key, wrap(val))
    }
    method asJSON {
        var ret := "\{"
        var comma := ""
        for (data) do {k->
            ret := ret ++ comma ++ "\"{k}\": " ++ data.get(k).asJSON
            comma := ","
        }
        return ret ++ "}"
    }
}

class JSArray.new {
    def data = collections.list.new
    method push(val) {
        data.push(wrap(val))
    }
    method asJSON {
        var ret := "["
        var comma := ""
        for (data) do {v->
            ret := ret ++ comma ++ v.asJSON
            comma := ","
        }
        return ret ++ "]"
    }
}

class JSString.new(s) {
    def data = s
    method asJSON {
        return "\"{data}\""
    }
}

method generateNode(n) {
    def ret = JSObj.new
    match (n.kind)
        case { "vardec" ->
            ret.put("type", "vardec")
            ret.put("name", n.name.value)
            ret.put("value", generateNode(n.value))
        } case { "string" ->
            ret.put("type", "string")
            ret.put("value", n.value)
        } case { "num" ->
            ret.put("type", "number")
            ret.put("value", n.value)
        } case { "op" ->
            ret.put("type", "operator")
            ret.put("left", generateNode(n.left))
            ret.put("right", generateNode(n.right))
            ret.put("operator", n.value)
        } case { "bind" ->
            if (n.dest.kind == "member") then {
                if (n.dest.in.value == "prelude") then {
                    ret.put("type", "dialect-method")
                    ret.put("name", n.dest.value ++ ":=")
                    def parts = JSArray.new
                    ret.put("parts", parts)
                    def part = JSArray.new
                    parts.push(part);
                    part.push(generateNode(n.value))
                } else {
                    ret.put("type", "unknown assign")
                }
            } else {
                ret.put("type", "assign")
                ret.put("left", generateNode(n.dest))
                ret.put("right", generateNode(n.value))
            }
        } case { "method" ->
            ret.put("type", "method")
            ret.put("name", n.value.value)
            ret.put("arg", n.signature.at(1).params.at(1).value)
            def body = JSArray.new
            for (n.body) do {v->
                body.push(generateNode(v))
            }
            ret.put("body", body)
        } case { "if" ->
            def body = JSArray.new
            for (n.thenblock) do {v->
                body.push(generateNode(v))
            }
            if (n.elseblock.size > 0) then {
                ret.put("type", "if-else")
                ret.put("condition", generateNode(n.value))
                ret.put("body", body)
                def elseBody = JSArray.new
                for (n.elseblock) do {v->
                    elseBody.push(generateNode(v))
                }
                ret.put("elseBody", elseBody)
            } else {
                ret.put("type", "if")
                ret.put("condition", generateNode(n.value))
                ret.put("body", body)
            }
        } case { "identifier" ->
            ret.put("type", "var")
            ret.put("value", n.value)
        } case { "call" ->
            if (n.value.kind == "member") then {
                if (n.value.in.value == "prelude") then {
                    ret.put("name", n.value.value)
                    ret.put("type", "dialect-method")
                    def parts = JSArray.new
                    ret.put("parts", parts)
                    for (n.with) do {part->
                        def thisPart = JSArray.new
                        parts.push(thisPart)
                        for (part.args) do {arg->
                            thisPart.push(generateNode(arg))
                        }
                    }
                } else {
                    if (n.value.in.value == "self") then {
                        def arg = generateNode(n.with.at(1).args.at(1))
                        ret.put("type", "selfcall")
                        ret.put("argument", arg)
                        ret.put("name", n.value.value)
                    } else {
                        ret.put("type", "request")
                        ret.put("receiver", generateNode(n.value.in))
                        ret.put("name", n.value.value)
                    }
                }
            } else {
                ret.put("type", "unknown call")
                print "    {n.pretty(4)}"
            }
        } case { "block" ->
            ret.put("type", "block")
            def params = JSArray.new
            ret.put("params", params)
            for (n.params) do {p->
                params.push(p.value)
            }
            def body = JSArray.new
            ret.put("body", body)
            for (n.body) do {p->
                body.push(generateNode(p))
            }
        } case { _ ->
            ret.put("type", "UNKNOWN")
            ret.put("internalKind", n.kind)
        }
    return ret
}

var lastToken := object {def kind is readable = ""}
method saveToken(token) {
    lastToken := token
}

method generate(values, outfile) {
    util.log_verbose "generating JSON."
    def chunkLocations = collections.list.new
    if (lastToken.kind == "comment") then {
        def cmt = lastToken.value
        if (cmt.substringFrom(1)to(9) == " chunks: ") then {
            var accum := "";
            var leftAccum := ""
            for (cmt.substringFrom(10)to(cmt.size)) do {c->
                if (c == " ") then {
                    chunkLocations.push(object {
                        def top is readable = accum
                        def left is readable = leftAccum
                    })
                    accum := ""
                } else {
                    if (c == ",") then {
                        leftAccum := accum
                        accum := ""
                    } else {
                        accum := accum ++ c
                    }
                }
            }
            chunkLocations.push(object {
                def top is readable = accum
                def left is readable = leftAccum
            })
            accum := ""
        }
    }
    if (chunkLocations.size == 0) then {
        chunkLocations.push(object {
            def top is readable = "10px"
            def left is readable = "10px"
        })
    }
    def overall = JSObj.new
    def arr = JSArray.new
    overall.put("chunks", arr)
    var chunkIndex := 1
    var chunk := JSObj.new
    arr.push(chunk)
    chunk.put("type", "chunk")
    chunk.put("x", chunkLocations.at(chunkIndex).left)
    chunk.put("y", chunkLocations.at(chunkIndex).top)
    var body := JSArray.new
    chunk.put("body", body)
    for (values) do {v->
        if (v.kind == "dialect") then {
            overall.put("dialect", v.value)
        } else {
            if (v.kind == "blank") then {
                chunkIndex := chunkIndex + 1
                if (chunkLocations.size < chunkIndex) then {
                    chunkLocations.push(object {
                        def top is readable = "{chunkIndex * 10}px"
                        def left is readable = "{chunkIndex * 10}px"
                    })
                }
                chunk := JSObj.new
                arr.push(chunk)
                chunk.put("type", "chunk")
                chunk.put("x", chunkLocations.at(chunkIndex).left)
                chunk.put("y", chunkLocations.at(chunkIndex).top)
                body := JSArray.new
                chunk.put("body", body)
            } else {
                body.push(generateNode(v))
            }
        }
    }
    outfile.write(overall.asJSON ++ "\n")
}
