local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local source = require("cerulean.source")

local record RenderContext
    render_expr: function(parser.Node, ?boolean): doc.Doc
    render_block: function(parser.Node): doc.Doc | nil
    fmt_off_regions: source.Regions
    source_lines: {string}
    hug_single_argument: boolean
end

local render_context = {
    RenderContext = RenderContext,
}

function RenderContext.new(
    raw_render_block: function(RenderContext, parser.Node): doc.Doc | nil,
    raw_render_expr: function(RenderContext, parser.Node, ?boolean): doc.Doc,
    fmt_off_regions: source.Regions,
    source_lines: {string},
    hug_single_argument: boolean
): RenderContext
    local self: RenderContext = setmetatable({}, {__index = RenderContext})
    self.fmt_off_regions = fmt_off_regions
    self.source_lines = source_lines
    self.hug_single_argument = hug_single_argument
    self.render_block = function(node: parser.Node): doc.Doc | nil
        return raw_render_block(self, node)
    end
    self.render_expr = function(
        node: parser.Node, same_indent_on_line?: boolean
    ): doc.Doc
        return raw_render_expr(self, node, same_indent_on_line)
    end
    return self
end

return render_context
