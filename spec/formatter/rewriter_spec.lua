local helpers = require("spec.formatter.helpers")

describe("formatter", function()

   describe("comma spacing", function()
      it("adds a single space after commas where spacing is wrong", helpers.format([[
         local x = f(1,  2,  3)
         local y = f("a","b")
      ]], [[
         local x = f(1, 2, 3)
         local y = f("a", "b")
      ]]))

      it("does not change a comma that already has exactly one space", helpers.check([[
         local x = f(1, 2, 3)
      ]]))

      it("does not touch commas where the next token is on the next line", helpers.check([[
         local x = f(1,
            2)
      ]]))
   end)

   describe("trailing spaces", function()
      it("removes trailing whitespace from lines", helpers.format([[
         local x = 1   
         local y = 2
         local z = x + y  
      ]], [[
         local x = 1
         local y = 2
         local z = x + y
      ]]))

      it("leaves already-clean source unchanged", helpers.check([[
         local x = 1
         local y = 2
      ]]))
   end)

   describe("fmt: off / fmt: on", function()
      it("skips formatting between directives and resumes after", helpers.format([[
         local function example()
            -- fmt: off
            local a = {1,  2,  3}
            local b = {4,  5,  6}
            -- fmt: on
            local c = {7,  8,  9}
         end
      ]], [[
         local function example()
            -- fmt: off
            local a = {1,  2,  3}
            local b = {4,  5,  6}
            -- fmt: on
            local c = {7, 8, 9}
         end
      ]]))

      it("fmt: off without fmt: on is scoped to the enclosing block", helpers.format([[
         local function inner()
            -- fmt: off
            local a = {1,  2,  3}
         end

         local b = {4,  5,  6}
      ]], [[
         local function inner()
            -- fmt: off
            local a = {1,  2,  3}
         end

         local b = {4, 5, 6}
      ]]))
   end)

   describe("resilience", function()
      it("returns an empty file unchanged", helpers.check([[
      ]]))

      it("returns a file with only comments unchanged", helpers.check([[
         -- this is a comment
         -- another comment
      ]]))

      it("fmt: off at top level freezes to end of file", helpers.check([[
         -- fmt: off
         local x = {1,  2,  3}
      ]]))

      it("reports a lex error for an unclosed string", helpers.parse_error([[
         local x = "hello
      ]]))

      it("reports a parse error for a missing end", helpers.parse_error([[
         local function f()
            local x = 1
      ]]))
   end)

   describe("operator spacing", function()
      it("adds spaces around binary operators that have none", helpers.format([[
         local x = 1+2
      ]], [[
         local x = 1 + 2
      ]]))

      it("collapses multiple spaces around an operator to one", helpers.format([[
         local x = 1  +  2
      ]], [[
         local x = 1 + 2
      ]]))

      it("does not change operators that already have one space", helpers.check([[
         local x = 1 + 2 - 3 * 4 / 5 % 6 ^ 7
      ]]))

      it("handles comparison and logical operators", helpers.format([[
         if a==b or c~=d and i<=j or k>=l then end
      ]], [[
         if a == b or c ~= d and i <= j or k >= l then end
      ]]))

      it("does not add spaces around unary minus", helpers.check([[
         local x = -1
         local y = f(-1, -2)
         local z = 1 + -1
      ]]))

      it("does not touch Teal attribute brackets", helpers.check([[
         local x <const> = 1
         local y <close> = f()
         local z <total> = 1
      ]]))

      it("does not touch generic type parameters", helpers.check([[
         local x: Group<Bomb> = Group.new()
         local function f(g: ReadableGroup<Player>): Group<Bomb> end
      ]]))

      it("handles string concatenation operator", helpers.format([[
         local s = "a".."b"
      ]], [[
         local s = "a" .. "b"
      ]]))

      it("handles assignment operator", helpers.format([[
         local x=1
      ]], [[
         local x = 1
      ]]))

      it("does not touch operators where the next token is on the next line", helpers.check([[
         local x = 1 +
            2
      ]]))
   end)

   describe("function signature wrapping", function()
      it("wraps a long single-line signature to one param per line", helpers.format_raw(
         "function f(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType): ReturnValue\nend\n",
         "function f(\n    param_one: LongTypeName,\n    param_two: AnotherLongType,\n    param_three: YetAnotherType\n): ReturnValue\nend\n"
      ))

      it("joins an already-wrapped signature that fits on one line", helpers.format_raw(
         "function f(\n    param_one: TypeA,\n    param_two: TypeB\n): ReturnType\nend\n",
         "function f(param_one: TypeA, param_two: TypeB): ReturnType\nend\n"
      ))

      it("does not change a short signature that is already on one line", helpers.check_raw(
         "function f(x: integer, y: integer): integer\nend\n"
      ))

      it("preserves indentation when wrapping a method signature", helpers.format_raw(
         "    function Obj:method(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType)\n    end\n",
         "    function Obj:method(\n        param_one: LongTypeName,\n        param_two: AnotherLongType,\n        param_three: YetAnotherType\n    )\n    end\n"
      ))
   end)

   describe("indentation", function()
      it("converts leading tabs to 4-space indentation", helpers.format_raw(
         "local function f()\n\tlocal x = 1\nend\n",
         "local function f()\n    local x = 1\nend\n"
      ))

      it("converts nested tabs to the correct number of spaces", helpers.format_raw(
         "local function f()\n\tif true then\n\t\tlocal x = 1\n\tend\nend\n",
         "local function f()\n    if true then\n        local x = 1\n    end\nend\n"
      ))

      it("does not change lines already using 4-space indentation", helpers.check_raw(
         "local function f()\n    local x = 1\nend\n"
      ))

      it("does not touch tabs that appear mid-line", helpers.check_raw(
         "local x = \"a\tb\"\n"
      ))
   end)

   describe("blank line normalisation", function()
      it("collapses two consecutive blank lines to one", helpers.format([[
         local x = 1


         local y = 2
      ]], [[
         local x = 1

         local y = 2
      ]]))

      it("collapses three or more consecutive blank lines to one", helpers.format([[
         local x = 1



         local y = 2
      ]], [[
         local x = 1

         local y = 2
      ]]))

      it("does not change a file with at most one blank line between declarations", helpers.check([[
         local x = 1

         local y = 2
      ]]))
   end)

   describe("require sorting", function()
      it("sorts a contiguous block of requires alphabetically by module path", helpers.format([[
         local b = require("b.module")
         local a = require("a.module")
      ]], [[
         local a = require("a.module")
         local b = require("b.module")
      ]]))

      it("does not change an already-sorted block", helpers.check([[
         local a = require("a.module")
         local b = require("b.module")
         local c = require("c.module")
      ]]))

      it("sorts each contiguous block independently", helpers.format([[
         local b = require("b")
         local a = require("a")

         local d = require("d")
         local c = require("c")
      ]], [[
         local a = require("a")
         local b = require("b")

         local c = require("c")
         local d = require("d")
      ]]))

      it("does not sort requires separated by non-require lines", helpers.check([[
         local a = require("a")
         local x = 1
         local b = require("b")
      ]]))

      it("sorts local type requires in the same block", helpers.format([[
         local type B = require("b")
         local type A = require("a")
      ]], [[
         local type A = require("a")
         local type B = require("b")
      ]]))
   end)

   describe("quote normalisation", function()
      it("converts single-quoted strings to double quotes", helpers.format([[
         local x = 'hello'
      ]], [[
         local x = "hello"
      ]]))
   end)

   describe("table constructor wrapping", function()
      it("wraps a long single-line table constructor to one element per line", helpers.format_raw(
         "local items = {Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon}\n",
         "local items = {\n    Alpha = Alpha,\n    Beta = Beta,\n    Gamma = Gamma,\n    Delta = Delta,\n    Epsilon = Epsilon,\n}\n"
      ))

      it("joins an already-wrapped table constructor that fits on one line", helpers.format_raw(
         "local items = {\n    Alpha = Alpha,\n    Beta = Beta,\n}\n",
         "local items = {Alpha = Alpha, Beta = Beta}\n"
      ))

      it("does not change a short table constructor already on one line", helpers.check_raw(
         "local items = {Alpha = Alpha, Beta = Beta}\n"
      ))

      it("does not change an already-wrapped table constructor that does not fit on one line", helpers.check_raw(
         "local items = {\n    Alpha = Alpha,\n    Beta = Beta,\n    Gamma = Gamma,\n    Delta = Delta,\n    Epsilon = Epsilon,\n}\n"
      ))

      it("preserves indentation when wrapping a table constructor", helpers.format_raw(
         "    local items = {Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon}\n",
         "    local items = {\n        Alpha = Alpha,\n        Beta = Beta,\n        Gamma = Gamma,\n        Delta = Delta,\n        Epsilon = Epsilon,\n    }\n"
      ))
   end)

   describe("function call wrapping", function()
      it("wraps a long function call to one arg per line", helpers.format_raw(
         "    local x = foo.new_selection(some_settings.long_field_name, minimum_value, maximum_value)\n",
         "    local x = foo.new_selection(\n        some_settings.long_field_name,\n        minimum_value,\n        maximum_value\n    )\n"
      ))

      it("joins an already-wrapped call that fits on one line", helpers.format_raw(
         "    local x = foo.new_selection(\n        field_a,\n        field_b\n    )\n",
         "    local x = foo.new_selection(field_a, field_b)\n"
      ))

      it("does not change a short call", helpers.check_raw(
         "    local x = foo.new_selection(field_a, field_b)\n"
      ))

      it("re-wraps an already-wrapped call whose args line is too long", helpers.format_raw(
         "foo.new_number(\n    \"long_label_here\", 110, nbr_lightning_bombs_selected, settings.set_spawn_of_lightning_bombs\n)\n",
         "foo.new_number(\n    \"long_label_here\",\n    110,\n    nbr_lightning_bombs_selected,\n    settings.set_spawn_of_lightning_bombs\n)\n"
      ))
   end)

end)
