require("tl").loader()

local cli = require("cerulean.cli")
local assert = require("luassert")

local cli_fixtures = "spec/cerulean/fixtures/cli/"

local function run(args)
    local out_lines = {}
    local err_lines = {}
    local printer = cli.new_printer(
        function(msg) table.insert(out_lines, msg) end,
        function(msg) table.insert(err_lines, msg) end
    )
    local code = cli.run(args, printer)
    return code, out_lines, err_lines
end

local function assert_contains(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then return end
    end
    local indented_line = "\n  "
    error(
        "expected output to contain: "
            .. text
            .. "\ngot:"
            .. indented_line
            .. table.concat(lines, indented_line),
        2
    )
end

describe("cli.run", function()

    describe("single file", function()
        it("returns 0 for a valid file", function()
            local code = run({cli_fixtures .. "valid.tl"})
            assert.same(0, code)
        end)

        it("returns 1 and reports the parse error for an invalid file", function()
            local code, _, err = run({cli_fixtures .. "invalid.tl"})
            assert.same(1, code)
            assert_contains(err, "invalid.tl")
        end)

        it("returns 1 and reports an error for a nonexistent file", function()
            local code, _, err = run({"nonexistent_file_cerulean_test.tl"})
            assert.same(1, code)
            assert_contains(err, "nonexistent_file_cerulean_test")
        end)
    end)

    describe("--help / -h", function()
        it("--help returns exit code 0", function()
            local code = run({"--help"})
            assert.same(0, code)
        end)

        it("--help prints to out, not err", function()
            local code, out, err = run({"--help"})
            assert.same(0, code)
            assert.same(0, #err)
            assert.is_true(#out > 0)
        end)

        it("--help output contains Usage:", function()
            local _, out = run({"--help"})
            assert_contains(out, "Usage:")
        end)

        it("-h returns exit code 0", function()
            local code = run({"-h"})
            assert.same(0, code)
        end)

        it("-h output contains Usage:", function()
            local _, out = run({"-h"})
            assert_contains(out, "Usage:")
        end)

        it("--help combined with other args still returns 0 and prints help", function()
            local code, out = run({"--help", "--check", "some_file.tl"})
            assert.same(0, code)
            assert_contains(out, "Usage:")
        end)
    end)

    describe("folder with one invalid and one valid file", function()
        it("returns 1", function()
            local code = run({cli_fixtures})
            assert.same(1, code)
        end)

        it("reports the parse error", function()
            local _, _, err = run({cli_fixtures})
            assert_contains(err, "invalid.tl")
        end)

        it("still processes the valid file", function()
            local _, out = run({cli_fixtures})
            assert_contains(out, "left unchanged")
        end)

        it("reports how many files could not be processed", function()
            local _, _, err = run({cli_fixtures})
            assert_contains(err, "could not be processed")
        end)
    end)

end)
