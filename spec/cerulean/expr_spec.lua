local helpers = require("spec.cerulean.helpers")

describe("formatter function expressions", function()
   it("perserves comments in wrapped expressions", helpers.format([[
      local a = 5 * --hmm
            7
   ]], [[
      local a = 5 * --hmm
          7
   ]]))

   it("perserves comments in wrapped expressions before op", helpers.format([[
      local a = 5 --hmm
            * 7
   ]], [[
      local a = 5 --hmm
          * 7
   ]]))

   it("perserves comments both befoer and after operator in expression", helpers.format([[
      local a = 5 --hmm 1
            * -- hmm 2
            7
   ]], [[
      local a = 5 --hmm 1
          * -- hmm 2
          7
   ]]))

   it("perserves comments after unary not", helpers.format([[
      local x = not --hmm
            y
   ]], [[
      local x = not --hmm
          y
   ]]))

   it("perserves comments after unary minus", helpers.format([[
      local x = - --hmm
            5
   ]], [[
      local x = - --hmm
          5
   ]]))

   it("double unary minus preserves space to avoid producing a comment", helpers.format([[
      local x = - - y
   ]], [[
      local x = - -y
   ]]))

   it("double unary minus on table preserves space to avoid producing a comment", helpers.format([[
      return - - {}
   ]], [[
      return - -{}
   ]]))

   it("preserves comment between assignment = and value", helpers.format([[
      local x = --hmm
            5
   ]], [[
      local x = --hmm
          5
   ]]))

   it("preserves comment between return and value", helpers.format([[
      local function f()
          return --hmm
                x
      end
   ]], [[
      local function f()
          return --hmm
              x
      end
   ]]))

   it("preserves comment between if and condition", helpers.format([[
      if --hmm
            x then
      end
   ]], [[
      if --hmm
          x then
      end
   ]]))

   it("preserves comment inline with call opening paren", helpers.format([[
      f(--hmm
            5)
   ]], [[
      f(--hmm
          5
      )
   ]]))

   it("perserves comments in return statements", helpers.check([[
      local function f()
          return a -- Good to have
      end
   ]]))

   it("do not add lines after multi-line string expressions", helpers.format([=[
      local s  =  [[
      multi-line-string]]
      local x  =  1
   ]=], [=[
      local s = [[
      multi-line-string]]
      local x = 1
   ]=]))

   it("empty anonymous function renders as function() end regardless of surrounding context", helpers.format([[
      return a or function() end and {
          x = 1,
      }
   ]], [[
      return a
          or function() end
              and {
                  x = 1,
              }
   ]]))

   it("only first chain skips indention in expression chains", helpers.format([[
      local x = (some_very_very_very_long_middle_expression_identifier_that_forces_wrapping or some_very_very_very_long_middle_expression_identifier_that_forces_wrapping and some_very_very_very_long_middle_expression_identifier_that_forces_wrapping)
   ]], [[
      local x = (
          some_very_very_very_long_middle_expression_identifier_that_forces_wrapping
          or some_very_very_very_long_middle_expression_identifier_that_forces_wrapping
              and some_very_very_very_long_middle_expression_identifier_that_forces_wrapping
      )
   ]]))

   it("expression with table type is kept", helpers.format([[
      local x = not ( formatter is table)
   ]], [[
      local x = not (formatter is table)
   ]]))

   it("expression with generic multi-type", helpers.format([[
      local data:  Data<string, boolean>
   ]], [[
      local data: Data<string, boolean>
   ]]))

   it("wraps long concatenation chain", helpers.format([[
      local x = very_long_prefix_string .. very_long_middle_value .. very_long_suffix_string_here
   ]], [[
      local x = very_long_prefix_string
          .. very_long_middle_value
          .. very_long_suffix_string_here
   ]]))

   it("wraps concatenation chain with a long middle term", helpers.format([[
      local x = a_prefix .. some_very_very_very_long_middle_expression_identifier_that_forces_wrapping .. c_suffix
   ]], [[
      local x = a_prefix
          .. some_very_very_very_long_middle_expression_identifier_that_forces_wrapping
          .. c_suffix
   ]]))

   it("keeps short concatenation chain flat", helpers.check([[
      local x = a .. b .. c
   ]]))

   it("inner and chain stays flat when it fits after or separator", helpers.format([[
      local ok = first or very_long_condition_alpha_name and very_long_condition_beta_name or last
   ]], [[
      local ok = first
          or very_long_condition_alpha_name and very_long_condition_beta_name
          or last
   ]]))

   it("index with long string key preserves space to avoid tokenizer ambiguity", helpers.check([=[
      local x = t[ [[key]] ]
   ]=]))

   it("index with expression starting with long string preserves space to avoid tokenizer ambiguity", helpers.check([=[
      local x = t[ [[d]] and {} ]
   ]=]))

   it("uses semicolon after cast to function type with multi-return rets to avoid trailing comma ambiguity in wrapped tables", helpers.format([[
      return { ab_field = x is number | function(): boolean, boolean | {string: number} | nil | string }
   ]], [[
      return {
          ab_field = x is number | function(): boolean, boolean | {string: number} | nil | string;
      }
   ]]))

end)

describe("idempotency: ", function()
   it("added parentheses for operators can be wrapped directly if neccessary", helpers.format([[
      return some_condition_that_is_long_long_long_enough_to_cause_wrapping_here_now / ~ value ^ y
   ]], [[
      return some_condition_that_is_long_long_long_enough_to_cause_wrapping_here_now / (
          ~value
      ) ^ y
   ]], { skip_ast_equivalence = true }))
end)
