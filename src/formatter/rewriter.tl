-- Top-level pipeline: lexical pass → line cleanup → structural block render → span pass → cleanup.
-- See ARCHITECTURE.md for the full pipeline diagram.
local ast_utils = require("formatter.ast_utils")
local block_doc = require("formatter.block_doc")
local parser = require("formatter.parser")
local require_sort = require("formatter.require_sort")
local structural_render_analysis = require("formatter.structural_render_analysis")
local tl = require("tl")

local rewriter = {}

local record Rewrite
    output: string
    changed: boolean
    parse_errors: {tl.Error}
end

function Rewrite.new(
    output: string, changed: boolean, parse_errors: {tl.Error}
): Rewrite
    local self: Rewrite = setmetatable({}, {__index = Rewrite})
    self.output = output
    self.changed = changed
    self.parse_errors = parse_errors
    return self
end

local record FormatterContext
    ast: parser.Node
    tokens: {tl.Token}
    lines: {string}
    fmt_off_regions: ast_utils.FmtOffRegions
end

function FormatterContext.new(
    ast: parser.Node,
    tokens: {tl.Token},
    lines: {string},
    fmt_off_regions: ast_utils.FmtOffRegions
): FormatterContext
    local self: FormatterContext = setmetatable({}, {__index = FormatterContext})
    self.ast = ast
    self.tokens = tokens
    self.lines = lines
    self.fmt_off_regions = fmt_off_regions
    return self
end

local function split_preserving_trailing_newline(source: string): {string}
    local lines: {string} = {}
    for line_str in string.gmatch(source .. "\n", "(.-)\n") do
        table.insert(lines, line_str)
    end
    return lines
end

local function build_formatter_context(
    source: string, filename: string, ast: parser.Node
): FormatterContext
    local source_blocks = ast_utils.collect_block_spans(ast)
    local tokens, _ = tl.lex(source, filename)
    local lines = split_preserving_trailing_newline(source)
    local fmt_off_regions = ast_utils.collect_fmt_off_regions(lines, source_blocks)

    return FormatterContext.new(ast, tokens, lines, fmt_off_regions)
end

local function run_structural_phase(
    source: string, filename: string, ast: parser.Node
): string
    local context = build_formatter_context(source, filename, ast)
    local structural_analysis = structural_render_analysis.analyze_block(
        context.ast, context.lines, context.fmt_off_regions
    )
    if structural_analysis.can_render_structurally then
        local block_layout = structural_analysis.block_layout
        local structurally_rendered = block_doc.render_block(context.ast, block_layout)
        if structurally_rendered ~= nil then
            local rendered_source = table.concat(structurally_rendered, "\n") .. "\n"
            return rendered_source
        end
    end

    return source
end

local function run_require_sort_phase(source: string, filename: string): Rewrite
    local output, parse_errors = require_sort.rewrite(source, filename)
    return Rewrite.new(output, output ~= source, parse_errors)
end

function rewriter.rewrite(source: string, filename: string): Rewrite
    local ast, parse_errors = parser.parse(source, filename)
    if #parse_errors > 0 then
        return Rewrite.new(source, false, parse_errors)
    end

    local intermediate = run_structural_phase(source, filename, ast)
    local reorder_rewrite = run_require_sort_phase(intermediate, filename)
    if #reorder_rewrite.parse_errors > 0 then
        return Rewrite.new(
            intermediate, intermediate ~= source, reorder_rewrite.parse_errors
        )
    end

    return Rewrite.new(reorder_rewrite.output, reorder_rewrite.output ~= source, {})
end

return rewriter
