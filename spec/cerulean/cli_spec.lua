require("tl").loader()

local cli = require("cerulean.cli")
local daemon = require("cerulean.daemon")
local helpers = require("spec.cerulean.helpers")
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

    describe("--version / -v", function()
        it("--version returns exit code 0", function()
            local code = run({"--version"})
            assert.same(0, code)
        end)

        it("--version prints to out, not err", function()
            local code, out, err = run({"--version"})
            assert.same(0, code)
            assert.same(0, #err)
            assert.is_true(#out > 0)
        end)

        it("--version output contains ceru", function()
            local _, out = run({"--version"})
            assert_contains(out, "dev")
        end)

        it("-v returns exit code 0", function()
            local code = run({"-v"})
            assert.same(0, code)
        end)

        it("-v output contains ceru", function()
            local _, out = run({"-v"})
            assert_contains(out, "dev")
        end)

        it("--version combined with other args still returns 0 and prints version", function()
            local code, out = run({"--version", "--check", "some_file.tl"})
            assert.same(0, code)
            assert_contains(out, "dev")
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

describe("daemon.run", function()

    local READY_BANNER = "cerulean-daemon: ready\n"

    local function frame(kind, payload)
        payload = payload or ""
        return kind .. "\n" .. tostring(#payload) .. "\n" .. payload
    end

    local PONG_FRAME = frame("PONG")

    local function run_daemon(input)
        local daemon_io = helpers.new_fake_daemon_io(input)
        daemon.run(daemon_io)
        return daemon_io:output(), daemon_io:errors()
    end

    describe("happy path", function()
        it("responds to PING with PONG", function()
            local out = run_daemon(frame("PING"))
            assert.same(PONG_FRAME, out)
        end)

        it("writes the ready banner to write_err", function()
            local _, err = run_daemon(frame("QUIT"))
            assert.same(READY_BANNER, err)
        end)

        it("returns 0 and writes nothing for QUIT alone", function()
            local out = run_daemon(frame("QUIT"))
            assert.same("", out)
        end)

        it("returns 0 on EOF with no commands", function()
            local out = run_daemon("")
            assert.same("", out)
        end)

        it("formats a valid source and replies OK", function()
            local src = "local x = 1\n"
            local out = run_daemon(frame("FORMAT", src) .. frame("QUIT"))
            assert.same(frame("OK", src), out)
        end)

        it("handles multiple back-to-back requests without state leak", function()
            local src_a = "local x = 1\n"
            local src_b = "local y = 2\n"
            local input = frame("PING")
                .. frame("FORMAT", src_a)
                .. frame("FORMAT", src_b)
                .. frame("QUIT")
            local out = run_daemon(input)
            assert.same(
                PONG_FRAME .. frame("OK", src_a) .. frame("OK", src_b),
                out
            )
        end)
    end)

    describe("malformed input", function()
        it("ERRs on missing length header (EOF)", function()
            local out = run_daemon("FORMAT\n")
            assert.same(frame("ERR", "missing length header"), out)
        end)

        it("ERRs on non-numeric length", function()
            local out = run_daemon("FORMAT\nabc\n")
            assert.same(frame("ERR", "bad length header: abc"), out)
        end)

        it("ERRs on negative length", function()
            local out = run_daemon("FORMAT\n-5\n")
            assert.same(frame("ERR", "bad length header: -5"), out)
        end)

        it("ERRs on short body read", function()
            local out = run_daemon("FORMAT\n10\nabc")
            assert.same(frame("ERR", "short read on body"), out)
        end)

        it("ERRs on unknown command and stays alive for next command", function()
            local out = run_daemon(
                frame("BOGUS") .. frame("PING") .. frame("QUIT")
            )
            assert.same(
                frame("ERR", "unknown command: BOGUS") .. PONG_FRAME,
                out
            )
        end)

        it("ignores blank lines between commands", function()
            local out = run_daemon(
                "\n\n" .. frame("PING") .. "\n" .. frame("QUIT")
            )
            assert.same(PONG_FRAME, out)
        end)

        it("ERRs on a partial trailing frame at EOF", function()
            local out = run_daemon(frame("PING") .. "PING\n")
            assert.same(
                PONG_FRAME .. frame("ERR", "missing length header"),
                out
            )
        end)
    end)

    describe("parse errors", function()
        it("replies ERR with line:col:msg and stays alive", function()
            local src = "local x =\n"
            local out = run_daemon(frame("FORMAT", src) .. frame("PING"))
            assert.same(
                frame("ERR", "2:1: expected an expression") .. PONG_FRAME,
                out
            )
        end)
    end)

end)
