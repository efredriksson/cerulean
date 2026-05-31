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
