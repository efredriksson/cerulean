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
- `parser.tl` — typed Teal AST parser.
- `ast_traversal.tl` — AST walks + block ranges.
- `source.tl` — `Text`, `Range`, `Region/Regions`, fmt-region collection.
- `render_context.tl` — `RenderContext` + ctor; holds render callbacks (breaks circular deps).
- `doc.tl` — doc algebra + renderer.
- `block_doc.tl` — block rendering, statement glue, `make_context()` factory.
- `stmt_doc.tl` / `expr_doc.tl` / `table_doc.tl` / `signature_doc.tl` — per-kind rendering.
- `delimited_list_doc.tl` — comma-separated, comment-threaded list rendering. `render_items` is the framing-agnostic item loop (driven by an `ItemRenderSpec`); `render_parens` frames it with `(…)`. Shared by call argument lists + parameter lists (`expr_doc`/`signature_doc` via `render_parens`) and table constructors (`table_doc` via `render_items`).
- `render_builders.tl` — shared doc helpers.
- `require_sort.tl` — top-level require reorder.

Dep direction: `rewriter` → render → doc builders → doc core.

## Doc Algebra

Wadler-Lindig: groups try flat, break when they don't fit. Two things in `doc.tl` are worth knowing before changing it.

**One walker, two modes.** `measure(commands, column, state, stop_at_break)` walks the command stack and returns whether it fit plus the column it ended on. `stop_at_break` reports success at the first break — the "does the next line fit" question a group asks, wrapped as `fits`. Without it the column resets to the indent and the walk continues, measuring every line of a layout; that is `layout_fits`. Both share `group_renders_flat` with the renderer, so a measurement can never describe a layout `render_doc` would not produce.

**`first_fit` / `flat`.** `first_fit(states)` offers alternative *complete* layouts and takes the first whose every line fits. A group cannot express this: its one decision is taken before the doc inside it makes its own, so it cannot say "break here only if that alone is enough". Used by the `as`/`is` cast, whose operator and cast type break independently. `flat(child)` pins a subtree against the surrounding mode, which is what keeps the states distinct layouts instead of collapsing them onto the enclosing mode. Three rules hold it together:

- **States run least-broken to most-broken.** The last one is the fallback, so it must offer a break and must not be pinned flat — it is the only state that can reach the renderer unmeasured. `doc.first_fit` asserts both.
- **A next-line check substitutes the last state.** Exact, since the check stops at the first break and the ordering puts the earliest break there. It is also the cost bound: running the real selection instead would make a `first_fit` in another one's tail re-select it, so a cast chain would cost O(states^depth).
- **What follows is measured one line deep.** `layout_fits` measures the candidate's own lines exactly, then hands the rest to `fits` — the same next-line rule every group uses. A `first_fit` therefore chooses on its own lines plus one line of what comes after.

Measurement rejects anything under `flat` that would emit a newline anyway (a group marked `should_break`, a bare `hardline`, `raw`), so a pinned state cannot render differently than it measured.

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
- `append_lines_pre_node(node, line_before, line_from_before?)` — separator + extra `hardline` for `blank_line_before`. Accepts `parser.Node` or `parser.FieldEntry`.
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

Access via `parser.inline_trivia(node, slot)` — returns the list, or an empty constant when absent (treat as read-only). Adding a new between-tokens case = adding an enum value, not a Node field.

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

## AST gotcha

`node.yend` is missing on some single-line statement kinds (`local_declaration`, `return`, `assignment`, `op`). Always use `node.yend or node.y` (or a helper that accounts for nested call-arg end lines).
