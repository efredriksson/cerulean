require("tl").loader()

local helpers = require("spec.formatter.helpers")
local assert = require("luassert")

local fixtures = "spec/formatter/fixtures/"

describe("FormatterOptions.from_config_file_and_args", function()

    describe("defaults", function()
        it("returns default options when only files are given", function()
            local opts, err = helpers.resolve_options(fixtures .. "configs/no_config", {"file.tl"})
            assert.is_nil(err)
            assert.is_false(opts.check_only)
            assert.same("nothing", opts.log_level)
            assert.same(4, opts.indent_width)
            assert.same(88, opts.max_line_width)
            assert.is_true(opts.sort_requires)
            assert.same({"file.tl"}, opts.files)
        end)
    end)

    describe("files", function()
        it("collects a single positional argument as a file", function()
            local opts, err = helpers.resolve_options(".", {"a.tl"})
            assert.is_nil(err)
            assert.same({"a.tl"}, opts.files)
        end)

        it("collects multiple positional arguments as files", function()
            local opts, err = helpers.resolve_options(".", {"a.tl", "b.tl", "c.tl"})
            assert.is_nil(err)
            assert.same({"a.tl", "b.tl", "c.tl"}, opts.files)
        end)

        it("collects files interspersed with flags", function()
            local opts, err = helpers.resolve_options(".", {"a.tl", "--check", "b.tl"})
            assert.is_nil(err)
            assert.same({"a.tl", "b.tl"}, opts.files)
            assert.is_true(opts.check_only)
        end)

        it("defaults to the current directory when only flags are given", function()
            local opts, err = helpers.resolve_options(fixtures .. "file_discovery/empty", {"--check"})
            assert.is_nil(err)
            assert.same({}, opts.files)
        end)

        it("defaults to the current directory when args is empty", function()
            local opts, err = helpers.resolve_options(fixtures .. "file_discovery/empty", {})
            assert.is_nil(err)
            assert.same({}, opts.files)
        end)
    end)

    describe("--check", function()
        it("sets check_only to true", function()
            local opts, err = helpers.resolve_options(".", {"--check", "file.tl"})
            assert.is_nil(err)
            assert.is_true(opts.check_only)
        end)

        it("check_only is false without the flag", function()
            local opts, err = helpers.resolve_options(".", {"file.tl"})
            assert.is_nil(err)
            assert.is_false(opts.check_only)
        end)
    end)

    describe("--no-sort-requires", function()
        it("sets sort_requires to false", function()
            local opts, err = helpers.resolve_options(".", {"--no-sort-requires", "file.tl"})
            assert.is_nil(err)
            assert.is_false(opts.sort_requires)
        end)

        it("sort_requires is true without the flag", function()
            local opts, err = helpers.resolve_options(".", {"file.tl"})
            assert.is_nil(err)
            assert.is_true(opts.sort_requires)
        end)
    end)

    describe("--log-level", function()
        it("sets log_level to the given value", function()
            local opts, err = helpers.resolve_options(".", {"--log-level", "info", "file.tl"})
            assert.is_nil(err)
            assert.same("info", opts.log_level)
        end)

        it("accepts debug", function()
            local opts, err = helpers.resolve_options(".", {"--log-level", "debug", "file.tl"})
            assert.is_nil(err)
            assert.same("debug", opts.log_level)
        end)

        it("returns an error when no argument follows", function()
            local opts, err = helpers.resolve_options(".", {"--log-level"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)
    end)

    describe("--indent", function()
        it("sets indent_width to the given value", function()
            local opts, err = helpers.resolve_options(".", {"--indent", "2", "file.tl"})
            assert.is_nil(err)
            assert.same(2, opts.indent_width)
        end)

        it("returns an error when no argument follows", function()
            local opts, err = helpers.resolve_options(".", {"--indent"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)

        it("returns an error for a non-integer value", function()
            local opts, err = helpers.resolve_options(".", {"--indent", "two", "file.tl"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)

        it("returns an error for zero", function()
            local opts, err = helpers.resolve_options(".", {"--indent", "0", "file.tl"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)

        it("returns an error for a negative value", function()
            local opts, err = helpers.resolve_options(".", {"--indent", "-1", "file.tl"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)
    end)

    describe("--line-length", function()
        it("sets max_line_width to the given value", function()
            local opts, err = helpers.resolve_options(".", {"--line-length", "100", "file.tl"})
            assert.is_nil(err)
            assert.same(100, opts.max_line_width)
        end)

        it("returns an error when no argument follows", function()
            local opts, err = helpers.resolve_options(".", {"--line-length"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)

        it("returns an error for a non-integer value", function()
            local opts, err = helpers.resolve_options(".", {"--line-length", "wide", "file.tl"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)

        it("returns an error for zero", function()
            local opts, err = helpers.resolve_options(".", {"--line-length", "0", "file.tl"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)
    end)

    describe("unknown flags", function()
        it("returns an error for an unrecognised flag", function()
            local opts, err = helpers.resolve_options(".", {"--unknown", "file.tl"})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)

        it("error message names the bad flag", function()
            local opts, err = helpers.resolve_options(".", {"--bad-flag", "file.tl"})
            assert.is_nil(opts)
            assert.truthy(err:find("--bad-flag", 1, true))
        end)
    end)

    describe("combined flags", function()
        it("parses all flags together", function()
            local opts, err = helpers.resolve_options(".", {
                "--check",
                "--no-sort-requires",
                "--log-level", "debug",
                "--indent", "2",
                "--line-length", "120",
                "a.tl",
                "b.tl",
            })
            assert.is_nil(err)
            assert.is_true(opts.check_only)
            assert.is_false(opts.sort_requires)
            assert.same("debug", opts.log_level)
            assert.same(2, opts.indent_width)
            assert.same(120, opts.max_line_width)
            assert.same({"a.tl", "b.tl"}, opts.files)
        end)
    end)

    describe("directory expansion", function()
        it("passes an explicit file through unchanged", function()
            local path = fixtures .. "file_discovery/flat/a.tl"
            local opts, err = helpers.resolve_options(".", {path})
            assert.is_nil(err)
            assert.same({path}, opts.files)
        end)

        it("passes an explicit non-.tl file through unchanged", function()
            local path = fixtures .. "file_discovery/flat/script.lua"
            local opts, err = helpers.resolve_options(".", {path})
            assert.is_nil(err)
            assert.same({path}, opts.files)
        end)

        it("expands a directory to its .tl files in alphabetical order", function()
            local dir = fixtures .. "file_discovery/flat"
            local opts, err = helpers.resolve_options(".", {dir})
            assert.is_nil(err)
            assert.same({dir .. "/a.tl", dir .. "/b.tl"}, opts.files)
        end)

        it("recurses into subdirectories", function()
            local dir = fixtures .. "file_discovery/recursive"
            local opts, err = helpers.resolve_options(".", {dir})
            assert.is_nil(err)
            assert.same({dir .. "/sub/nested.tl", dir .. "/top.tl"}, opts.files)
        end)

        it("skips hidden directories", function()
            local dir = fixtures .. "file_discovery/with_hidden"
            local opts, err = helpers.resolve_options(".", {dir})
            assert.is_nil(err)
            assert.same({dir .. "/visible.tl"}, opts.files)
        end)

        it("returns empty list for an empty directory", function()
            local dir = fixtures .. "file_discovery/empty"
            local opts, err = helpers.resolve_options(".", {dir})
            assert.is_nil(err)
            assert.same({}, opts.files)
        end)

        it("mixes explicit files and directories", function()
            local dir = fixtures .. "file_discovery/flat"
            local file = fixtures .. "file_discovery/recursive/top.tl"
            local opts, err = helpers.resolve_options(".", {file, dir})
            assert.is_nil(err)
            assert.same({file, dir .. "/a.tl", dir .. "/b.tl"}, opts.files)
        end)
    end)

    describe("config file", function()
        it("returns default options when no tlconfig.lua exists", function()
            local opts, err = helpers.resolve_options(fixtures .. "configs/no_config", {})
            assert.is_nil(err)
            assert.same(4, opts.indent_width)
            assert.same(88, opts.max_line_width)
            assert.is_true(opts.sort_requires)
        end)

        it("reads formatter.indent_width", function()
            local opts, err = helpers.resolve_options(fixtures .. "configs/indent_width_2", {})
            assert.is_nil(err)
            assert.same(2, opts.indent_width)
        end)

        it("reads formatter.max_line_width", function()
            local opts, err = helpers.resolve_options(fixtures .. "configs/max_line_width_120", {})
            assert.is_nil(err)
            assert.same(120, opts.max_line_width)
        end)

        it("reads formatter.sort_requires = false", function()
            local opts, err = helpers.resolve_options(fixtures .. "configs/no_sort_requires", {})
            assert.is_nil(err)
            assert.is_false(opts.sort_requires)
        end)

        it("returns default options when tlconfig.lua has no formatter key", function()
            local opts, err = helpers.resolve_options(fixtures .. "configs/no_formatter_key", {})
            assert.is_nil(err)
            assert.same(4, opts.indent_width)
            assert.same(88, opts.max_line_width)
            assert.is_true(opts.sort_requires)
        end)

        it("returns an error when the formatter key is not a table", function()
            local opts, err = helpers.resolve_options(fixtures .. "configs/malformed_formatter", {})
            assert.is_nil(opts)
            assert.is_not_nil(err)
        end)
    end)
end)
