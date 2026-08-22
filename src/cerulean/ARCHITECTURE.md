# Formatter Architecture

## Pipeline

`rewriter.rewrite(source, filename)`:
1. `parser.parse(source, filename)` → AST + errors + the token array. The parser owns the lex (`tl.lex` inside `parse`); while parsing it deletes each discarded statement `;` from that array at the moment it consumes it, moving the `;`'s comments to the following token (see Comment Model), and returns the mutated array. `token_stream.from_tokens(tokens)` then builds the lossless stream at the callsite — stream and node token indices are aligned by identity: both wrap the same array, after mutation. One lex per side (the output's parse-check and audit share a second one).
2. Source ctx: `source.Text`, `ast_traversal.collect_block_ranges`, `source.collect_fmt_off_regions`.
3. `block_doc.make_context()` → `RenderContext` (carries the token stream and the `CommentSlots` reader; renderers read comments through `ctx.slots`).
4. `blank_lines.mark`: recompute `blank_line_before` on container children from the token stream.
5. `require_sort.sort_top_level_requires`: in-place reorder of contiguous top-level `local ... = require(...)`. Stops at first non-require / fmt:off. Returns a per-node leading-comment override map (set as `ctx.slots.leading_overrides`) and a floating tail.
6. If structural render allowed: `block_doc.render_block(ctx, block, …, require_sort_tail)` → `stmt_doc` → `expr_doc`/`table_doc`/`type_doc`, finalized via `doc.Doc:render`.

If blocked or render fails: keep original source.

## Modules

- `rewriter.tl` — pipeline.
- `ast.tl` — the AST data contract: `Node`, the `Type` hierarchy, `Comment`, `InlineSlot`, and the token-index slots (`tok_first`/`tok_last`/`slot_tok`) the renderer reads comments through. Renderers depend on this, not on the parser; any parser producing `ast.Node` trees can drive them.
- `parser.tl` — typed Teal parser producing `ast.Node` trees.
- `token_stream.tl` — lossless token backbone. `from_tokens(tokens)` takes the token array `parser.parse` returns and splits the gap-before comments into per-token `leading_trivia` (own-line before) / `trailing_trivia` (same-line after). It returns a `Stream`: the token array plus the consume ledger (`mark_consumed`/`is_consumed`/`consume_slice`/`take_unconsumed`) recording by source position which trivia the render has already emitted. The array part is **index-aligned with the parser's token indices by identity** (one `Token` per entry of the same array, in order), so a node's `tok_first`/`tok_last` index straight into it. Its structural no-drop guarantee is that every comment the lexer reports lands in exactly one token's trivia. Nothing tests the stream directly: a comment this layer loses is a comment the output loses, which every `helpers.check`/`helpers.format` case and the `comment_audit` backstop catch as changed output. Positions are lines and columns throughout; whitespace is never stored (the Doc IR re-derives it), and fmt:off slicing works off source lines, not byte offsets.
- `ast_traversal.tl` — AST walks + block ranges.
- `source.tl` — `Text`, `Range`, `Region/Regions`, fmt-region collection.
- `render_context.tl` — `RenderContext` + ctor: the per-render wiring bag carrying the render callbacks (breaks circular deps) and the shared render inputs (`tokens`, `source_lines`, `fmt_off_regions`, `slots`).
- `comment_slots.tl` — `CommentSlots`: the accessor suite mapping a node's token-ownership stamps to the comments each render slot emits, marking every read on the stream's consume ledger. The ledger itself lives on the `Stream`.
- `doc.tl` — doc algebra + renderer.
- `block_doc.tl` — block rendering, statement glue, `make_context()` factory.
- `stmt_doc.tl` / `expr_doc.tl` / `table_doc.tl` — per-kind rendering.
- `delimited_list_doc.tl` — comma-separated, comment-threaded list rendering. `render_items` is the framing-agnostic item loop (driven by an `ItemRenderSpec`); `render_parens` frames it with `(…)`. Shared by call argument lists + parameter lists (`expr_doc`/`type_doc` via `render_parens`) and table constructors (`table_doc` via `render_items`).
- `render_builders.tl` — shared doc helpers.
- `require_sort.tl` — top-level require reorder.
- `blank_lines.tl` — recomputes `blank_line_before` on container children from the token stream (statement lists, table literals, call-argument lists, enum items, record field entries).
- `comment_audit.tl` — comment-preservation backstop. `diff(before_tokens, after_tokens)` compares the two token streams built from each side's parse (one lex per side, the input's shared with the render), keys every comment by its whitespace-normalized text, and reports any the formatter dropped or duplicated; `rewriter` safe-skips on any problem, naming the offending comment.

