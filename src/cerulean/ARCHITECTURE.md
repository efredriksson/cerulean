# Formatter Architecture

## Pipeline

`rewriter.rewrite(source, filename)`:
1. `parser.parse` → AST.
2. Source ctx: `source.Text`, `ast_traversal.collect_block_ranges`, `source.collect_fmt_off_regions`.
3. `block_doc.make_context()` → `RenderContext`.
4. `require_sort.sort_top_level_requires`: in-place reorder of contiguous top-level `local ... = require(...)`. Stops at first non-require / fmt:off. Returns `sorted_require_count` so renderer suppresses blank lines within the group.
5. If structural render allowed: `block_doc.render_block(ctx, block, sorted_require_count)` → `stmt_doc` → `expr_doc`/`table_doc`/`signature_doc`, finalized via `doc.Doc:render`.

If blocked or render fails: keep original source.

## Modules

- `rewriter.tl` — pipeline.
- `ast.tl` — the AST data contract: `Node`, the `Type` hierarchy, `Comment`, `InlineSlot`, `inline_trivia` accessor. Renderers depend on this, not on the parser; any parser producing `ast.Node` trees can drive them.
- `parser.tl` — typed Teal parser producing `ast.Node` trees.
- `ast_traversal.tl` — AST walks + block ranges.
- `source.tl` — `Text`, `Range`, `Region/Regions`, fmt-region collection.
- `render_context.tl` — `RenderContext` + ctor; holds render callbacks (breaks circular deps).
- `doc.tl` — doc algebra + renderer.
- `block_doc.tl` — block rendering, statement glue, `make_context()` factory.
- `stmt_doc.tl` / `expr_doc.tl` / `table_doc.tl` / `signature_doc.tl` — per-kind rendering.
- `delimited_list_doc.tl` — comma-separated, comment-threaded list rendering. `render_items` is the framing-agnostic item loop (driven by an `ItemRenderSpec`); `render_parens` frames it with `(…)`. Shared by call argument lists + parameter lists (`expr_doc`/`signature_doc` via `render_parens`) and table constructors (`table_doc` via `render_items`).
- `render_builders.tl` — shared doc helpers.
- `require_sort.tl` — top-level require reorder.

Dep direction: `rewriter` → render → doc builders → doc core. `rewriter` is the only module requiring `parser`; everything downstream depends on `ast` only.

## RenderContext

Breaks `block_doc` ↔ `stmt_doc` ↔ `expr_doc` ↔ `table_doc` cycle via callbacks: `render_expr(node)`, `render_stmt(node)`, `render_block(node)`. `block_doc.make_context()` wires impls (closures over `self`); created once in `rewriter.rewrite`, threaded through render + require-sort.

## render_builders Helpers

(Shared across `block_doc`/`stmt_doc`/`expr_doc`/`table_doc`.)

- `trailing_comment_doc(node)` — joins `trailing_comments` as text (` <c1> <c2>…`), else empty.
- `head_trivia_doc(node)` — emits the `"head"` inline-trivia slot (after `do`/`then`/`function`).
- `with_leading_inline_trivia(node, prefix, content)` — threads the `"after_opener"` inline-trivia slot (same-line after openers like `(`, `=`, `until`, `return`) on the prefix line, breaks before `content`.
- `append_comment_docs(parts, comments, line_before)` — own-line leading comments with `hardline` separators; returns updated `line_before`.
- `any_items_have_comments(items)` — any `leading_comments` / `trailing_comments`. Drives force-wrap. Deliberately ignores `"before_separator"` inline trivia (inline block-trivia must not flip flat → wrapped).
- `item_line_doc(force_wrap)` — `hardline` if force-wrapping, else `softline`.
- `append_lines_pre_node(node, line_before, line_from_before?)` — separator + extra `hardline` for `blank_line_before`. Accepts `ast.Node` or `ast.FieldEntry`.
- `build_grouped_comma_items_doc(item_docs)` — comma list whose commas all give at once: one line, or one item per line. The second stage of every two-stage break (delimited sequences, `=` value lists).
- `exp_list_can_break(exps)` — more than one item and no threaded comments. Guards both list builders below.
- `build_exp_list_doc(ctx, exps)` — comma-joined expression list; threads item comments when present, otherwise `build_grouped_comma_items_doc`. Callers frame it: `inline_stmt_doc` wraps it with `wrap_keyword_before` so a long `=` list drops below the `=` before its commas give.
- `build_return_exp_list_doc(ctx, exps)` — same list, but the first value stays on the `return` line and only the continuations indent. Return-only: a `return` has no operator to its left to give first. Delegates to `build_exp_list_doc` for the comment-threaded path.
- Delimiter builders (`build_delimited_sequence_doc`, `build_comma_separated_docs`, …).

