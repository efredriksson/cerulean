-- Recompute blank_line_before on container children from the lossless token
-- stream. The renderer reads the flag to keep a single blank line above an item;
-- a blank is kept only when the item starts more than one line past the previous
-- item's end -- or, when the item has leading comments, past the end of that
-- leading run, since the comments carry their own blank. The first item of a
-- container has no predecessor, so without a leading run it never leads with a
-- blank.
--
-- Every line here is read as geometry: this pass runs before the render, so it
-- must not consume the comments it measures (see CommentSlots:leading_extent).
local ast = require("cerulean.ast")
local ast_traversal = require("cerulean.ast_traversal")
local render_context = require("cerulean.render_context")

local type RenderContext = render_context.RenderContext

local blank_lines = {}

-- An item is introduced on its first token's line and reaches to its last
-- token's, both read off the span the parser stamped rather than off the node's
-- own y: an op node's y is its operator's line, so a wrapped operand like
-- `foo\n    + bar` would otherwise look as though it began on the `+` line.
local function mark_run<T is ast.ContainerItem>(
    ctx: RenderContext, items: {T}, absorb_opener: boolean
)
    local previous_end: integer | nil = nil
    for index, item in ipairs(items) do
        if item.tok_first ~= nil and item.tok_last ~= nil then
            local leading_end = ctx.slots:leading_extent(
                item, items[index - 1], absorb_opener
            )
            if leading_end > 0 then
                previous_end = leading_end
            end
            if previous_end ~= nil then
                item.blank_line_before = ctx.tokens[item.tok_first].y > previous_end + 1
            end
            previous_end = ctx.tokens[item.tok_last].yend
        end
    end
end

-- The containers whose children carry blank_line_before: statement lists, table
-- literals, and call-argument lists on nodes; enum items and field entries on
-- types. A table, enum or record body's first item also absorbs the opener's
-- same-line comment (see RenderContext:item_leading_comments), so its leading run
-- is measured with absorb on; a parenthesized argument list leaves that comment
-- to its after_opener slot.
function blank_lines.mark(root: ast.Node, ctx: RenderContext)
    local function on_node(node: ast.Node)
        if node.kind == "statements" then
            mark_run(ctx, node, false)
        elseif node.kind == "literal_table" then
            mark_run(ctx, node, true)
        elseif node.kind == "call" and node.e2 then
            mark_run(ctx, node.e2, false)
        end
    end

    local function on_type(typ: ast.Type)
        if typ is ast.EnumType then
            mark_run(ctx, typ.enum_items, true)
        elseif typ is ast.RecordLikeType then
            mark_run(ctx, typ.field_entries, true)
        end
    end

    ast_traversal.walk_owners(root, on_node, on_type)
end

return blank_lines
