local doc = require("formatter.doc")
local layout_types = require("formatter.layout_types")
local parser = require("formatter.parser")

local type BlockLayout = layout_types.BlockLayout
local type StatementLayout = layout_types.StatementLayout

local record RenderContext
    render_expr: function(parser.Node): doc.Doc
    render_stmt: function(parser.Node, StatementLayout | nil): doc.Doc | nil
    render_block: function(parser.Node, BlockLayout | nil): doc.Doc | nil
end

local render_context = {
    RenderContext = RenderContext,
}

function RenderContext.new(
    raw_render_block: function(RenderContext, parser.Node, BlockLayout | nil): doc.Doc | nil,
    raw_render_expr: function(RenderContext, parser.Node): doc.Doc,
    raw_render_stmt: function(RenderContext, parser.Node, StatementLayout | nil): doc.Doc | nil
): RenderContext
    local self: RenderContext = setmetatable({}, {__index = RenderContext})
    self.render_block = function(
        node: parser.Node, layout: BlockLayout | nil
    ): doc.Doc | nil
        return raw_render_block(self, node, layout)
    end
    self.render_expr = function(node: parser.Node): doc.Doc
        return raw_render_expr(self, node)
    end
    self.render_stmt = function(
        node: parser.Node, layout: StatementLayout | nil
    ): doc.Doc | nil
        return raw_render_stmt(self, node, layout)
    end
    return self
end

return render_context
