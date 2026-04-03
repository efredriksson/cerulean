local helpers = require("spec.formatter.helpers")

describe("formatter", function()


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


   describe("structural block rendering", function()
      it("reindents a clean local function body with wrong space indentation", helpers.format([[
         local function f()
           local x =  1
         end
      ]], [[
         local function f()
             local x = 1
         end
      ]]))

      it("reindents clean if elseif else blocks with wrong space indentation", helpers.format([[
         local function f(flag: boolean)
           if flag then
             log("yes" )
           elseif not flag then
             log("maybe")
           else
             log("no")
           end
         end
      ]], [[
         local function f(flag: boolean)
             if flag then
                 log("yes")
             elseif not flag then
                 log("maybe")
             else
                 log("no")
             end
         end
      ]]))

      it("reindents a clean while block with wrong space indentation", helpers.format([[
         local function f( )
           while ready() do
             tick()
           end
         end
      ]], [[
         local function f()
             while ready() do
                 tick()
             end
         end
      ]]))

      it("reindents a clean do block with wrong space indentation", helpers.format([[
         local function f()
           do
                     tick()
           end
         end
      ]], [[
         local function f()
             do
                 tick()
             end
         end
      ]]))

      it("reindents a clean repeat block with wrong space indentation", helpers.format([[
         local function f()
           repeat
             tick()
           until done()
         end
      ]], [[
         local function f()
             repeat
                 tick()
             until done()
         end
      ]]))

      it("reindents a clean numeric for block with wrong space indentation", helpers.format([[
         local function f()
           for i = 1,    3 do
             tick(i)
           end
         end
      ]], [[
         local function f()
             for i = 1, 3 do
                 tick(i)
             end
         end
      ]]))

      it("reindents a clean generic for block with wrong space indentation", helpers.format([[
         local function f(items: {string})
           for _, item in ipairs(items) do
             log(item)
           end
         end
      ]], [[
         local function f(items: {string})
             for _, item in ipairs(items) do
                 log(item)
             end
         end
      ]]))

      it("reindents clean assignment return and expression statements", helpers.format([[
         local function f()
           local x = 1
           x = x + 1
           log(x)
           return x
         end
      ]], [[
         local function f()
             local x = 1
             x = x + 1
             log(x)
             return x
         end
      ]]))

      it("reindents nested clean blocks transitively", helpers.format([[
         local function f(items: {string})
           for _, item in ipairs(items) do
             if active(item) then
               log(item)
             end
           end
         end
      ]], [[
         local function f(items: {string})
             for _, item in ipairs(items) do
                 if active(item) then
                     log(item)
                 end
             end
         end
      ]]))

      it("keeps wrong space indentation when a comment blocks structural rendering", helpers.check([[
         local function f()
           local x = 1 -- keep this comment
           return x
         end
      ]]))

      it("keeps wrong space indentation when blank line gaps block structural rendering", helpers.format([[
         local function f()
           local x = 1


           return x
         end
      ]], [[
         local function f()
             local x = 1

             return x
         end
      ]]))

      it("reindents a colon method definition with a clean block body", helpers.format([[
         function Obj:method(flag: boolean)
           if flag then
             log(self)
           end
         end
      ]], [[
         function Obj:method(flag: boolean)
             if flag then
                 log(self)
             end
         end
      ]]))

      it("reindents a dotted record function with nested clean blocks", helpers.format([[
         function Obj.build(items: {string})
           for _, item in ipairs(items) do
             if active(item) then
               log(item)
             end
           end
         end
      ]], [[
         function Obj.build(items: {string})
             for _, item in ipairs(items) do
                 if active(item) then
                     log(item)
                 end
             end
         end
      ]]))

      it("keeps wrong space indentation for an unsupported const declaration", helpers.check([[
         local function f()
           local x <const> = 1
           return x
         end
      ]]))

      it("reindents a function body with a local type and multiline if condition", helpers.format([[
         local function f(ready: boolean, active: boolean)
           local type Result = string | number
           if ready
               and active
           then
             return
           end
         end
      ]], [[
         local function f(ready: boolean, active: boolean)
             local type Result = string | number
             if ready and active then
                 return
             end
         end
      ]]))

      it("reindents a function body with break in a multiline while condition", helpers.format([[
         local function f()
           while ready()
               and active()
           do
             break
           end
         end
      ]], [[
         local function f()
             while ready() and active() do
                 break
             end
         end
      ]]))

      it("reindents a function body with a typed local and multiline if condition", helpers.format([[
         local function f()
           local current: ResultType = compute_result()
           if ready()
               and active()
           then
             log(current)
           end
         end
      ]], [[
         local function f()
             local current: ResultType = compute_result()
             if ready() and active() then
                 log(current)
             end
         end
      ]]))

      it("reindents a function body with a richer return expression under a multiline while condition", helpers.format([[
         local function f()
           while ready()
               and active()
           do
             return left_value + right_value * compute_result()
           end
         end
      ]], [[
         local function f()
             while ready() and active() do
                 return left_value + right_value * compute_result()
             end
         end
      ]]))

      it("reindents a clean function body while preserving a single blank line", helpers.format(
         "local function f()\n  local x = 1\n\n  return x\nend\n",
         "local function f()\n    local x = 1\n\n    return x\nend\n"
      ))

      it("reindents a function body with a multiline local call rhs", helpers.format([[
         local function setup()
           local selected = foo.new_selection(
             some_settings.long_field_name,
             minimum_value_long,
             maximum_value_long
           )
           return selected
         end
      ]], [[
         local function setup()
             local selected = foo.new_selection(
                 some_settings.long_field_name, minimum_value_long, maximum_value_long
             )
             return selected
         end
      ]]))

      it("reindents a function body with a multiline return call with a table arg", helpers.format([[
         local function setup()
           return foo.new(
             {first_option_name = first_option_value, second_option_name = second_option_value, third_option_name = third_option_value},
             done_callback
           )
         end
      ]], [[
         local function setup()
             return foo.new(
                 {
                     first_option_name = first_option_value,
                     second_option_name = second_option_value,
                     third_option_name = third_option_value,
                 },
                 done_callback
             )
         end
      ]]))
   end)

   describe("top-level structural block rendering", function()
      it("reindents a clean top-level if block", helpers.format([[
         if ready then
           tick()
         end
      ]], [[
         if ready then
             tick()
         end
      ]]))

      it("reindents a clean top-level mixed local if return block", helpers.format([[
         local ready = true
         if ready then
           tick()
         end
         return ready and done()
      ]], [[
         local ready = true
         if ready then
             tick()
         end
         return ready and done()
      ]]))

      it("reindents a top-level function definition with nested clean blocks", helpers.format([[
         local function build(items: {string})
           for _, item in ipairs(items) do
             if active(item) then
               log(item)
             end
           end
         end
         return build
      ]], [[
         local function build(items: {string})
             for _, item in ipairs(items) do
                 if active(item) then
                     log(item)
                 end
             end
         end
         return build
      ]]))

      it("reindents a top-level block with a multiline local call rhs", helpers.format([[
         local selected = foo.new_selection(
             some_settings.long_field_name,
             minimum_value_long,
             maximum_value_long
         )
         if enabled then
           log(selected)
         end
         return selected
      ]], [[
         local selected = foo.new_selection(
             some_settings.long_field_name, minimum_value_long, maximum_value_long
         )
         if enabled then
             log(selected)
         end
         return selected
      ]]))

      it("reindents a top-level block with a multiline local table rhs", helpers.format([[
         local items = {
             first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha,
             second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta,
             third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma
         }
         if ready then
           log(items)
         end
         return items
      ]], [[
         local items = {
             first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha,
             second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta,
             third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma,
         }
         if ready then
             log(items)
         end
         return items
      ]]))

      it("reindents a top-level block with a multiline return expression", helpers.format([[
         local ready = true
         if ready then
           tick()
         end
         return interval_overlap(
             self.x,
             self.x + self.width,
             other.x,
             other.x + other.width
         ) and
             interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
      ]], [[
         local ready = true
         if ready then
             tick()
         end
         return interval_overlap(
            self.x, self.x + self.width, other.x, other.x + other.width
         ) and interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
      ]]))

      it("reindents a top-level block while preserving a single blank line", helpers.format(
         "local ready = true\n\nif ready then\n  tick()\nend\nreturn ready\n",
         "local ready = true\n\nif ready then\n    tick()\nend\nreturn ready\n"
      ))
   end)


   describe("require sorting", function()
      it("sorts a contiguous block of requires alphabetically by module path", helpers.format([[
         local b = require("b.module")
         local a = require("a.module")
      ]], [[
         local a = require("a.module")
         local b = require("b.module")
      ]], { skip_ast_equivalence = true }))

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
      ]], { skip_ast_equivalence = true }))

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
      ]], { skip_ast_equivalence = true }))

      it("sorts typed local requires and renders them from AST", helpers.format([[
         local b: BType = require( "b" )
         local a: AType = require( "a" )
      ]], [[
         local a: AType = require("a")
         local b: BType = require("b")
      ]], { skip_ast_equivalence = true }))

      it("sorts requires with non-standard spacing inside the call parens", helpers.format([[
         local b = require( "b.module" )
         local a = require( "a.module" )
      ]], [[
         local a = require("a.module")
         local b = require("b.module")
      ]], { skip_ast_equivalence = true }))

      it("sorts multi-line require declarations and renders them structurally", helpers.format([[
         local b =
             require("b.module")
         local a =
             require("a.module")
      ]], [[
         local a = require("a.module")
         local b = require("b.module")
      ]], { skip_ast_equivalence = true }))

      it("does not sort requires inside a function body", helpers.format([[
         local function setup()
            local b = require("b")
            local a = require("a")
         end
      ]], [[
         local function setup()
             local b = require("b")
             local a = require("a")
         end
      ]]))

      it("excludes a require with a variable argument from the sort block", helpers.check([[
         local b = require("b")
         local a = require(module_name)
         local c = require("c")
      ]]))

      it("excludes a require with a non-literal-string argument from the sort block", helpers.check([[
         local b = require("b")
         local a = require("a" .. ".module")
         local c = require("c")
      ]]))

      it("excludes a require with an inline comment from the sort block", helpers.check([[
         local b = require("b") -- keep this where it is
         local a = require("a")
      ]]))

   end)


   describe("table constructor wrapping", function()
      it("wraps a long single-line table constructor to compact form when the inner line fits", helpers.format([[
         local items = {Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon}
      ]], [[
         local items = {
             Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon
         }
      ]]))

      it("joins an already-wrapped table constructor that fits on one line", helpers.format([[
         local items = {
             Alpha = Alpha,
             Beta = Beta
         }
      ]],[[
         local items = {Alpha = Alpha, Beta = Beta}
      ]]))

      it("does not change a short table constructor already on one line", helpers.check(
         "local items = {Alpha = Alpha, Beta = Beta}"
      ))

      it("does not change an already-wrapped table constructor that does not fit on one line", helpers.check([[
         local items = {
             Alpha = Alpha,
             Beta = Beta,
             Gamma = Gamma,
             Delta = Delta,
             Epsilon = Epsilon,
         }
      ]]))

      it("preserves indentation when wrapping a table constructor", helpers.format([[
         local items = {Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon}
      ]],[[
         local items = {
             Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon
         }
      ]]))

      it("wraps a long table constructor to one element per line when the compact broken form is still too wide", helpers.format([[
         local items = {first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha, second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta, third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma}
      ]], [[
         local items = {
             first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha,
             second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta,
             third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma,
         }
      ]]))

      it("does not change a table whose entries have inline comments", helpers.check([[
         local z = {
            BELOW = -3, -- on ground
            LEVEL = 0 -- ground level
         }
      ]]))

      it("does not join a multi-line table whose last entry has a trailing comma", helpers.check([[
         local t = {
             a = 1,
             b = 2,
         }
      ]]))

      it("joins a multi-line table whose last entry has no trailing comma", helpers.format([[
         local t = {
            a = 1,
            b = 2
         }
      ]],[[
         local t = {a = 1, b = 2}
      ]]))

      it("does not collapse a wrapped table after joining its multi-line call entry", helpers.format([[
         local t = {
            key = foo(
               arg_one,
               arg_two
            ),
         }
      ]],[[
         local t = {
            key = foo(arg_one, arg_two),
         }
      ]]))

      it("preserves source spelling for typed and anonymous-function table entries", helpers.format([[
         local items = {callback: function(ctx: Scene): ResultType = function(ctx: Scene): ResultType return ctx.result end, value = ((left_value + right_value))}
      ]], [[
         local items = {
             callback: function(ctx: Scene): ResultType = function(ctx: Scene): ResultType return ctx.result end,
             value = ((left_value + right_value)),
         }
      ]]))
   end)


   describe("current-implementation limitations (AST needed)", function()
      it("does not change a wrapped table whose entries include inline comments", helpers.check([[
         local x = {
            alpha, -- keep alpha grouped here
            beta
         }
      ]]))

      it("does not collapse a wrapped table when a string literal contains comment text", helpers.check([[
         local x = {"--",
            beta}
      ]]))

      it("wraps a return table constructor that is too long", helpers.format([[
         return {alpha_value, beta_value, gamma_value, delta_value, epsilon_value, zeta_value, eta_value}
      ]],[[
         return {
             alpha_value,
             beta_value,
             gamma_value,
             delta_value,
             epsilon_value,
             zeta_value,
             eta_value,
         }
      ]]))

      it("joins a wrapped return table that fits on one line", helpers.format([[
         return {
            alpha_value,
            beta_value
         }
      ]],[[
         return {alpha_value, beta_value}
      ]]))

      it("joins a wrapped table whose value is a call expression", helpers.format([[
         local t = {
            key = foo(a, b)
         }
      ]],[[
         local t = {key = foo(a, b)}
      ]]))
   end)


end)
