-- Function parameter list → doc.Doc.
local ast = require("cerulean.ast")
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local type_doc = require("cerulean.type_doc")

local signature_doc = {}

local function build_signature_item_doc(arg_node: ast.Node): doc.Doc
    local parts: {doc.Doc} = {
        doc.text(arg_node.tk),
    }

    if arg_node.opt == true and arg_node.tk ~= "..." then
        table.insert(parts, doc.text("?"))
    end

    if arg_node.argtype ~= nil then
        table.insert(parts, doc.text(": "))
        table.insert(parts, type_doc.render(arg_node.argtype))
    end

    return doc.concat(parts)
end

local function argument_nodes(args: ast.Node): {ast.Node}
    local result: {ast.Node} = {}
    for _, arg_node in ipairs(args) do
        if arg_node.kind == "argument" then
            table.insert(result, arg_node)
        end
    end
    return result
end

-- Parameter lists are paren-delimited with no trailing comma, exactly like
-- function call argument lists, so both delegate to `paren_list_doc.render`.
function signature_doc.render_signature_doc(args: ast.Node): doc.Doc
    return delimited_list_doc.render_parens(
        args, argument_nodes(args), build_signature_item_doc
    )
end

return signature_doc
