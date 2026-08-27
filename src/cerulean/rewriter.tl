-- Top-level pipeline: parse -> source analysis -> require sort -> structural render.
-- See ARCHITECTURE.md for the current module map and flow.
local ast = require("cerulean.ast")
local ast_traversal = require("cerulean.ast_traversal")
local blank_lines = require("cerulean.blank_lines")
local block_doc = require("cerulean.block_doc")
local comment_audit = require("cerulean.comment_audit")
local fmt_logger = require("cerulean.fmt_logger")
local options = require("cerulean.options")
local parser = require("cerulean.parser")
local require_sort = require("cerulean.require_sort")
local source = require("cerulean.source")
local token_stream = require("cerulean.token_stream")

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
    self.failure_reason = failure_reason or ""
    return self
end

-- Name every comment the renderer never consumed, so that when the audit then
-- rejects the output this pinpoints what the render lost. Info level, not error:
-- an unconsumed comment funnels into the accepted safe-skip fallback, which
-- reports to the user at the end. Runs after the render, so taking the strays
-- off the ledger retires no read anything else performs.
local function log_unconsumed_comments(
    tokens: token_stream.Stream, fmt_off_regions: source.Regions
)
    local strays = tokens:take_unconsumed(1, #tokens, fmt_off_regions)
    for k = 1, #strays do
        fmt_logger.info(
            "[audit] comment never consumed at line %s: %s",
            tostring(strays[k].y),
            strays[k].text
        )
    end
end

local function render_with_ast(
    source_: string,
    root: ast.Node,
    opts: FormatterOptions,
    source_tokens: token_stream.Stream
): string
    local source_text = source.Text.new(source_)
    local fmt_off_regions = source.collect_fmt_off_regions(
        source_text, ast_traversal.collect_block_ranges(root)
    )
    local no_overrides: {ast.Node: {ast.Comment}} = {}
    local ctx = block_doc.make_context(
        fmt_off_regions, source_text.lines, source_tokens, no_overrides
    )
    -- Recompute blank_line_before on container children from the token stream
    -- before require_sort, which then overrides the flags on the requires it
    -- reorders.
    blank_lines.mark(root, ctx)
    local require_sort_tail: {ast.Comment} = {}
    if opts.sort_requires then
        -- require_sort reorders the requires and returns where their comments go;
        -- it sources each node's leading comments from the token stream (the same
        -- read the renderer uses, here with no overrides in play yet) and the
        -- placement it returns becomes the renderer's leading overrides.
        local function read_leading(node: ast.Node): {ast.Comment}
            return ctx.slots:leading_comments(node)
        end
        ctx.slots.leading_overrides, require_sort_tail = require_sort.sort_top_level_requires(
            root, fmt_off_regions, read_leading
        )
    end
    local rendered = block_doc.render_block(
        ctx, root, opts.max_line_width, opts.indent_width, require_sort_tail
    )
    -- The scan exists only to name what the audit will reject; skip the token
    -- walk entirely when info logging is off.
    if rendered ~= nil and fmt_logger.enabled("info") then
        log_unconsumed_comments(source_tokens, fmt_off_regions)
    end
    return rendered
end

local function describe_problem(problem: comment_audit.Problem): string
    local location = ""
    if #problem.lines > 0 then
        local numbers: {string} = {}
        for _, line in ipairs(problem.lines) do
            table.insert(numbers, tostring(line))
        end
        location = string.format(" (source line %s)", table.concat(numbers, ", "))
    end
    return string.format("%s comment %q%s", problem.kind, problem.text, location)
end

-- Reject formatter output that is unsafe to emit, returning the reason or nil when
-- safe. The output must parse and preserve every comment; a dropped or duplicated
-- comment is corruption an idempotency check would call stable, so the audit names
-- the offending comment(s) and the caller falls back to the original source.
local function output_failure(
    source_tokens: token_stream.Stream, output: string, filename: string
): string
    -- One lex of the output (inside the parse); the audit's stream view is
    -- built from the token array the parse returns.
    local _, parse_errors, output_raw = parser.parse(output, filename)
    if #parse_errors > 0 then
        return "the formatter produced output that is not valid Teal"
    end
    local output_tokens = token_stream.from_tokens(output_raw)
    local problems = comment_audit.diff(source_tokens, output_tokens)
    if #problems == 0 then
        return nil
    end
    local descriptions: {string} = {}
    for _, problem in ipairs(problems) do
        table.insert(descriptions, describe_problem(problem))
    end
    return "the formatter changed comments: " .. table.concat(descriptions, "; ")
end

function rewriter.rewrite(
    source_: string, filename: string, opts: FormatterOptions
): Rewrite
    -- The parser owns the lex and returns its token array with the statement
    -- `;` tokens it discarded removed (their comments moved to the next
    -- token); the lossless stream the render and audit read is built from that
    -- array, so node token indices address it directly.
    local root, parse_errors, parsed_tokens = parser.parse(source_, filename)
    if #parse_errors > 0 then
        return Rewrite.new(source_, "unchanged", parse_errors)
    end
    local source_tokens = token_stream.from_tokens(parsed_tokens)

    -- Test-only invariant: the renderer routes comments purely off the parser's
    -- ownership stamps, so an unowned separator means a consumption site forgot
    -- to stamp -- fail loudly instead of silently re-routing a comment.
    if opts.strict_comments then
        local violations = parser.check_separator_ownership(root, parsed_tokens)
        if #violations > 0 then
            error(
                string.format(
                    "%s: separator tokens without an owning stamp: %s",
                    filename,
                    table.concat(violations, ", ")
                )
            )
        end
    end

    local output = render_with_ast(source_, root, opts, source_tokens)
    if not output then
        return Rewrite.new(
            source_, "failed", {}, "the formatter could not render this file"
        )
    end

    -- Byte-identical output needs no safety check: it parses (the source did)
    -- and trivially preserves every comment.
    if output == source_ then
        return Rewrite.new(output, "unchanged", {})
    end

    -- A successful render can still be corrupt; fall back to the original source
    -- when the safety check rejects it.
    local failure = output_failure(source_tokens, output, filename)
    if failure then
        if opts.strict_comments then
            error(string.format("%s: %s", filename, failure))
        end
        return Rewrite.new(source_, "failed", {}, failure)
    end

    return Rewrite.new(output, "reformatted", {})
end

return rewriter
