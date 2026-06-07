require("tl").loader()

local parser = require("cerulean.parser")
local assert = require("luassert")

local function comment_count(src)
    local _, _, _, count = parser.parse(src, "t.tl")
    return count
end

describe("parser.parse comment count", function()

    it("returns 0 when there are no comments", function()
        assert.equal(0, comment_count("local x = 1\n"))
    end)

    it("counts line and block comments", function()
        assert.equal(3, comment_count("-- a\nlocal x = 1 -- b\n--[[ c ]]\n"))
    end)

    it("counts a multi-line block comment as one", function()
        assert.equal(1, comment_count("--[[ one\ntwo\nthree ]]\nlocal x = 1\n"))
    end)

    it("counts a trailing comment in a file with no final newline", function()
        assert.equal(1, comment_count("local x = 1 -- z"))
    end)

end)
