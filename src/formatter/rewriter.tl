-- Top-level pipeline: parse -> source/layout analysis -> structural render -> require sort.
-- See ARCHITECTURE.md for the current module map and flow.
local ast_traversal = require("formatter.ast_traversal")
local block_doc = require("formatter.block_doc")
local layout_analysis = require("formatter.layout_analysis")
local parser = require("formatter.parser")
local render_context = require("formatter.render_context")
local require_sort = require("formatter.require_sort")
local source = require("formatter.source")
local tl = require("tl")

local type RenderContext = render_context.RenderContext

local rewriter = {}

local record Rewrite
    output: string
    changed: boolean
    parse_errors: {parser.Error}
end

function Rewrite.new(
    output: string, changed: boolean, parse_errors: {parser.Error}
): Rewrite
    local self: Rewrite = setmetatable({}, {__index = Rewrite})
    self.output = output
    self.changed = changed
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

local function run_structural_phase(
    source_: string, filename: string, ast: parser.Node, ctx: RenderContext
): string
    local context = build_formatter_context(source_, filename, ast)
    local structural_analysis = layout_analysis.analyze_block(
        context.ast, context.source_text.lines, context.fmt_off_regions
    )
    if structural_analysis.can_render_structurally then
        local block_layout = structural_analysis.block_layout
        local structurally_rendered = block_doc.render_block(
            ctx, context.ast, block_layout
        )
        if structurally_rendered ~= nil then
            local rendered_source = table.concat(structurally_rendered, "\n") .. "\n"
            return rendered_source
        end
    end

    return source_
end

local function run_require_sort_phase(
    ctx: RenderContext, source_: string, filename: string
): Rewrite
    local output, parse_errors = require_sort.rewrite(ctx, source_, filename)
    return Rewrite.new(output, output ~= source_, parse_errors)
end

function rewriter.rewrite(source_: string, filename: string): Rewrite
    local ast, parse_errors = parser.parse(source_, filename)
    if #parse_errors > 0 then
        return Rewrite.new(source_, false, parse_errors)
    end

    local ctx = block_doc.make_context()
    local intermediate = run_structural_phase(source_, filename, ast, ctx)
    local reorder_rewrite = run_require_sort_phase(ctx, intermediate, filename)
    if #reorder_rewrite.parse_errors > 0 then
        return Rewrite.new(
            intermediate, intermediate ~= source_, reorder_rewrite.parse_errors
        )
    end

    return Rewrite.new(reorder_rewrite.output, reorder_rewrite.output ~= source_, {})
end

return rewriter
