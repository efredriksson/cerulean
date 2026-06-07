-- Top-level pipeline: parse -> source analysis -> require sort -> structural render.
-- See ARCHITECTURE.md for the current module map and flow.
local ast_traversal = require("cerulean.ast_traversal")
local block_doc = require("cerulean.block_doc")
local options = require("cerulean.options")
local parser = require("cerulean.parser")
local require_sort = require("cerulean.require_sort")
local source = require("cerulean.source")

local type FormatterOptions = options.FormatterOptions

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
    failure_reason: string
end

function Rewrite.new(
    output: string,
    status: Status,
    parse_errors: {parser.Error},
    failure_reason?: string
): Rewrite
    local self: Rewrite = setmetatable({}, {__index = Rewrite})
    self.output = output
    self.status = status
    self.parse_errors = parse_errors
    self.failure_reason = failure_reason
    return self
end

local record FormatterContext
    ast: parser.Node
    source_text: source.Text
    fmt_off_regions: source.Regions
end

function FormatterContext.new(
    ast: parser.Node, source_text: source.Text, fmt_off_regions: source.Regions
): FormatterContext
    local self: FormatterContext = setmetatable({}, {__index = FormatterContext})
    self.ast = ast
    self.source_text = source_text
    self.fmt_off_regions = fmt_off_regions
    return self
end

local function build_formatter_context(
    source_code: string, ast: parser.Node
): FormatterContext
    local source_text = source.Text.new(source_code)
    local source_blocks = ast_traversal.collect_block_ranges(ast)
    local fmt_off_regions = source.collect_fmt_off_regions(source_text, source_blocks)

    return FormatterContext.new(ast, source_text, fmt_off_regions)
end

local function render_with_ast(
    source_: string, ast: parser.Node, opts: FormatterOptions
): string
    local context = build_formatter_context(source_, ast)
    local ctx = block_doc.make_context(
        context.fmt_off_regions, context.source_text.lines
    )
    if opts.sort_requires then
        require_sort.sort_top_level_requires(context.ast, context.fmt_off_regions)
    end
    return block_doc.render_block(
        ctx, context.ast, opts.max_line_width, opts.indent_width
    )
end

-- Reject formatter output that is unsafe to emit, returning the reason or nil when
-- safe. The output must parse and preserve every comment 1:1; a changed comment count
-- is corruption that an idempotency check would call stable.
local function output_failure(
    source_comments: integer, output: string, filename: string
): string
    local _, parse_errors, _, output_comments = parser.parse(output, filename)
    if #parse_errors > 0 then
        return "the formatter produced output that is not valid Teal"
    end
    if source_comments ~= output_comments then
        return string.format(
            "the formatter changed the number of comments (%d -> %d)",
            source_comments,
            output_comments
        )
    end
    return nil
end

function rewriter.rewrite(
    source_: string, filename: string, opts: FormatterOptions
): Rewrite
    local ast, parse_errors, _, source_comments = parser.parse(source_, filename)
    if #parse_errors > 0 then
        return Rewrite.new(source_, "unchanged", parse_errors)
    end

    local output = render_with_ast(source_, ast, opts)
    if not output then
        return Rewrite.new(
            source_, "failed", {}, "the formatter could not render this file"
        )
    end

    -- A successful render can still be corrupt; fall back to the original source
    -- when the safety check rejects it.
    local failure = output_failure(source_comments, output, filename)
    if failure then
        return Rewrite.new(source_, "failed", {}, failure)
    end

    if output == source_ then
        return Rewrite.new(output, "unchanged", {})
    end
    return Rewrite.new(output, "reformatted", {})
end

return rewriter
