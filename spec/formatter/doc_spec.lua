require("tl").loader()

local assert = require("luassert")
local doc = require("formatter.doc")

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

    it("flushes line_suffix content before hardline", function()
        local tree = doc.concat({
            doc.text("value"),
            doc.line_suffix(doc.text(" -- keep")),
            doc.hardline(),
            doc.text("next"),
        })

        assert.same("value -- keep\nnext", render(tree, 88))
    end)

    it("flushes line_suffix content at explicit boundary", function()
        local tree = doc.concat({
            doc.text("{"),
            doc.line_suffix(doc.text(" -- trailing")),
            doc.line_suffix_boundary(),
            doc.text("}"),
        })

        assert.same("{ -- trailing}", render(tree, 88))
    end)

    it("flushes pending line_suffix at end of document", function()
        local tree = doc.concat({
            doc.text("value"),
            doc.line_suffix(doc.text(" -- keep")),
        })

        assert.same("value -- keep", render(tree, 88))
    end)
end)

describe("formatter doc close node", function()
    it("appends close text inline when the group renders flat", function()
        local tree = doc.group(doc.concat({
            doc.text("function()"),
            doc.close("end"),
        }))

        assert.same("function()end", render(tree, 88))
    end)

    it("accounts for close text width when deciding if the group fits flat", function()
        -- "function()end" is 13 chars
        local tree = doc.group(doc.concat({
            doc.text("function()"),
            doc.close("end"),
        }))

        assert.same("function()end", render(tree, 13))
        assert.same("function()\nend", render(tree, 12))
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
end)
