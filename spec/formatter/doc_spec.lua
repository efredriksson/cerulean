require("tl").loader()

local assert = require("luassert")
local doc = require("formatter.doc")

local function render(root, width, force_break)
    local lines = root:render(width or 88, 0, 0, force_break ~= false)
    return table.concat(lines, "\n")
end

describe("formatter doc primitives", function()
    it("renders line as space when group fits and newline when it does not", function()
        local tree = doc.group(doc.concat({
            doc.text("alpha"),
            doc.line(" "),
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
            doc.line(" "),
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
                doc.line(" "),
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
            doc.line(" "),
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
