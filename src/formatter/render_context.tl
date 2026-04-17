local doc = require("formatter.doc")
local parser = require("formatter.parser")
local source = require("formatter.source")

local record RenderContext
    render_expr: function(parser.Node): doc.Doc
    render_block: function(parser.Node): doc.Doc | nil
    fmt_off_regions: source.Regions
    source_lines: {string}
end

local render_context = {
    RenderContext = RenderContext,
}

function RenderContext.new(
    raw_render_block: function(RenderContext, parser.Node): doc.Doc | nil,
    raw_render_expr: function(RenderContext, parser.Node): doc.Doc,
    fmt_off_regions: source.Regions,
    source_lines: {string}
): RenderContext
    local self: RenderContext = setmetatable({}, {__index = RenderContext})
    self.fmt_off_regions = fmt_off_regions
    self.source_lines = source_lines
    self.render_block = function(node: parser.Node): doc.Doc | nil
        return raw_render_block(self, node)
    end
    self.render_expr = function(node: parser.Node): doc.Doc
        return raw_render_expr(self, node)
    end
    return self
end

return render_context
