# Formatter Architecture

## Pipeline

`rewriter.rewrite(source, filename)` does:

1. Parse source to AST (`parser.parse`).
2. Build formatting context (lines + `fmt:off` regions from `ast_utils`).
3. Structural analysis (`structural_render_analysis.analyze_block`):
   - returns `{ can_render_structurally, block_layout }`.
4. If structural render is allowed, render full AST block via doc tree:
   - `block_doc` -> `stmt_doc` -> `expr_doc`/`call_doc`/`table_doc`/`signature_doc`
   - render with `doc.Doc:render(...)`.
5. Run `require_sort.rewrite` on resulting source.

If structural render is blocked or rendering fails, keep original source and still run require sorting.

## Core Modules

- `rewriter.tl`: pipeline orchestration.
- `parser.tl`: typed Teal AST parser.
- `ast_utils.tl`: AST walking + `fmt:off` region collection.
- `structural_render_analysis.tl`: layout/eligibility analysis.
- `layout_types.tl`: `BlockLayout`/`StatementLayout` types.
- `doc.tl`: document algebra and renderer.
- `block_doc.tl`: block-level rendering and statement glue.
- `stmt_doc.tl`: statement rendering.
- `expr_doc.tl`: expression rendering + precedence.
- `call_doc.tl`: call argument list rendering (owned here).
- `table_doc.tl`: table constructor rendering.
- `signature_doc.tl`: function signature rendering.
- `render_builders.tl`: shared delimiter/comment builders.
- `require_sort.tl`: top-level contiguous `local ... = require(...)` sort pass.

## Dependency Shape

Preferred direction is:

`rewriter`
-> `analysis + render`
-> `doc builders`
-> `doc core`

Rendering modules should depend on `layout_types`, not on analysis internals.

## Important AST Detail

`node.yend` is missing on some single-line statement kinds (`local_declaration`, `return`, `assignment`, `op`).
Always treat end line as `node.yend or node.y` (or a helper that accounts for nested call arg end lines when needed).
