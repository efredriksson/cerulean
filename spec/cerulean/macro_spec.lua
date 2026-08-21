local helpers = require("spec.cerulean.helpers")
local toolchain = require("spec.cerulean.toolchain")

-- Only the unreleased Teal lexes `!` and macro quotes. Against a released one the
-- source below cannot even be tokenised, so these report as pending instead of
-- failing; CI's test-teal-dev job is where they run.
local macro_it = toolchain.supports_macros() and it or pending

describe("formatter local macros", function()

   macro_it("normalises spacing in a declaration and its invocation", helpers.format([[
      local macro bitsToWords!( nExpr : Expression )
         return `rshift($nExpr + 31, 5)`
      end

      local words=bitsToWords!( capacity )
   ]], [[
      local macro bitsToWords!(nExpr: Expression)
          return `rshift($nExpr + 31, 5)`
      end

      local words = bitsToWords!(capacity)
   ]]))

   macro_it("keeps a statement quote verbatim", helpers.check([[
      local macro markDirty!(archExpr: Expression)
          return ```
              if $archExpr.dirty then
                  $archExpr.queued = true
              end
          ```
      end

      markDirty!(archetype)
   ]]))

   macro_it("keeps a macro without arguments or return types", helpers.check([[
      local macro hello!()
          return `print("hi")`
      end

      hello!()
   ]]))

   macro_it("keeps type arguments on a generic macro", helpers.check([[
      local macro foo!<T>(x: Expression): T
          return `$x`
      end
   ]]))

   macro_it("parenthesises a string argument", helpers.format([[
      local macro show!(x: Expression)
          return `print($x)`
      end

      show!"str"
   ]], [[
      local macro show!(x: Expression)
          return `print($x)`
      end

      show!("str")
   ]]))

   macro_it("parenthesises a table argument", helpers.format([[
      local macro show!(x: Expression)
          return `print($x)`
      end

      show!{a = 1}
   ]], [[
      local macro show!(x: Expression)
          return `print($x)`
      end

      show!({a = 1})
   ]]))

   macro_it("wraps a long macro signature", helpers.format([[
      local macro apply_transform!(callback_expression: Expression, fallback_expression: Expression): Statement
          return `$callback_expression`
      end
   ]], [[
      local macro apply_transform!(
          callback_expression: Expression, fallback_expression: Expression
      ): Statement
          return `$callback_expression`
      end
   ]]))

   macro_it("wraps a long invocation like any other call", helpers.format([[
      local result = accumulate_offsets!(first_argument_value, second_argument_value, third_value)
   ]], [[
      local result = accumulate_offsets!(
          first_argument_value, second_argument_value, third_value
      )
   ]]))

   macro_it("normalises a quote passed to a call inside a macro body", helpers.format([[
      local macro outer!(x: Expression)
          return emit(  `$x`  )
      end
   ]], [[
      local macro outer!(x: Expression)
          return emit(`$x`)
      end
   ]]))

   it("reads 'macro' as a variable name when no macro name follows", helpers.check([[
      local macro = 1
   ]]))

end)
