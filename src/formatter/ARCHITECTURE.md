# Formatter Architecture

## Pipeline

`rewriter.rewrite(source, filename)` does:

1. Parse source to AST (`parser.parse`).
2. Build source context:
   - `source.Text` for line view
   - `ast_traversal.collect_block_ranges` + `source.collect_fmt_off_regions`.
3. Create a `RenderContext` via `block_doc.make_context()`.
4. Sort top-level require declarations (`require_sort.sort_top_level_requires`):
   - Reorders contiguous `local ... = require(...)` nodes in the AST in-place.
   - Stops at the first non-require statement or fmt:off region.
   - Returns `sorted_require_count` for the renderer to suppress blank lines within the group.
5. Layout analysis (`layout_analysis.analyze_block`):
   - returns `{ can_render_structurally, block_layout }`.
6. If structural render is allowed, render full AST block via doc tree:
   - `block_doc.render_block(ctx, block, layout, sorted_require_count)` -> `stmt_doc` -> `expr_doc`/`table_doc`/`signature_doc`
   - render with `doc.Doc:render(...)`.

If structural render is blocked or rendering fails, keep original source.

## Core Modules

- `rewriter.tl`: pipeline orchestration.
- `parser.tl`: typed Teal AST parser.
- `ast_traversal.tl`: AST traversal + AST-derived block ranges.
- `source.tl`: source domain (`Text`, `Range`, `Region/Regions`, fmt-region collection).
- `layout_analysis.tl`: layout/eligibility analysis.
- `layout_types.tl`: `BlockLayout`/`StatementLayout` types.
- `render_context.tl`: `RenderContext` type and constructor — holds callbacks for rendering expressions, statements, and blocks, breaking circular module dependencies.
- `doc.tl`: document algebra and renderer.
- `block_doc.tl`: block-level rendering, statement glue, and `make_context()` factory.
- `stmt_doc.tl`: statement rendering.
- `expr_doc.tl`: expression rendering + precedence.
- `table_doc.tl`: table constructor rendering.
- `signature_doc.tl`: function signature rendering.
- `render_builders.tl`: shared delimiter/comment builders.
- `require_sort.tl`: in-place AST reorder of top-level `local ... = require(...)` declarations.

## Dependency Shape

Preferred direction is:

`rewriter`
-> `analysis + render`
-> `doc builders`
-> `doc core`

Rendering modules should depend on `layout_types` and `render_context`, not on analysis internals.

## RenderContext

Breaks circular deps (`block_doc` ↔ `stmt_doc` ↔ `expr_doc` ↔ `table_doc`) via three callbacks:

- `render_expr(node)` → `doc.Doc`
- `render_stmt(node, layout)` → `doc.Doc | nil`
- `render_block(node, layout)` → `doc.Doc | nil`

`block_doc.make_context()` wires the concrete implementations into `RenderContext.new()`, which builds closures that partially apply `self`. Created once in `rewriter.rewrite`, threaded through render and require-sort phases.

## Important AST Detail

`node.yend` is missing on some single-line statement kinds (`local_declaration`, `return`, `assignment`, `op`).
Always treat end line as `node.yend or node.y` (or a helper that accounts for nested call arg end lines when needed).
