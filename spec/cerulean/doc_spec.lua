require("tl").loader()

local doc = require("cerulean.doc")
local helpers = require("spec.cerulean.helpers")

local group_ref = doc.group_ref()

describe("formatter doc primitives", function()
    it("renders line as a space when the group fits", helpers.renders(
        doc.group(doc.concat({
            doc.text("alpha"), doc.line(), doc.text("beta"),
        })), 88,
    [[
        alpha beta
    ]]))

    it("renders line as a newline when the group breaks", helpers.renders(
        doc.group(doc.concat({
            doc.text("alpha"), doc.line(), doc.text("beta"),
        })), 6,
    [[
        alpha
        beta
    ]]))

    it("renders softline as empty when the group fits", helpers.renders(
        doc.group(doc.concat({
            doc.text("alpha"), doc.softline(), doc.text("beta"),
        })), 88,
    [[
        alphabeta
    ]]))

    it("renders softline as a newline when the group breaks", helpers.renders(
        doc.group(doc.concat({
            doc.text("alpha"), doc.softline(), doc.text("beta"),
        })), 6,
    [[
        alpha
        beta
    ]]))

    it("renders the if_break flat branch when its group fits", helpers.renders(
        group_ref:group(doc.concat({
            doc.text("alpha"),
            doc.line(),
            group_ref:if_break(doc.text("[broken]"), doc.text("[flat]")),
            doc.text("beta"),
        })), 88,
    [[
        alpha [flat]beta
    ]]))

    it("renders the if_break break branch when its group breaks", helpers.renders(
        group_ref:group(doc.concat({
            doc.text("alpha"),
            doc.line(),
            group_ref:if_break(doc.text("[broken]"), doc.text("[flat]")),
            doc.text("beta"),
        })), 6,
    [[
        alpha
        [broken]beta
    ]]))

    it("renders the if_break flat branch when its target group fits", helpers.renders(
        doc.concat({
            group_ref:group(doc.concat({
                doc.text("alpha"), doc.line(), doc.text("beta"),
            })),
            doc.hardline(),
            group_ref:if_break(doc.text("outer-broken"), doc.text("outer-flat")),
        }), 88,
    [[
        alpha beta
        outer-flat
    ]]))

    it("renders the if_break break branch when its target group breaks", helpers.renders(
        doc.concat({
            group_ref:group(doc.concat({
                doc.text("alpha"), doc.line(), doc.text("beta"),
            })),
            doc.hardline(),
            group_ref:if_break(doc.text("outer-broken"), doc.text("outer-flat")),
        }), 6,
    [[
        alpha
        beta
        outer-broken
    ]]))

    it("keeps the flat if_break branch for unbreakable groups that overflow width", helpers.renders(
        doc.concat({
            group_ref:group(doc.text("supercalifragilisticexpialidocious")),
            group_ref:if_break(doc.text("[broken]"), doc.text("[flat]")),
        }), 6,
    [[
        supercalifragilisticexpialidocious[flat]
    ]]))

    it("forces the containing group to break when break_parent is present", helpers.renders(
        group_ref:group(doc.concat({
            doc.text("alpha"),
            doc.line(),
            doc.text("beta"),
            doc.break_parent(),
            group_ref:if_break(doc.text(" [broken]"), doc.text(" [flat]")),
        })), 88,
    [[
        alpha
        beta [broken]
    ]]))

    it("forces the containing group to break when a hardline is present", helpers.renders(
        group_ref:group(doc.concat({
            doc.text("alpha"),
            doc.line(),
            doc.text("beta"),
            doc.hardline(),
            doc.text("gamma"),
            group_ref:if_break(doc.text(" [broken]"), doc.text(" [flat]")),
        })), 88,
    [[
        alpha
        beta
        gamma [broken]
    ]]))
end)