Dep direction: `rewriter` → render → doc builders → doc core. `rewriter` is the only module requiring `parser`; everything downstream depends on `ast` only.

## RenderContext

Breaks `block_doc` ↔ `stmt_doc` ↔ `expr_doc` ↔ `table_doc` cycle via callbacks: `render_expr(node)` and `render_block(node)`. `block_doc.make_context()` wires impls (closures over `self`) and builds the `CommentSlots` reader exposed as `ctx.slots`; created once in `rewriter.rewrite`, threaded through render + require-sort.

## render_builders Helpers

(Shared across `block_doc`/`stmt_doc`/`expr_doc`/`table_doc`.)

- `trailing_comment_doc(comments)` — joins a comment list as text (` <c1> <c2>…`), else empty. Caller supplies the list from `ctx.slots:trailing_comments` / `ctx.slots:statement_trailing_comments`.
- `head_trivia_doc(comments)` — emits a comment list inline (the `"head"` slot, read by the caller via `ctx.slots:opener_comments(node, "head")`).
- `with_leading_inline_trivia(comments, prefix, content)` — threads a comment list (the `"after_opener"` slot, via `ctx.slots:opener_comments(node, "after_opener")`) on the prefix line, breaks before `content`.
- `append_comment_docs(parts, comments, line_before)` — own-line leading comments with `hardline` separators; returns updated `line_before`.
- `any_items_have_comments(ctx, items, absorb_first_opener)` — any item has leading (`ctx.slots:item_leading_comments`) or trailing (`ctx.slots:trailing_comments`). Drives force-wrap.
- `item_line_doc(force_wrap)` — `hardline` if force-wrapping, else `softline`.
- `append_lines_pre_node(node, line_before, line_from_before?)` — separator + extra `hardline` for `blank_line_before`. Accepts `ast.Node` or `ast.FieldEntry`.
- `build_grouped_comma_items_doc(item_docs)` — comma list whose commas all give at once: one line, or one item per line. The second stage of every two-stage break (delimited sequences, `=` value lists).
- `exp_list_can_break(exps)` — more than one item and no threaded comments. Guards both list builders below.
- `build_exp_list_doc(ctx, exps)` — comma-joined expression list; threads item comments when present, otherwise `build_grouped_comma_items_doc`. Callers frame it: `inline_stmt_doc` wraps it with `wrap_keyword_before` so a long `=` list drops below the `=` before its commas give.
- `build_return_exp_list_doc(ctx, exps)` — same list, but the first value stays on the `return` line and only the continuations indent. Return-only: a `return` has no operator to its left to give first. Delegates to `build_exp_list_doc` for the comment-threaded path.
- `build_comma_separated_docs(docs)` / `build_comma_separated_with_trailing(...)` — the comma-joining primitives the list builders above sit on.

## Comment Model

The model is layered; each layer is simpler and broader than the one before it:

