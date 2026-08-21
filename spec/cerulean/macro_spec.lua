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

-- A parameter annotated `Statement` takes a whole statement, so the invocation can
-- hold something that is not an expression at all. Reading those needs the macro's
-- declared signature, which the parser keeps per file.
describe("formatter macro statement arguments", function()

   macro_it("formats an assignment argument", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(z=3)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(z = 3)
   ]]))

   macro_it("formats a declaration argument", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(local q   =  5)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(local q = 5)
   ]]))

   macro_it("gives a block statement argument its own lines", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(if c then y=1 end)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          if c then
              y = 1
          end
      )
   ]]))

   macro_it("formats a call argument", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(print( 1 ))
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(print(1))
   ]]))

   macro_it("keeps a comment inside a statement argument", helpers.check([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          -- keep me
          z = 3
      )
   ]]))

   macro_it("keeps a comment before the closing paren", helpers.check([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          z = 3
          -- dangling
      )
   ]]))

   macro_it("gives every statement of a do block its own line", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(do a=1 b=2 end)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          do
              a = 1
              b = 2
          end
      )
   ]]))

   -- Nothing follows the only parameter, so the commas belong to the statement.
   macro_it("keeps a top-level comma inside the last statement argument", helpers.check([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(a, b = 1, 2)
   ]]))

   -- A statement argument may not contain a top-level comma when another argument
   -- follows it, so the first one ends it and the expression after reads normally.
   macro_it("splits a statement argument at the first comma", helpers.format([[
      local macro pair!(a: Statement, b: Expression)
          return ```
              $a
              print($b)
          ```
      end

      pair!(z=3,   7)
   ]], [[
      local macro pair!(a: Statement, b: Expression)
          return ```
              $a
              print($b)
          ```
      end

      pair!(z = 3, 7)
   ]]))

   macro_it("reads every argument of a Statement vararg as a statement", helpers.format([[
      local macro all!(...: Statement)
          return ```
              $1
          ```
      end

      all!(z=3,  y=4)
   ]], [[
      local macro all!(...: Statement)
          return ```
              $1
          ```
      end

      all!(z = 3, y = 4)
   ]]))

   macro_it("formats a record declaration argument", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(record Foo x:integer end)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          record Foo
              x: integer
          end
      )
   ]]))

   macro_it("formats an enum declaration argument", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(enum Color "red" "blue" end)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          enum Color
              "red"
              "blue"
          end
      )
   ]]))

   macro_it("formats an interface declaration argument", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(interface Shape area: function(): number end)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          interface Shape
              area: function(): number
          end
      )
   ]]))

   macro_it("keeps type arguments on a record declaration argument", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(record Box<T> item: T end)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          record Box<T>
              item: T
          end
      )
   ]]))

   macro_it("formats two declarations in one argument", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(record A x:integer end record B y:integer end)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          record A
              x: integer
          end
          record B
              y: integer
          end
      )
   ]]))

   -- Teal rejects a string here; the formatter still has to produce something, and
   -- reading the argument as an expression is what it did before it knew signatures.
   macro_it("falls back to an expression when the argument is not a statement", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!"str"
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!("str")
   ]]))

   macro_it("reads the arguments of an undeclared macro as expressions", helpers.check([[
      local x = undeclared!(a, b)
   ]]))

end)