describe("formatter doc close node", function()
    it("appends close text inline when the group renders flat", helpers.renders(
        doc.group(doc.concat({
            doc.text("function()"),
            doc.close("end"),
        })), 88,
    [[
        function() end
    ]]))

    it("renders close text inline when its width fits flat", helpers.renders(
        doc.group(doc.concat({
            doc.text("function()"),
            doc.close("end"),
        })), 14,
    [[
        function() end
    ]]))

    it("breaks before close text when its width does not fit flat", helpers.renders(
        doc.group(doc.concat({
            doc.text("function()"),
            doc.close("end"),
        })), 13,
        [[
            function()
            end
        ]]))

    it("places close text on a new line at the enclosing indent when broken", helpers.renders(
        doc.group(doc.concat({
            doc.text("function()"),
            doc.indent(doc.concat({
                doc.line(),
                doc.text("body"),
            })),
            doc.close("end"),
        })), 10,
        [[
            function()
                body
            end
        ]]))
end)

describe("formatter doc trim_lines", function()
    it("adds no space or line break when wrapped content is empty in flat mode", helpers.renders(
        doc.group(doc.concat({
            doc.text("f()"),
            doc.indent(doc.concat({doc.line(), doc.trim_lines(doc.text(""))})),
            doc.close("end"),
        })), 88,
    [[
        f() end
    ]]))

    it("adds no space or line break when wrapped content is empty in broken mode", helpers.renders(
        doc.group(doc.concat({
            doc.text("f()"),
            doc.indent(doc.concat({doc.line(), doc.trim_lines(doc.text(""))})),
            doc.close("end"),
        })), 5,
        [[
            f()
            end
        ]]))

    it("appends a space after content when the group renders flat", helpers.renders(
        doc.group(doc.concat({
            doc.text("f()"),
            doc.indent(doc.concat({doc.line(), doc.trim_lines(doc.text("body"))})),
            doc.close("end"),
        })), 88,
    [[
        f() body end
    ]]))

    it("breaks the line after content when the group is broken", helpers.renders(
        doc.group(doc.concat({
            doc.text("f()"),
            doc.indent(doc.concat({doc.line(), doc.trim_lines(doc.text("body"))})),
            doc.close("end"),
        })), 10,
        [[
            f()
                body
            end
        ]]))
end)

-- Four alternative layouts over two independent break sites, least broken to most
-- broken: neither gives, the left break alone, the inner group alone, both. Shaped like
-- the `as` cast that the primitive exists for.
local function first_fit_layouts()
    local inner = doc.group(doc.concat({
        doc.text("fn("),
        doc.indent_softline(doc.text("argument")),
        doc.softclose(")"),
    }))
    local function left_breaks(inner_state)
        return doc.indent(doc.concat({doc.line(), doc.text("as "), inner_state}))
    end
    local left_stays = doc.concat({doc.text(" as "), inner})
    return doc.concat({
        doc.text("value"),
        doc.first_fit({
            doc.flat(left_stays),
            left_breaks(doc.flat(inner)),
            left_stays,
            left_breaks(inner),
        }),
    })
end

-- A forced break inside a state that is pinned flat: the state cannot render as the
-- single line it was measured as, so it must never be chosen.
local function first_fit_over(forced)
    return doc.concat({
        doc.text("x ="),
        doc.first_fit({
            doc.flat(forced),
            doc.indent(doc.concat({doc.line(), forced})),
        }),
    })
end

