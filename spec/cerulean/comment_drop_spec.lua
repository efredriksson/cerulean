-- Tests for comment-drop bugs found during review of d37bc20.
-- Each test documents a case where the formatter silently drops an inline comment.
-- All tests are expected to FAIL until the corresponding bugs are fixed.
local helpers = require("spec.cerulean.helpers")

describe("comment drop bugs", function()
    -- =========================================================================
    -- logical and/or operators
    --
    -- Root cause: render_op unconditionally routes and/or through
    -- render_logical_chain, which flattens the chain into a group without ever
    -- consulting before_op_comment / after_op_comment on the node.
    -- Fix: skip render_logical_chain when the node carries a comment.
    -- =========================================================================

    it("preserves comment before 'and' operator", helpers.check([[
        local x = a --hmm
            and b
    ]]))

    it("preserves comment after 'and' operator", helpers.check([[
        local x = a and --hmm
            b
    ]]))

    it("preserves comment before 'or' operator", helpers.check([[
        local x = a --hmm
            or b
    ]]))

    it("preserves comment after 'or' operator", helpers.check([[
        local x = a or --hmm
            b
    ]]))

    -- =========================================================================
    -- while condition
    --
    -- Root cause: parse_while does not call get_same_line_comment after
    -- consuming the 'while' keyword, so leading_inline_comment is never set
    -- on the node. render_while_doc therefore never emits the comment.
    -- Fix: add get_same_line_comment capture in parse_while, and handle
    -- leading_inline_comment in render_while_doc (same pattern as if/elseif).
    -- =========================================================================

    it("preserves comment between 'while' and condition", helpers.check([[
        while --hmm
            cond do
        end
    ]]))

    -- =========================================================================
    -- for-numeric range
    --
    -- Root cause: parse_fornum does not call get_same_line_comment after the
    -- '=' token, so leading_inline_comment is never set on the node.
    -- render_fornum_doc therefore never emits the comment.
    -- Fix: add get_same_line_comment capture in parse_fornum, and handle
    -- leading_inline_comment in the fornum header construction.
    -- =========================================================================

    it("preserves comment between 'for =' and range", helpers.check([[
        for i = --hmm
            1, 10 do
        end
    ]]))

    -- =========================================================================
    -- for-in iterator expression
    --
    -- Root cause: parse_forin does not call get_same_line_comment after the
    -- 'in' keyword, so leading_inline_comment is never set on the node.
    -- render_forin_doc therefore never emits the comment.
    -- Fix: add get_same_line_comment capture in parse_forin, and handle
    -- leading_inline_comment when rendering the iterator expression list.
    -- =========================================================================

    it("preserves comment between 'in' and iterator", helpers.check([[
        for k in --hmm
            iter do
        end
    ]]))

    -- =========================================================================
    -- repeat..until condition
    --
    -- Two bugs in this case:
    -- (1) The comment after 'until' is dropped entirely.
    -- (2) An extra blank line is inserted between 'repeat' and 'until' even
    --     when the body is empty.
    --
    -- Root cause for (1): parse_repeat does not call get_same_line_comment
    -- after consuming 'until', so leading_inline_comment is never set.
    -- render_repeat_doc therefore never emits the comment.
    -- Root cause for (2): not yet pinpointed; likely in block_with_indent or
    -- the empty-body doc emitting a spurious softline/hardline.
    -- Fix: capture leading_inline_comment in parse_repeat; investigate and
    -- remove the spurious blank line.
    -- =========================================================================

    it("preserves comment between 'until' and condition", helpers.check([[
        repeat
        until --hmm
            cond
    ]]))

    -- =========================================================================
    -- table short-key initializer
    --
    -- Root cause: parse_table_item does not call get_same_line_comment after
    -- the '=' token in the short-key path, so leading_inline_comment is never
    -- set on the item node. build_table_item_text therefore never emits it.
    -- Fix: add get_same_line_comment capture in parse_table_item after '=',
    -- and handle leading_inline_comment in build_table_item_text.
    -- =========================================================================

    it("preserves comment between table key '=' and value", helpers.check([[
        local t = {
            key = --hmm
                value,
        }
    ]]))

    -- =========================================================================
    -- trailing comment in comma-separated expression list (assignment RHS)
    --
    -- Root cause: parse_assignment_expression_list captures leading_inline_comment
    -- only for the first expression (the comment right after '='). It does not
    -- capture trailing_comment on intermediate expressions when a comma follows
    -- on the same line as the comment.
    -- Fix: after parsing each expression (except the last), call
    -- get_same_line_comment on the next token if a comma follows, attaching
    -- the result as trailing_comment on the expression. Also update
    -- render_assignment_doc to use a comment-aware exp list renderer.
    -- =========================================================================

    it("preserves trailing comment after first exp in assignment list", helpers.check([[
        a, b = 1, --hmm
            2
    ]]))

    -- =========================================================================
    -- trailing comment in comma-separated expression list (return)
    --
    -- Root cause: parse_list (used for return expression lists) does not capture
    -- trailing_comment on list items when a comma follows on the same line as
    -- the comment. render_return_doc uses build_mapped_comma_separated_docs which
    -- has no comment-aware path.
    -- Fix: capture trailing_comment in parse_list for return expressions, and
    -- update render_return_doc to use a comment-aware exp list renderer.
    -- =========================================================================

    it("preserves trailing comment after first exp in return list", helpers.check([[
        local function f()
            return a, --hmm
                b
        end
    ]]))
end)
