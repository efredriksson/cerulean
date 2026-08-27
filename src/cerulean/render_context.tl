-- The per-render wiring bag: carries the render callbacks (bound here to break
-- the block_doc <-> expr_doc <-> stmt_doc require cycle) and the shared render
-- inputs every layout module reads.
local ast = require("cerulean.ast")
local comment_slots = require("cerulean.comment_slots")
local doc = require("cerulean.doc")
local source = require("cerulean.source")
local token_stream = require("cerulean.token_stream")

local record RenderContext
    render_expr: function(ast.Node, ?boolean): doc.Doc
    render_block: function(ast.Node): doc.Doc | nil
    fmt_off_regions: source.Regions
    source_lines: {string}
    -- The lossless token stream, index-aligned with the parser tokens that a
    -- node's tok_first/tok_last/slot_tok address; carries the consume ledger.
    tokens: token_stream.Stream
    -- The comment reads: every slot accessor mapping a node's token-ownership
    -- stamps to the comments it emits.
    slots: comment_slots.CommentSlots
end

local render_context = {
    RenderContext = RenderContext,
}

function RenderContext.new(
    raw_render_block: function(RenderContext, ast.Node): doc.Doc | nil,
    raw_render_expr: function(RenderContext, ast.Node, ?boolean): doc.Doc,
    fmt_off_regions: source.Regions,
    source_lines: {string},
    tokens: token_stream.Stream,
    slots: comment_slots.CommentSlots
): RenderContext
    local self: RenderContext = setmetatable({}, {__index = RenderContext})
    self.fmt_off_regions = fmt_off_regions
    self.source_lines = source_lines
    self.tokens = tokens
    self.slots = slots
    self.render_block = function(node: ast.Node): doc.Doc | nil
        return raw_render_block(self, node)
    end
    self.render_expr = function(node: ast.Node, same_indent_on_line?: boolean): doc.Doc
        return raw_render_expr(self, node, same_indent_on_line)
    end
    return self
end

return render_context
