local ast = require("cerulean.ast")
local doc = require("cerulean.doc")
local source = require("cerulean.source")

local record RenderContext
    render_expr: function(ast.Node, ?boolean): doc.Doc
    render_block: function(ast.Node): doc.Doc | nil
    fmt_off_regions: source.Regions
    source_lines: {string}
end

local render_context = {
    RenderContext = RenderContext,
}

function RenderContext.new(
    raw_render_block: function(RenderContext, ast.Node): doc.Doc | nil,
    raw_render_expr: function(RenderContext, ast.Node, ?boolean): doc.Doc,
    fmt_off_regions: source.Regions,
    source_lines: {string}
): RenderContext
    local self: RenderContext = setmetatable({}, {__index = RenderContext})
    self.fmt_off_regions = fmt_off_regions
    self.source_lines = source_lines
    self.render_block = function(node: ast.Node): doc.Doc | nil
        return raw_render_block(self, node)
    end
    self.render_expr = function(node: ast.Node, same_indent_on_line?: boolean): doc.Doc
        return raw_render_expr(self, node, same_indent_on_line)
    end
    return self
end

return render_context