describe("formatter doc first_fit", function()
    it("takes the flat state when it fits", helpers.renders(
        first_fit_layouts(), 88,
    [[
        value as fn(argument)
    ]]))

    it("takes the next state when the flat one does not fit", helpers.renders(
        first_fit_layouts(), 20,
    [[
        value
            as fn(argument)
    ]]))

    it("keeps the left side on the line when breaking there does not help", helpers.renders(
        first_fit_layouts(), 15,
    [[
        value as fn(
            argument
        )
    ]]))

    it("falls back to the last state when no state fits", helpers.renders(
        first_fit_layouts(), 10,
    [[
        value
            as fn(
                argument
            )
    ]]))

    it("skips a flat-pinned state holding a grouped forced break", helpers.renders(
        first_fit_over(
            doc.group(doc.concat({doc.text("a"), doc.hardline(), doc.text("b")}))
        ), 88,
    [[
        x =
            a
            b
    ]]))

    it("skips a flat-pinned state holding a bare hardline", helpers.renders(
        first_fit_over(doc.concat({doc.text("a"), doc.hardline(), doc.text("b")})), 88,
    [[
        x =
            a
            b
    ]]))

    it("rejects a fallback state that is pinned flat", function()
        assert.has_error(function()
            doc.first_fit({doc.text("a"), doc.flat(doc.line())})
        end, "first_fit fallback state renders unmeasured")
    end)

    it("rejects a fallback state that cannot break", function()
        assert.has_error(function()
            doc.first_fit({doc.text("a"), doc.text("b")})
        end, "first_fit fallback state cannot break")
    end)

    it("rejects a first_fit with no alternative", function()
        assert.has_error(function()
            doc.first_fit({doc.line()})
        end, "first_fit needs alternative layouts")
    end)
end)

describe("formatter doc introspection", function()
    it("introspects a text leaf as a quoted literal", helpers.introspects(
        doc.text("hello"), '"hello"'
    ))
    it("introspects hardline as a bare keyword", helpers.introspects(
        doc.hardline(), "hardline"
    ))
    it("introspects blankline as a bare keyword", helpers.introspects(
        doc.blankline(), "blankline"
    ))
    it("introspects break_parent as a bare keyword", helpers.introspects(
        doc.break_parent(), "break_parent"
    ))
    it("introspects line with its single-space flat text", helpers.introspects(
        doc.line(), 'line(" ")'
    ))
    it("introspects softline with its empty flat text", helpers.introspects(
        doc.softline(), 'line("")'
    ))
    it("introspects stmt_sep_line with its statement-separator flat text", helpers.introspects(
        doc.stmt_sep_line(), 'line("; ")'
    ))
    it("introspects a concat of texts that fit on one line", helpers.introspects(
        doc.concat({doc.text("a"), doc.text("b"), doc.text("c")}),
        '[ "a", "b", "c" ]'
    ))
    it("introspects a concat by breaking after each line-kind child", helpers.introspects(
        doc.concat({
            doc.text("a"), doc.text("b"), doc.line(), doc.text("c"), doc.hardline(),
        }),
        '[ "a", "b", line(" "),\n"c", hardline ]'
    ))

    local intro_group = doc.group_ref()
    it("introspects a group with its id", helpers.introspects(
        intro_group:group(doc.text("x")),
        "group#" .. intro_group.group_id .. '[ "x" ]'
    ))

    local intro_if_break = doc.group_ref()
    it("introspects if_break with target id and both branches", helpers.introspects(
        intro_if_break:if_break(doc.text("brk"), doc.text("flt")),
        "if_break#" .. intro_if_break.group_id .. '[ flat="flt", break="brk" ]'
    ))
    it("introspects raw lines as quoted children", helpers.introspects(
        doc.raw({"one", "two"}), 'raw[ "one", "two" ]'
    ))
    it("introspects close with text and flat separator", helpers.introspects(
        doc.close(")"), 'close(text=")", sep=" ")'
    ))
    it("introspects softclose with text and empty separator", helpers.introspects(
        doc.softclose("]"), 'close(text="]", sep="")'
    ))
    it("introspects break_text with both branches", helpers.introspects(
        doc.if_wrapped(","), 'break_text(flat="", broken=",")'
    ))
    it("introspects a group whose inner concat has line-kind children", helpers.introspects(
        doc.group(doc.concat({doc.text("a"), doc.hardline(), doc.text("b"),})),
        'group[ [ "a", hardline,\n"b" ] ]'
    ))
end)
