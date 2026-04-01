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

      it("joins a two-line call while preserving correct comma spacing", helpers.format([[
         local x = f(1,
            2)
      ]], [[
         local x = f(1, 2)
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
      it("wraps a long single-line signature to compact form", helpers.format([[
         function f(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType): ReturnValue
         end
      ]],[[
         function f(
             param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType
         ): ReturnValue
         end
      ]]))
      it("joins an already-wrapped signature that fits on one line", helpers.format([[
         function f(
            param_one: TypeA,
            param_two: TypeB
         ): ReturnType
         end
      ]],[[
         function f(param_one: TypeA, param_two: TypeB): ReturnType
         end
      ]]))

      it("does not change a short signature that is already on one line", helpers.check([[
         function f(x: integer, y: integer): integer
         end
      ]]))

      it("preserves indentation when wrapping a method signature", helpers.format([[
         function Obj:method(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType)
         end
      ]],[[
         function Obj:method(
             param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType
         )
         end
      ]]))

      it("splits a signature one parameter per line when the compact broken form is still too wide", helpers.format([[
         function f(first_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameAlpha, second_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameBeta, third_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameGamma): ReturnType
         end
      ]],[[
         function f(
             first_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameAlpha,
             second_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameBeta,
             third_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameGamma
         ): ReturnType
         end
      ]]))

      it("preserves optional and vararg parameters when wrapping a signature", helpers.format([[
         function f(required: RequiredType, optional_param?: OptionalTypeName, ...: VariadicTypeName): ReturnType
         end
      ]],[[
         function f(
             required: RequiredType, optional_param?: OptionalTypeName, ...: VariadicTypeName
         ): ReturnType
         end
      ]]))

      it("preserves source spelling for parenthesized and function parameter types", helpers.format([[
         function f(left: (Alpha | Beta), callback: function(ctx: Scene, enabled: boolean): ResultType, right: ExtremelyVerboseTypeName)
         end
      ]],[[
         function f(
             left: (Alpha | Beta),
             callback: function(ctx: Scene, enabled: boolean): ResultType,
             right: ExtremelyVerboseTypeName
         )
         end
      ]]))
   end)

   describe("indentation", function()
      it("converts leading tabs to 4-space indentation", helpers.format(
         "local function f()\n\tlocal x = 1\nend\n",
         "local function f()\n    local x = 1\nend\n"
      ))

      it("converts nested tabs to the correct number of spaces", helpers.format(
         "local function f()\n\tif true then\n\t\tlocal x = 1\n\tend\nend\n",
         "local function f()\n    if true then\n        local x = 1\n    end\nend\n"
      ))

      it("does not change lines already using 4-space indentation", helpers.check(
         "local function f()\n    local x = 1\nend\n"
      ))

      it("does not touch tabs that appear mid-line", helpers.check(
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

      it("sorts requires with non-standard spacing inside the call parens", helpers.format([[
         local b = require( "b.module" )
         local a = require( "a.module" )
      ]], [[
         local a = require("a.module")
         local b = require("b.module")
      ]], { skip_ast_equivalence = true }))

      it("sorts multi-line require declarations as a unit", helpers.format([[
         local b =
             require("b.module")
         local a =
             require("a.module")
      ]], [[
         local a =
             require("a.module")
         local b =
             require("b.module")
      ]], { skip_ast_equivalence = true }))

      it("does not sort requires inside a function body", helpers.check([[
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

   end)

   describe("quote normalisation", function()
      it("converts single-quoted strings to double quotes", helpers.format([[
         local x = 'hello'
      ]], [[
         local x = "hello"
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

   describe("function call wrapping", function()
      it("wraps a long function call to compact form", helpers.format([[
         local x = foo.new_selection(some_settings.long_field_name, minimum_value_long, maximum_value_long)
      ]], [[
         local x = foo.new_selection(
             some_settings.long_field_name, minimum_value_long, maximum_value_long
         )
      ]]))
      it("joins an already-wrapped call that fits on one line", helpers.format([[
             local x = foo.new_selection(
                 field_a,
                 field_b
             )
         ]], [[
             local x = foo.new_selection(field_a, field_b)
         ]]
      ))

      it("does not change a short call", helpers.check([[
             local x = foo.new_selection(field_a, field_b)
      ]]))

      it("re-wraps an already-wrapped call whose args line is too long", helpers.format([[
         foo.new_number(
            "long_label_here", 110, nbr_lightning_bombs_selected, settings.set_spawn_of_lightning_bombs
         )
      ]],[[
         foo.new_number(
             "long_label_here",
             110,
             nbr_lightning_bombs_selected,
             settings.set_spawn_of_lightning_bombs
         )
      ]]))

      it("wrap the inner function and do not touch outer function", helpers.format([[
         table.insert(
             parts,
             indentation .. self.name .. ": " .. string.format("%.1f", self.elapsed * 1000) .. "ms"
         )
      ]], [[
         table.insert(
             parts,
             indentation .. self.name .. ": " .. string.format(
                "%.1f", self.elapsed * 1000
             ) .. "ms"
         )
      ]]))

      it("wrap the second inner function as it is the one to reduce line lenght", helpers.format([[
         table.insert(
             self.trophy_positions,
             points.new(get_x_pos(i, #names) - self.trophy.width / 2, (screen.HEIGHT - self.trophy.height) / 2)
         )
      ]], [[
         table.insert(
             self.trophy_positions,
             points.new(
                 get_x_pos(i, #names) - self.trophy.width / 2,
                 (screen.HEIGHT - self.trophy.height) / 2
             )
         )
      ]]))

      it("wraps a call with trailing content to compact broken form when it fits", helpers.format([[
         local formatted = string.format("%.1f", elapsed_milliseconds_long_value, maximum_precision) .. "ms"
      ]], [[
         local formatted = string.format(
            "%.1f", elapsed_milliseconds_long_value, maximum_precision
         ) .. "ms"
      ]]))

      it("preserves source spelling for parenthesized and complex call arguments", helpers.format([[
         local result = process.deep_call(((left_value + right_value)), function(ctx: Scene, enabled: boolean): ResultType return ctx.result end, trailing_argument_with_a_very_long_name)
      ]], [[
         local result = process.deep_call(
             ((left_value + right_value)),
             function(ctx: Scene, enabled: boolean): ResultType return ctx.result end,
             trailing_argument_with_a_very_long_name
         )
      ]]))

      it("preserves anonymous function arguments with a local declaration body", helpers.format([[
         local result = process.deep_call(function() local current_value: ResultType = compute_result() end, trailing_argument_with_a_very_long_name)
      ]], [[
         local result = process.deep_call(
             function() local current_value: ResultType = compute_result() end,
             trailing_argument_with_a_very_long_name
         )
      ]]))

      it("preserves anonymous function arguments with an assignment body", helpers.format([[
         local result = process.deep_call(function() current_value = compute_result() end, trailing_argument_with_a_very_long_name)
      ]], [[
         local result = process.deep_call(
             function() current_value = compute_result() end,
             trailing_argument_with_a_very_long_name
         )
      ]]))

      it("does not collapse an expanded call whose closing paren has trailing content", helpers.check([[
         return interval_overlap(
             self.x,
             self.x + self.width,
             other.x,
             other.x + other.width
         ) and
             interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
      ]]))

      it("collapse the function arguments to single own line if possible", helpers.format([[
         local function interval_overlap(
             xmin1: number,
             xmax1: number,
             xmin2: number,
             xmax2: number
         ): boolean
         end
      ]], [[
         local function interval_overlap(
             xmin1: number, xmax1: number, xmin2: number, xmax2: number
         ): boolean
         end
      ]]))
   end)

   describe("current-implementation limitations (AST needed)", function()
      it("does not treat a commented-out function line as a signature", helpers.check([[
         -- local function foo(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherLongType)
      ]]))

      it("joins a wrapped call containing nested call and table arguments when they are already compact", helpers.format([[
         local x = f(g(1, 2),
            {alpha = 1, beta = 2})
      ]],[[
         local x = f(g(1, 2), {alpha = 1, beta = 2})
      ]]))

      it("does not change a wrapped call whose arguments include inline comments", helpers.check([[
         local x = f(
            alpha, -- keep alpha grouped here
            beta
         )
      ]]))

      it("does not change a wrapped table whose entries include inline comments", helpers.check([[
         local x = {
            alpha, -- keep alpha grouped here
            beta
         }
      ]]))

      it("does not collapse a wrapped call when a string literal contains comment text", helpers.check([[
         local x = f("--",
            beta)
      ]]))

      it("does not collapse a wrapped table when a string literal contains comment text", helpers.check([[
         local x = {"--",
            beta}
      ]]))

      it("wraps a long anonymous function signature", helpers.format([[
         local callback = function(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType): ReturnValue
         end
      ]],[[
         local callback = function(
             param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType
         ): ReturnValue
         end
      ]]))

      it("joins a wrapped anonymous function signature that fits on one line", helpers.format([[
         local callback = function(
            param_one: TypeA,
            param_two: TypeB
         ): ReturnType
         end
      ]],[[
         local callback = function(param_one: TypeA, param_two: TypeB): ReturnType
         end
      ]]))

      it("wraps a long call whose argument is a string containing a closing paren", helpers.format([[
         local x = my_func("closing)paren", argument_two_long, argument_three_long, argument_four_and_five_long_long)
      ]],[[
         local x = my_func(
             "closing)paren",
             argument_two_long,
             argument_three_long,
             argument_four_and_five_long_long
         )
      ]]))

      it("collapses a call where arguments would fix on their own line", helpers.format([[
         local x = my_func("closing)paren", argument_two, argument_three, argument_four_and_five_long)
      ]],[[
         local x = my_func(
             "closing)paren", argument_two, argument_three, argument_four_and_five_long
         )
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

   describe("combined signature and call rewriting", function()
      -- When a multi-line signature is compacted (reducing line count), call
      -- spans in the function body must still be resolved against the correct
      -- output lines, not the original source line numbers.
      it("correctly joins a call inside a function whose signature was compacted", helpers.format([[
         function some_module.new(
             menu_choices: {string},
             go_back: function(),
             on_load: function()
         ): string
             baz(
                 arg1,
                 arg2
             )
         end
      ]],[[
         function some_module.new(
             menu_choices: {string}, go_back: function(), on_load: function()
         ): string
             baz(arg1, arg2)
         end
      ]]))
   end)

end)
