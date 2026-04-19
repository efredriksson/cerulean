-- Top-level pipeline: parse -> source analysis -> require sort -> structural render.
-- See ARCHITECTURE.md for the current module map and flow.
local ast_traversal = require("formatter.ast_traversal")
local block_doc = require("formatter.block_doc")
local FormatterOptions = require("formatter.options")
local parser = require("formatter.parser")
local require_sort = require("formatter.require_sort")
local source = require("formatter.source")
local tl = require("tl")

local enum Status
    "reformatted"
    "unchanged"
    "failed"
end

local rewriter = {Status = Status}

local record Rewrite
    output: string
    status: Status
    parse_errors: {parser.Error}
end

function Rewrite.new(
    output: string, status: Status, parse_errors: {parser.Error}
): Rewrite
    local self: Rewrite = setmetatable({}, {__index = Rewrite})
    self.output = output
    self.status = status
    self.parse_errors = parse_errors
    return self
end

local record FormatterContext
    ast: parser.Node
    tokens: {parser.Token}
    source_text: source.Text
    fmt_off_regions: source.Regions
end

function FormatterContext.new(
    ast: parser.Node,
    tokens: {parser.Token},
    source_text: source.Text,
    fmt_off_regions: source.Regions
): FormatterContext
    local self: FormatterContext = setmetatable({}, {__index = FormatterContext})
    self.ast = ast
    self.tokens = tokens
    self.source_text = source_text
    self.fmt_off_regions = fmt_off_regions
    return self
end

local function build_formatter_context(
    source_code: string, filename: string, ast: parser.Node
): FormatterContext
    local source_text = source.Text.new(source_code)
    local source_blocks = ast_traversal.collect_block_ranges(ast)
    local tokens, _ = tl.lex(source_code, filename)
    local fmt_off_regions = source.collect_fmt_off_regions(source_text, source_blocks)

    return FormatterContext.new(ast, tokens, source_text, fmt_off_regions)
end

function rewriter.rewrite(
    source_: string, filename: string, opts: FormatterOptions
): Rewrite
    local ast, parse_errors = parser.parse(source_, filename)
    if #parse_errors > 0 then
        return Rewrite.new(source_, "unchanged", parse_errors)
    end

    local context = build_formatter_context(source_, filename, ast)
    local ctx = block_doc.make_context(
        context.fmt_off_regions, context.source_text.lines
    )
    if opts.sort_requires then
        require_sort.sort_top_level_requires(context.ast, context.fmt_off_regions)
    end
    local output = block_doc.render_block(
        ctx, context.ast, opts.max_line_width, opts.indent_width
    )
    if not output then
        return Rewrite.new(source_, "failed", {})
    end
    if output == source_ then
        return Rewrite.new(output, "unchanged", {})
    end
    return Rewrite.new(output, "reformatted", {})
end

return rewriter
