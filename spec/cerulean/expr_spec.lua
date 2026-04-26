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

   -- comment before the top-level expression (between keyword/punctuation and value).
   -- Requires leading_inline_comment on Node + stmt_doc changes to render it inline.
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

   it("empty anonymous function renders as function() end regardless of surrounding context", helpers.format([[
      return a or function() end and {
          x = 1,
      }
   ]], [[
      return a
          or function() end and {
          x = 1,
      }
   ]]))

   pending("expression with table type is kept", helpers.format([[
      local x = not ( formatter is table)
   ]], [[
      local x = not (formatter is table)
   ]]))

   it("expression with generic multi-type", helpers.format([[
      local data:  Data<string, boolean>
   ]], [[
      local data: Data<string, boolean>
   ]]))

end)
