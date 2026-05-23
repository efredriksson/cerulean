require("tl").loader()

local assert = require("luassert")
local doc = require("cerulean.doc")

local function render(root, width)
    return root:render(width or 88, 4)
end

describe("formatter doc primitives", function()
    it("renders line as space when group fits and newline when it does not", function()
        local tree = doc.group(doc.concat({
            doc.text("alpha"),
            doc.line(),
            doc.text("beta"),
        }))

        assert.same("alpha beta", render(tree, 88))
        assert.same("alpha\nbeta", render(tree, 6))
    end)

    it("renders softline as empty string when group fits", function()
        local tree = doc.group(doc.concat({
            doc.text("alpha"),
            doc.softline(),
            doc.text("beta"),
        }))

        assert.same("alphabeta", render(tree, 88))
        assert.same("alpha\nbeta", render(tree, 6))
    end)

    it("renders if_break branches based on current group break state", function()
        local tagged_group = doc.group_ref()
        local tree = tagged_group:group(doc.concat({
            doc.text("alpha"),
            doc.line(),
            tagged_group:if_break(doc.text("[broken]"), doc.text("[flat]")),
            doc.text("beta"),
        }))

        assert.same("alpha [flat]beta", render(tree, 88))
        assert.same("alpha\n[broken]beta", render(tree, 6))
    end)

    it("supports targeting another group by id in if_break", function()
        local tagged_group = doc.group_ref()
        local tree = doc.concat({
            tagged_group:group(doc.concat({
                doc.text("alpha"),
                doc.line(),
                doc.text("beta"),
            })),
            doc.hardline(),
            tagged_group:if_break(doc.text("outer-broken"), doc.text("outer-flat")),
        })

        assert.same("alpha beta\nouter-flat", render(tree, 88))
        assert.same("alpha\nbeta\nouter-broken", render(tree, 6))
    end)

    it("keeps flat if_break branch for unbreakable target groups that only overflow width", function()
        local tagged_group = doc.group_ref()
        local tree = doc.concat({
            tagged_group:group(doc.text("supercalifragilisticexpialidocious")),
            tagged_group:if_break(doc.text("[broken]"), doc.text("[flat]")),
        })

        assert.same("supercalifragilisticexpialidocious[flat]", render(tree, 6))
    end)

    it("break_parent forces the containing group to break", function()
        local tagged_group = doc.group_ref()
        local tree = tagged_group:group(doc.concat({
            doc.text("alpha"),
            doc.line(),
            doc.text("beta"),
            doc.break_parent(),
            tagged_group:if_break(doc.text(" [broken]"), doc.text(" [flat]")),
        }))

        assert.same("alpha\nbeta [broken]", render(tree, 88))
    end)
end)

describe("formatter doc close node", function()
    it("appends close text inline when the group renders flat", function()
        local tree = doc.group(doc.concat({
            doc.text("function()"),
            doc.close("end"),
        }))

        assert.same("function() end", render(tree, 88))
    end)

    it("accounts for close text width when deciding if the group fits flat", function()
        -- "function()end" is 13 chars
        local tree = doc.group(doc.concat({
            doc.text("function()"),
            doc.close("end"),
        }))

        assert.same("function() end", render(tree, 14))
        assert.same("function()\nend", render(tree, 13))
    end)

    it("places close text on a new line at the enclosing indent when broken", function()
        local tree = doc.group(doc.concat({
            doc.text("function()"),
            doc.indent(doc.concat({
                doc.line(),
                doc.text("body"),
            })),
            doc.close("end"),
        }))

        assert.same("function()\n    body\nend", render(tree, 10))
    end)
end)

describe("formatter doc trim_lines", function()
    it("adds no space and no line break when the wrapped content is empty in flat mode", function()
        local tree = doc.group(doc.concat({
            doc.text("f()"),
            doc.indent(doc.concat({doc.line(), doc.trim_lines(doc.text(""))})),
            doc.close("end"),
        }))

        assert.same("f() end", render(tree, 88))
    end)

    it("appends a space after content when the group renders flat", function()
        local tree = doc.group(doc.concat({
            doc.text("f()"),
            doc.indent(doc.concat({doc.line(), doc.trim_lines(doc.text("body"))})),
            doc.close("end"),
        }))

        assert.same("f() body end", render(tree, 88))
    end)

    it("breaks the line after content when the group is broken", function()
        local tree = doc.group(doc.concat({
            doc.text("f()"),
            doc.indent(doc.concat({doc.line(), doc.trim_lines(doc.text("body"))})),
            doc.close("end"),
        }))

        assert.same("f()\n    body\nend", render(tree, 10))
    end)

    it("adds no space and no line break when the wrapped content is empty in broken mode", function()
        local tree = doc.group(doc.concat({
            doc.text("f()"),
            doc.indent(doc.concat({doc.line(), doc.trim_lines(doc.text(""))})),
            doc.close("end"),
        }))

        assert.same("f()\nend", render(tree, 5))
    end)

    local function introspect(root)
        return tostring(root)
    end

    it("introspects a text leaf as a quoted literal", function()
        assert.same('"hello"', introspect(doc.text("hello")))
    end)

    it("introspects atomic kinds as bare keywords", function()
        assert.same("hardline", introspect(doc.hardline()))
        assert.same("blankline", introspect(doc.blankline()))
        assert.same("break_parent", introspect(doc.break_parent()))
    end)

    it("introspects line kinds with their flat text", function()
        assert.same('line(" ")', introspect(doc.line()))
        assert.same('line("")', introspect(doc.softline()))
        assert.same('line("; ")', introspect(doc.stmt_sep_line()))
    end)

    it("introspects a concat of texts that fit on one line", function()
        local tree = doc.concat({doc.text("a"), doc.text("b"), doc.text("c")})
        assert.same('[ "a", "b", "c" ]', introspect(tree))
    end)

    it("introspects a concat by breaking after each line-kind child", function()
        local tree = doc.concat({
            doc.text("a"),
            doc.text("b"),
            doc.line(),
            doc.text("c"),
            doc.hardline(),
        })
        assert.same(
            '[ "a", "b", line(" "),\n"c", hardline ]', introspect(tree)
        )
    end)

    it("introspects groups with their id", function()
        local tagged = doc.group_ref()
        local tree = tagged:group(doc.text("x"))
        assert.same(
            "group#" .. tostring(tagged.group_id) .. '[ "x" ]', introspect(tree)
        )
    end)

    it("introspects if_break target ids and both branches", function()
        local tagged = doc.group_ref()
        local tree = tagged:if_break(doc.text("brk"), doc.text("flt"))
        local expected = "if_break#"
            .. tostring(tagged.group_id)
            .. '[ flat="flt", break="brk" ]'
        assert.same(expected, introspect(tree))
    end)

    it("introspects raw lines as quoted children", function()
        assert.same('raw[ "one", "two" ]', introspect(doc.raw({"one", "two"})))
    end)

    it("introspects close with text and flat separator", function()
        assert.same('close(text=")", sep=" ")', introspect(doc.close(")")))
        assert.same('close(text="]", sep="")', introspect(doc.softclose("]")))
    end)

    it("introspects break_text with both branches", function()
        assert.same(
            'break_text(flat="", broken=",")', introspect(doc.if_wrapped(","))
        )
    end)

    it("introspects a group whose inner concat has line-kind children", function()
        local tree = doc.group(doc.concat({
            doc.text("a"), doc.hardline(), doc.text("b"),
        }))
        assert.same(
            'group[ [ "a", hardline,\n"b" ] ]', introspect(tree)
        )
    end)
end)
