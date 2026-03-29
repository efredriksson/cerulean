require("tl").loader()
local blocks = require("formatter.blocks")

describe("blocks.parse", function()
    it("finds a simple function block", function()
        local source = [[
            local function foo()
                return 1
            end
        ]]
        local result, errs = blocks.parse(source, "test.tl")
        assert.are.equal(0, #errs)
        assert.are.equal(1, #result)
        assert.are.equal(1, result[1].open_line)
        assert.are.equal(3, result[1].close_line)
    end)

    it("finds nested function blocks", function()
        local source = [[
            local function outer()
                local function inner()
                    return 1
                end
                return inner
            end
        ]]
        local result, errs = blocks.parse(source, "test.tl")
        assert.are.equal(0, #errs)
        assert.are.equal(2, #result)
    end)

    it("finds an if block", function()
        local source = [[
            if x then
                y = 1
            end
        ]]
        local result, errs = blocks.parse(source, "test.tl")
        assert.are.equal(0, #errs)
        assert.are.equal(1, #result)
        assert.are.equal(1, result[1].open_line)
        assert.are.equal(3, result[1].close_line)
    end)

    it("finds a while block", function()
        local source = [[
            while true do
                break
            end
        ]]
        local result, errs = blocks.parse(source, "test.tl")
        assert.are.equal(0, #errs)
        assert.are.equal(1, #result)
        assert.are.equal(1, result[1].open_line)
        assert.are.equal(3, result[1].close_line)
    end)

    it("finds a for block", function()
        local source = [[
            for i = 1, 10 do
                print(i)
            end
        ]]
        local result, errs = blocks.parse(source, "test.tl")
        assert.are.equal(0, #errs)
        assert.are.equal(1, #result)
        assert.are.equal(1, result[1].open_line)
        assert.are.equal(3, result[1].close_line)
    end)

    it("finds a repeat block", function()
        local source = [[
            repeat
                x = x + 1
            until x > 10
        ]]
        local result, errs = blocks.parse(source, "test.tl")
        assert.are.equal(0, #errs)
        assert.are.equal(1, #result)
        assert.are.equal(1, result[1].open_line)
        assert.are.equal(3, result[1].close_line)
    end)

    it("returns no blocks for empty source", function()
        local result, errs = blocks.parse("", "test.tl")
        assert.are.equal(0, #errs)
        assert.are.equal(0, #result)
    end)
end)