1. **Lossless token stream** — the lexer leaves every comment on a token; `token_stream` splits each into the previous token's `trailing_trivia` (same-line) or the following token's `leading_trivia` (own-line). No attachment pass, no node-level comment slots.
2. **A small set of kept slots** — `CommentSlots` accessors that read a specific token's trivia for the common real-code placements (listed below). Ownership is the renderer's structural context: when `stmt_doc` emits an `if`, it walks `if` → cond → `then` → body → `end`, so "between the last body statement and `end`" is unambiguously the `end` token's leading trivia. Every accessor return funnels through `consume()`, which records each comment by source position on the stream's ledger.
3. **The per-statement sweep** — the primary mechanism for everything else. After a statement renders, `block_doc` calls `ctx.slots:unconsumed_comments_in_span(stmt)`: any comment in the statement's token span that no slot consumed (and no fmt-off region froze) is relocated to the statement's own-line leading — the only idempotent home for arbitrary strays (relocated comments re-lex as leading comments and read back the same way; own lines never join). Pathological placements (`local --[[c]] x`, `( --[[c]] e)`, comments buried in type syntax) all resolve here instead of each having a dedicated accessor.
4. **Audit + strict mode** — `comment_audit.diff` compares the per-comment multiset of input vs output; any drop or duplicate safe-skips the file (status `failed`, source verbatim, offending comment named). `rewriter` logs every never-consumed comment at info level before the audit, and with `FormatterOptions.strict_comments` (test-only; spec helpers set it) an audit failure raises instead of safe-skipping, so a regression cannot hide behind a status assertion.

