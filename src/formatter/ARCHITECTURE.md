# Formatter architecture

## Pipeline

`rewriter.rewrite(source, filename)` runs two sequential phases.

### 1. Structural phase

```
source
  ├─ lexical whitespace pass   token-level: comma/op spacing, quote normalisation
  ├─ line cleanup pass         strip trailing spaces, expand tabs
  ├─ re-parse
  ├─ structural block render   AST → doc.Doc → {string}, replaces source when approved
  ├─ re-parse
  ├─ span pass                 collect call/table/signature spans; join or split vs 88 cols
  └─ final cleanup             strip trailing spaces, collapse blank lines
```

### 2. Require sort phase

Alphabetically sorts consecutive top-level `local x = require(...)` declarations.

---

## Module map

| File | Responsibility |
|------|---------------|
| `init.tl` | CLI entry point |
| `rewriter.tl` | Assembles all pipeline stages; owns span collection and application |
| `parser.tl` | Forked parser from `tl.parse` returning a typed `Node` tree |
| `ast_utils.tl` | AST traversal, fmt:off region tracking, block-span collection |
| `doc.tl` | Wadler-Lindig document algebra; `Doc:render` produces `{string}` |
| `expr_doc.tl` | AST node → **compact single-line string only** — never wraps |
| `signature_doc.tl` | Function parameter list → wrapped `{string}` or compact text |
| `call_doc.tl` | Function call args → `doc.Doc` (AST→doc path) or `{string}` (span pass) |
| `table_doc.tl` | Table constructor → `doc.Doc` (AST→doc path) or `{string}` (span pass) |
| `stmt_doc.tl` | Single statement → `doc.Doc`; dispatches to `call_doc` for `@funcall` |
| `block_doc.tl` | Block of statements → `doc.Doc` or `{string}` via recursive `stmt_doc` |
| `structural_render_analysis.tl` | Decides if a block is safe for structural rendering; produces `BlockLayout` |
| `require_sort.tl` | Re-orders top-level require declarations alphabetically |

---

## The two rendering paths

### Span pass (line-level)

`rewriter.tl` collects `Span` records for call arg lists, table constructors, and signatures, then applies them bottom-to-top joining or splitting vs 88 columns. Delegates to `call_doc.render_call`, `table_doc.render_table`, `signature_doc.render_signature`. A span is skipped when it overlaps `fmt:off`, contains a comment, or `has_multiline_descendant` returns true.

### Structural block rendering (AST → doc)

When `structural_render_analysis.analyze_block` returns a `BlockLayout`, `block_doc.render_block` renders the entire block via the doc algebra, reindenting at 4-space multiples. The rendered output replaces the source before the span pass runs.

`analyze_block` returns `nil` — blocking structural rendering — when any statement has a comment, `fmt:off`, an unsupported kind, an anonymous function with >1 body statements in an expression, a multi-line `if`/`while`/`for` condition, or non-whitespace between statements.

Blank lines between statements are preserved up to one via `StatementLayout.preserve_blank_line_after`.

---

## The `yend` quirk

The Teal parser sets `node.yend` on block-forming nodes (`if`, `while`, `fornum`, `forin`, `repeat`, `do`, `function`, `local_function`, `global_function`, `record_function`, `literal_table`) but **not** on `local_declaration`, `return`, `assignment`, or `op`.

Always use `node.yend or node.y`. To detect whether a `local_declaration` or `return` spans multiple lines use `has_multiline_descendant` or `max_source_line` from `structural_render_analysis`.

---

## AST → doc transition (in progress)

**Done**: `call_doc.build_call_expr_doc`, `table_doc.build_table_doc`, `stmt_doc`, `block_doc`.

**Still ad-hoc string path**: `signature_doc.render_signature_text` (used for function definition headers in `stmt_doc`); the span pass in `rewriter.tl` (fallback for anything structural rendering can't handle).

**Intended end state**: `block_doc` handles all indentation structurally; span pass reduced to a narrow fallback.