## Comment Model

Hybrid: three node-level slots for structural cases + per-position `{Comment}` trivia lists for between-token cases.

**Node slots** (render order: `leading_comments` → node → `trailing_comments`):
- `leading_comments` — own-line before first token; each carries `blank_line_before`.
- `trailing_comments` — same-line `--` / `--[[…]]` entries after last token; forces a break in surrounding layout.
- `dangling_comments` — own-line inside a block before its closer (`end`, `}`, `until`).

**Inline trivia** — same-line, between-token comments live on the spanning node in one map: `inline_trivia: {InlineSlot: {Comment}}`. Populated at parse time via `take_all_token_comments` / `take_same_line_comments`. Slots (`InlineSlot` enum):
- `"op_leading"` / `"op_trailing"` (binary op) — around the operator. Same-line: inline. Own-line: force chain break.
- `"before_separator"` (call args, decl LHS/RHS) — same-line `--[[…]]` after value, before comma. Does *not* force-wrap.
- `"head"` — same-line after block-opener (`do`/`then`/`function`/`repeat`/`until`). Holds the opener-line comment regardless of whether the body is empty; storage tracks source position, not body state. Empty-body + own-line comment inside the block is the orthogonal case and goes in `dangling_comments`.
- `"after_opener"` — same-line after value-introducing opener (`(`, `=`, `until`, `return`, `if`).

Access via `ast.inline_trivia(node, slot)` — returns the list, or an empty constant when absent (treat as read-only). Adding a new between-tokens case = adding an enum value, not a Node field.

**`trivia_doc.tl` helpers:**
- `partition(trivia, anchor_line)` → `(same_line_head, own_line_tail)`.
- `append_inline(parts, trivia)` — `" --[[c]]"` per entry, leading space.
- `append_inline_joined(parts, trivia)` — single-space separator, no leading space (use after openers).
- `emit_transition(parts, trivia, anchor_line, next_doc, plain_separator)` — operator-position boundary; own-line trivia forces break before `next_doc`, else emits `plain_separator` + `next_doc` flat.

### Design note

The model is deliberately *not* a full token-trivia CST (StyLua / Prettier style). Comments are drained off tokens at parse time and stored on spanning nodes in three structural slots (`leading_comments` / `trailing_comments` / `dangling_comments`) plus one positional map (`inline_trivia`). Moving trivia onto `Token` refs would match the canonical CST conventions but wouldn't reduce renderer complexity (the three branches are real conceptual differences, not storage shape) — not planned without a concrete forcing function (e.g. sharing AST with an external tool).

## require_sort Comment Semantics

Only module mutating AST comment fields post-parse. Two kinds:
- **Attached**: immediately before require (no gap). Moves with require; `blank_line_before` cleared.
- **Floating**: blank-line gap before require, or before first require. Pinned to top of sorted block.

First require's comments: if none floating, attached are treated as module docs and also pinned.

## Parser contract

What any parser (incl. future replacement) must supply. Renderers depend only on `ast.tl`; `rewriter.tl` sole consumer of `parser.tl`.

**API.** `parser.parse(input, filename) → ast.Node, {tl.Error}, integer`.
- Fail-fast: stop at first syntax error; error list ≤1 entry (`filename`, `y`, `x`, `msg`). On error rewriter leaves source unchanged.
- Grammar only: anything grammatical parses, incl. Teal-invalid code (unknown attributes, redeclared fields, optional-arg order). Semantics belong to `tl check`.
- Integer = lex-level comment count of input: every comment, attached to AST or not. Rewriter compares source vs output counts as comment-preservation safety net (`rewriter.tl`); catches attachment bugs only because count independent of attachment.

**Positions.** `y`/`x` 1-indexed (`Where` interface). `node.yend` guaranteed on statements (set in `parse_statements`) + expression nodes (set before operands wrapped into op nodes); renderers read directly, no `yend or y` fallback. Other kinds (e.g. `if_block` with empty body) may lack `yend`; fallback only there. `close_x` = closing keyword's start column on block statements; nil at top level (EOF not closer).

**Token fidelity.** `node.tk` = verbatim source text. String nodes carry `tk` (with quotes), `conststr` (unquoted value), `is_longstring`. Op nodes carry `op.op`, `op.prec`, `op.y`: expression rendering + trivia placement need all three.

**Trivia.** `Comment.text` includes delimiters (`--`, `--[[ ]]`). Attachment rules (three node slots + `inline_trivia` map): see Comment Model section above.

**Conformance.** `make ab-snapshot` pins per-file status + output over `fuzz/corpus/`; `make ab-diff` reruns, reports drift. Snapshot before parser change, diff after; review every drift, then retake snapshot.
