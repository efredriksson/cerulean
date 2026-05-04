# Formatter Architecture

## Pipeline

`rewriter.rewrite(source, filename)` does:

1. Parse source to AST (`parser.parse`).
2. Build source context:
   - `source.Text` for line view
   - `ast_traversal.collect_block_ranges` + `source.collect_fmt_off_regions`.
3. Create `RenderContext` via `block_doc.make_context()`.
4. Sort top-level require declarations (`require_sort.sort_top_level_requires`):
   - Reorders contiguous `local ... = require(...)` nodes in AST in-place.
   - Stops at first non-require statement or fmt:off region.
   - Returns `sorted_require_count` for renderer to suppress blank lines within group.
5. If structural render allowed, render full AST block via doc tree:
   - `block_doc.render_block(ctx, block, sorted_require_count)` -> `stmt_doc` -> `expr_doc`/`table_doc`/`signature_doc`
   - render with `doc.Doc:render(...)`.

If structural render blocked or rendering fails, keep original source.

## Core Modules

- `rewriter.tl`: pipeline orchestration.
- `parser.tl`: typed Teal AST parser.
- `ast_traversal.tl`: AST traversal + AST-derived block ranges.
- `source.tl`: source domain (`Text`, `Range`, `Region/Regions`, fmt-region collection).
- `render_context.tl`: `RenderContext` type and constructor — holds callbacks for rendering expressions, statements, blocks, breaking circular module deps.
- `doc.tl`: document algebra and renderer.
- `block_doc.tl`: block-level rendering, statement glue, and `make_context()` factory.
- `stmt_doc.tl`: statement rendering.
- `expr_doc.tl`: expression rendering + precedence.
- `table_doc.tl`: table constructor rendering.
- `signature_doc.tl`: function signature rendering.
- `render_builders.tl`: shared doc-building helpers across rendering modules.
- `require_sort.tl`: in-place AST reorder of top-level `local ... = require(...)` declarations.

## Dependency Shape

Preferred direction:

`rewriter`
-> `render`
-> `doc builders`
-> `doc core`

## RenderContext

Breaks circular deps (`block_doc` ↔ `stmt_doc` ↔ `expr_doc` ↔ `table_doc`) via three callbacks:

- `render_expr(node)` → `doc.Doc`
- `render_stmt(node)` → `doc.Doc | nil`
- `render_block(node)` → `doc.Doc | nil`

`block_doc.make_context()` wires concrete implementations into `RenderContext.new()`, builds closures that partially apply `self`. Created once in `rewriter.rewrite`, threaded through render and require-sort phases.

## render_builders Helpers

Shared across `block_doc`, `stmt_doc`, `expr_doc`, `table_doc`:

- `trailing_comment_doc(node)` — same-line comment as `doc.text`, or empty.
- `head_trivia_doc(node)` — emits `head_trivia` (same-line comments after a block-opening keyword like `do`/`then`/`function`).
- `with_leading_inline_trivia(node, prefix, content)` — wraps `content` after `prefix`, threading any `leading_inline_trivia` (same-line comments after an opener like `(`, `=`, `until`, `return`) on the prefix line and breaking before `content`.
- `append_comment_docs(parts, comments, line_before)` — prepend leading own-line comments with `hardline` separators; returns updated `line_before`.
- `any_items_have_comments(items)` — true if any item has `leading_comments` or `trailing_comment`; drives force-wrap. Note: deliberately *does not* consult `trailing_trivia`, since inline block-trivia must not flip a flat layout to wrapped.
- `item_line_doc(force_wrap)` — `hardline` if force-wrapping, else `softline`.
- `append_lines_pre_node(node, line_before, line_from_before?)` — emit separator + extra `hardline` for `blank_line_before`. Accepts `parser.Node` or `parser.FieldEntry`.
- Delimiter builders (`build_delimited_sequence_doc`, `build_comma_separated_docs`, etc.) — bracketed comma-separated doc sequences.

## Comment Model

Cerulean uses a hybrid model: structural comments live in three node-level slots; positional comments between specific tokens live in trivia lists owned by the node spanning those tokens.

### Node-level slots

- `node.leading_comments` — own-line comments before the node's first token. Each carries `blank_line_before: boolean`.
- `node.trailing_comment` — single same-line `--`-style comment after the node's last token. Forces a break in the surrounding layout.
- `node.dangling_comments` — own-line comments inside a block construct before its closing keyword/delimiter (`end`, `}`, `until`).

Render order: `leading_comments` → node → `trailing_comment`.

### Trivia lists (positional, between tokens)

For comments that sit between *specific* tokens of a single node — where neither the preceding child nor the following child can own them — the spanning node holds a typed `{Comment}` list keyed by position:

- `op_leading_trivia` / `op_trailing_trivia` (binary `op` nodes) — comments around the operator token. Same-line entries render inline; own-line entries force the chain to break.
- `trailing_trivia` (call args, declaration RHS values) — same-line block comments (`--[[...]]`) emitted after the value but before the comma. Does *not* force-wrap a list that would otherwise fit flat.
- `head_trivia` (block nodes) — same-line comments after a block-opening keyword (`do`, `then`, `function`).
- `leading_inline_trivia` — same-line comments after an opener that introduces a value (`(`, `=`, `until`, `return`, `if`).

Trivia lists are populated during parse by draining `token.comments` via `take_all_token_comments` (whole list) or `take_same_line_comments` (line-matched). Renderers compose trivia via the helpers in `trivia_doc.tl`:

- `partition(trivia, anchor_line)` — splits into a single same-line head + own-line tail.
- `append_inline(parts, trivia)` — `" --[[c]]"` per entry, leading space.
- `append_inline_joined(parts, trivia)` — same content, single-space separator, no leading space (for use after openers).
- `emit_transition(parts, trivia, anchor_line, next_doc, plain_separator)` — boundary handler for operator-like positions: own-line entries force a break before `next_doc`; otherwise emits `plain_separator` and `next_doc` flat.

## require_sort Comment Semantics

Only module mutating AST comment fields post-parse. Two kinds:
- **Attached**: immediately before require (no gap). Move with require; `blank_line_before` cleared.
- **Floating**: blank-line gap before require, or before first require. Pinned to top of sorted block.

First require's comments: if none floating, attached treated as module docs and also pinned.

## Important AST Detail

`node.yend` missing on some single-line statement kinds (`local_declaration`, `return`, `assignment`, `op`).
Always treat end line as `node.yend or node.y` (or helper that accounts for nested call arg end lines when needed).