A node addresses its tokens through the index slots the parser stamps: `tok_first`/`tok_last` (the node's edge tokens) and `slot_tok[slot]` (the opener token feeding a positional slot). These index straight into `token_stream` (one Token per lexed token, same order). The parser is the **single grammar authority**: it emits grammar exclusively as token ownership stamped on nodes, and the render layer decides layout from those stamps alone — it never classifies a token, only trivia *shape* (`trivia_doc.is_block_comment`). `token_stream` is purely lexical and holds no grammar.

**Separator ownership** (the full_moon `Punctuated` model: a separator has no role of its own, it belongs to a node). All stamps are optional integer indices into the shared token array, on `ast.HasTokenSpan`:

| Stamp | Owner | Meaning |
| --- | --- | --- |
| `tok_first` / `tok_last` | any node | edge tokens (node extent) |
| `slot_tok[InlineSlot]` | construct | opener token feeding a positional slot |
| `tok_op` | expression | operator / `.`/`:` member / `as`/`is` token |
| `tok_sep` | list item | my following list separator (`,` / table `;` / `|`); it donates its same-line trailing trivia to me |
| `tok_bound` | pre-boundary node | the token right after me that ends my same-line trivia claim without donating any of its own: the parent construct's `=`/`:`, or a table constructor's `}` (its last item sits in a separator position whether or not the source filled it) |

Discarded statement `;` tokens need no stamp: they render nothing, so the parser **deletes them from the token array at the moment it consumes them**, moving any comments parked on the `;` to the following token (the StyLua model — a removed token donates its trivia to a neighbor). `token_stream.from_tokens` then splits those comments against the surviving neighbors as usual: same-line ones become the previous token's trailing, own-line ones the next token's leading. After the parse the renderer's leading read is just "my first token's leading trivia" and statement gaps hold nothing — no scanning, no boundary arguments. One geometric trace remains: a return's consumed `;` leaves its line in `node.yend`, so an fmt:off region anchored only by the `;` line still freezes the statement (frozen output is raw source lines, which preserves the `;` bytes).

Two enforcement points keep this closed:
- `parser.check_separator_ownership(root, tokens)`, run under `strict_comments` (spec helpers + fuzz enable it): every separator-shaped token in a parsed file must be owned by exactly one stamp; an unowned one raises with its position. A missed consumption site fails the whole suite, position-exact.
- `make lint` greps the render-layer files for `.text ==`/`.text ~=` and fails on any hit, so token-text classification cannot creep back in.

**CommentSlots accessors** (all return `{Comment}`, computed from the token stream, marked consumed on read):
- `leading_comments(node)` — own-line comments leading a statement: its `tok_first` leading trivia (any discarded-`;` trivia was already moved there by the parser's deletion). Consults `leading_overrides` first (see require_sort).
- `trailing_comments(node)` / `statement_trailing_comments(node)` — same-line comments after a node's last content token, routed by the ownership stamps: `tok_sep` donates the separator's line comments to the item, `tok_bound` ends the claim at line comments (a block comment right before the boundary is left for the sweep), no stamp takes the run whole. Forces a break in surrounding layout.
- `dangling_comments(block)` / `container_dangling_comments(node, empty?)` — own-line comments before a block's or container's closer (`tok_last`, which lands exactly on the `end`/`}`/`)`, or EOF for the top-level block; the container variant also picks up the opener-trailing comment of an empty container).
- `item_leading_comments(item, prev, absorb_opener?)` — own-line comments leading a list/table/enum/field item: its leading run plus a comment stranded on the separator in the sibling gap. `prev` is the previous item, passed by the iterating caller (nil for the first item) — the gap between siblings is the caller's knowledge, never scanned for; with `absorb_opener`, the first item also takes the opener's same-line comment.
- `opener_comments(node, slot)` — the opener's same-line trivia for an opener-anchored slot (`"head"`, `"after_opener"`), via `slot_tok[slot]`.
- `pre_opener_block_comments(node, slot)` — positional twin of `opener_comments`: the same-line trivia just *before* the slot's opener token (the `=` of an assignment/declaration), kept inline in place, but only when the whole run is single-line block comments; otherwise returns empty without consuming and the run falls to `trailing_comments`/the sweep.
- `pre_opener_trailing_comments(node, slot, item)` — the line-comment counterpart: `item`'s own `trailing_comments` run, but only when `item.tok_bound` *is* the slot's opener token. The run is emitted after the whole lhs, so an item bounded by anything else (a declaration's `:`) would have its comment land at a token the next parse reads differently; declining leaves it to the sweep.
- `op_leading_comments(node)` / `op_trailing_comments(node)` — the one-token gap around a binary/cast operator. Own-line forces a chain break; same-line stays inline.
- `unconsumed_comments_in_span(node)` — the sweep (layer 3): unpacks the node's token span and delegates to `Stream:take_unconsumed`, which returns every trivium in the window not yet consumed and not frozen by fmt-off, marking each consumed. (`rewriter`'s unconsumed-comment log is the same stream call over the whole array.)
- `Stream:consume_slice(first_line, start_col, last_line, cut_col?)` — on the stream, not the context, and not a read: marks the comments a frozen (fmt-off) run just emitted raw as consumed, so an enclosing statement's sweep does not relocate a duplicate copy.
- `trailing_extent(node)` / `leading_extent(item, prev, absorb_opener?)` — geometry, not comments: the last line a node's same-line trailing run or its leading run reaches, read **without consuming**. fmt-off region math and blank-line marking both need the line and neither emits, so consuming here would hide a comment from the sweep that nothing then prints.

`blank_line_before` on a `Comment` (own-line runs) and on a container child (set by `blank_lines.mark`) preserves a single source blank line. For comments it is measured against the actual source lines (`blank_line_between` in comment_slots), not line-number arithmetic: a line that held only a discarded `;` sits inside a token gap without being blank.

**Where each slot is emitted** — the inverse index, so "where is construct X's comment handled?" resolves to a file. Regenerate by grepping `:<accessor>(`. `render_builders` is the shared helper hub (force-wrap probes, list emit loops), not a construct renderer, so it is omitted; `blank_lines`/`rewriter` only *read* some slots (blank marking, require_sort overrides), shown in parentheses.

| Accessor | Emitting module(s) |
| --- | --- |
| `leading_comments` | block_doc · (rewriter) |
| `statement_trailing_comments` | block_doc |
| `unconsumed_comments_in_span` | block_doc |
| `trailing_comments` | block_doc, stmt_doc, table_doc, delimited_list_doc, inline_stmt_doc |
| `dangling_comments` | block_doc, stmt_doc |
| `container_dangling_comments` | stmt_doc, table_doc, delimited_list_doc |
| `item_leading_comments` | stmt_doc, delimited_list_doc |
| `opener_comments` | stmt_doc, function_doc, type_doc, table_doc, delimited_list_doc, inline_stmt_doc |
| `pre_opener_block_comments` | inline_stmt_doc |
| `pre_opener_trailing_comments` | inline_stmt_doc |
| `op_leading_comments` / `op_trailing_comments` | expr_doc |

Coverage is enforced, not just documented: `comment_matrix_spec.lua` pins per-construct comment placement (each case runs through `rewriter` and so through the audit), and `comment_audit` (Design note) fails any change where a renderer stops emitting a slot, naming the dropped comment.

**Consume-without-emit is the hazard to watch.** An accessor read marks its comments consumed; if the caller then conditionally discards the result, the comment is invisible to the sweep and the audit safe-skips the file. Read a slot only on the path that emits it (see `render_declaration_doc`, which reads the last variable's trailing comments only when an initializer follows).

**`InlineSlot`** (`"head"`, `"after_opener"`) names the opener-anchored `slot_tok` entries the parser stamps. An op/field/method/cast node carries a `tok_op` index (also stamped by the parser, like `tok_first`/`tok_last`) marking the operator, `.`/`:`, or `as`/`is` token; `op_leading_comments`/`op_trailing_comments` read the gaps on either side of it. Every other placement is unstamped and falls to the sweep.

**`trivia_doc.tl` helpers:**
- `is_block_comment(text)` / `comment_doc(comment)` — classify block vs line; a line comment doc carries `break_parent` so a flat group cannot fold the next statement onto it.
- `partition(trivia, anchor_line)` → `(same_line_head, own_line_tail)`.
- `append_inline(parts, trivia)` — `" --[[c]]"` per entry, leading space.
- `append_inline_joined(parts, trivia)` — single-space separator, no leading space (use after openers).
- `emit_transition(parts, trivia, anchor_line, next_doc, plain_separator, inline_block?)` — operator-position boundary; own-line trivia forces break before `next_doc`, else emits `plain_separator` + `next_doc` flat.

### Sweep relocation policy

A comment in a kept slot renders where it was written. Everything else — a block comment wedged into a keyword run (`local --[[c]] x`), inside parentheses (`( --[[c]] e)`), inside type syntax (`Map<--[[k]] string, integer>`), an own-line comment mid-annotation — relocates to the statement's own-line leading. Real code essentially never writes these placements (fuzzing does); one mechanism that provably keeps them beats a dedicated keep-in-place accessor per gap. Known accepted consequence: a comment buried in a record body's *field type* relocates to the whole record statement's leading, because fields are not statements and the sweep is per-statement.

### Design note

This replaced parse-time attachment: the parser drained the comments off each token as it consumed it and stored them on the spanning node, in three structural slots (`leading`/`trailing`/`dangling`) plus a positional `inline_trivia` map. Every grammar site that could hold a comment needed its own drain call, so a comment in a position no site had a slot for — inside a cast, between header keywords, in a call's parentheses, buried in type syntax, on a discarded `;` — belonged to nobody and was dropped. The old whole-file comment count caught that only as a safe skip, and a drop paired with a duplicate cancelled out entirely.

Attachment had to decide ownership while parsing, with no view of how the node would render. A *renderer* has full structural context, so letting each renderer read its tokens' trivia at the point it emits that token removes the ownership question instead of answering it once per grammar site. The note this replaces argued that moving trivia onto tokens "wouldn't reduce renderer complexity … not planned without a concrete forcing function": the forcing function was the dropped comments.

**Why this is drop-proof.** Every comment lives on a token at lex time, and `token_stream` puts each one the lexer reports in exactly one token's leading or trailing trivia, so none reaches the renderer unattached. Every emit funnels through `consume()`, so "was this comment rendered?" is a set lookup, and the per-statement sweep turns the remainder into relocated leading comments instead of drops — a comment can now only vanish through consume-without-emit (a read whose result is conditionally discarded), a *local, per-call-site, testable* bug. `comment_audit.diff` in `rewriter.tl` is the backstop: it compares the per-comment multiset (keyed by whitespace-normalized text) of input vs output and rejects any drop or duplicate as a safe-skip (status `failed`, source returned verbatim), naming the offending comment in `failure_reason`. Because it is per-comment, it also catches a net-zero drop+duplicate the older lex-count net missed. `rewriter` additionally logs each never-consumed comment at info level (the accepted-fallback path must not log at error), and `strict_comments` turns an audit failure into a raise under test.

Known gap: a bare gap `;` inside an `fmt:off` region that no statement's line-range reaches (a `;` line between statements, not a return's) is not frozen — the parser deleted the token and no node anchors its line — so its byte is dropped from the region. Count-preserving for comments (the `;`'s comments moved to a surviving token); faithful freezing of node-less lines is future work. A return's own `;` *is* frozen, via the line it leaves in `node.yend`.

### Why this model (alternatives considered)

The trivia-on-tokens backbone matches StyLua/full_moon, dprint, and Roslyn; it is the right long-term choice. The decisive difference is *who emits a comment by default*. StyLua/full_moon and rustfmt **default-keep**: they print the whole concrete tree (StyLua) or copy every source byte between nodes with a linear `last_pos` cursor (rustfmt), so a comment no formatting rule touches still survives. Cerulean's renderers *pull* trivia per emit-site, which on its own would **default-drop**; the consumed set plus the per-statement sweep converts that to **default-relocate** — a comment no slot pulls still appears, as statement leading. That is Prettier's per-comment `printed` flag (`ensureAllCommentsPrinted`) in spirit: `consume()` marks at every emit site, the sweep and the info-level unconsumed log are the guards against unmarked emits, and the output-diff audit remains the outer guarantee.

Two tempting alternatives are deliberately *not* taken. **Default-keep** does not transfer: cerulean emits a structural Doc IR out of source order (require_sort reorders, grouping reflows) and keeps no token→output-location map, so keeping an unclaimed comment *in place* would have to infer its home from flat position — exactly the positional ownership-guessing the deleted `comment_attachment.tl` router did; relocation to statement leading sidesteps the inference. **Centralized attachment** (Prettier-style `enclosingNode`/`precedingNode`/`followingNode`) *is* that deleted router; the cost was the guessing, which structural reads remove. On safety cerulean exceeds StyLua, which has no per-comment guarantee (only an opt-in, coarse `--verify`): `comment_audit` is always-on and the file safe-skips to verbatim rather than emit a dropped comment.

## require_sort Comment Semantics

require_sort reorders the require nodes in place and returns where their comments go, because reordering moves comments contrary to source position (which the token reads key on). It sources each require's leading comments from the token stream (via the `ctx.slots:leading_comments` reader the rewriter passes in) and returns a per-node override map, set as `ctx.slots.leading_overrides`; the renderer reads that placement for the reordered nodes instead of the tokens. Two kinds:
- **Attached**: immediately before require (no gap). Moves with require; `blank_line_before` cleared.
- **Floating**: blank-line gap before require, or before first require. Pinned to top of sorted block (or, when a statement follows the group, folded into that statement's override).

First require's comments: if none floating, attached are treated as module docs and also pinned. require_sort runs after `blank_lines.mark`, so it overrides the blank flags on the requires it touches.

## Parser contract

What any parser (incl. future replacement) must supply. Renderers depend only on `ast.tl`; `rewriter.tl` sole consumer of `parser.tl`.

**API.** `parser.parse(input, filename) → ast.Node, {parser.Error}, {tl.Token}`. The parser owns the lex; the returned token array is `tl.lex`'s output with the discarded statement `;` tokens removed (their comments moved to the following token). Callers build the lossless stream from it (`token_stream.from_tokens`), so node token indices address it by identity.
- Fail-fast: stop at first syntax error; error list ≤1 entry (`filename`, `y`, `x`, `msg`). On error rewriter leaves source unchanged.
- Grammar only: anything grammatical parses, incl. Teal-invalid code (unknown attributes, redeclared fields, optional-arg order). Semantics belong to `tl check`.
- Comment preservation is owned by `comment_audit.diff` (per-comment text multiset, see Design note), not the parser.

**Positions.** `y`/`x` 1-indexed (`Where` interface). These are **already token-derived by construction** — `new_node` copies `y`/`x`/`tk`/`tok_first` straight off the token at the node's start index, and `end_at`/`verify_end` set `yend`/`tok_last` off the closing token. There is no separate "manual position stamping" layer to delete or re-derive; reworking positions to compute post-hoc from `tok_first`/`tok_last` would be a lateral refactor that only risks drift. `node.yend` guaranteed on statements (set in `parse_statements`) + expression nodes (set before operands wrapped into op nodes); renderers read directly, no `yend or y` fallback. Other kinds (e.g. `if_block` with empty body) may lack `yend`; fallback only there. `close_x` = closing keyword's start column on block statements; nil at top level (EOF not closer).

**Token fidelity.** `node.tk` = verbatim source text. String nodes carry `tk` (with quotes), `conststr` (unquoted value), `is_longstring`. Op nodes carry `op.op`, `op.prec`, `op.y`: expression rendering + trivia placement need all three.

**Trivia.** `Comment.text` includes delimiters (`--`, `--[[ ]]`). The grammar does *not* attach comments; it leaves each on its token, and the renderer reads them off the index-aligned `token_stream` at its emit points (see Comment Model). The parser's comment-related duties are exactly two: stamp the token-ownership indices (`tok_first`/`tok_last`/`slot_tok`/`tok_op`/`tok_sep`/`tok_bound`) the renderer routes by, and delete each discarded statement `;` from the token array at its consumption site, moving the `;`'s comments to the following token. `check_separator_ownership` (strict mode) verifies the stamps are complete.

**Token spans.** Every `Node` / `Type` / `FieldEntry` carries `tok_first` / `tok_last` — integer indices into the token array bounding the source it owns, index-aligned with `token_stream` (see Modules). These are **renderer-facing**: the renderer reads a node's leading comments at `tok_first`'s leading trivia and its trailing at `tok_last`'s trailing trivia, so a node whose span includes a token it does not own (a "phantom span") would read a neighbouring comment. For a delimited construct `tok_last` lands exactly on the closer (`end`/`until`/`else`/`elseif`/`}`/`)`), so `dangling_comments` reads that token's leading trivia with no guesswork.

**Index alignment invariant.** The renderer's stream is built *from the token array the parse returns*, so alignment is by identity, not by parallel construction — which is what makes the parser's one mutation (deleting discarded statement `;` tokens) safe: every index the renderer sees was stamped against the already-compacted array. Deletion happens at the parse frontier, so stamps taken before it point at or before the removal point, and a rolled-back trial parse re-walks the same compacted array (a statement `;` never re-parses as anything else). No synthetic tokens are ever inserted (the old synthetic `;` for the `f()\n(...)` cross-line-call ambiguity is gone: ending the suffix chain already marks the statement boundary). Identity alignment is what lets the accessors trust `tok_first`/`tok_last`/`slot_tok` directly, instead of re-deriving structure from token text (no closer-keyword table, no leftmost-token walk-back).

**Conformance.** `make ab-snapshot` pins per-file status + output over `fuzz/corpus/`; `make ab-diff` reruns, reports drift. Snapshot before parser change, diff after; review every drift, then retake snapshot.
