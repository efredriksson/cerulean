local helpers = require("spec.formatter.helpers")

describe("formatter function expressions", function()

   -- Supporting mid-expression comments (e.g. `5 * --hmm\n  7`) requires:
   -- 1. Extracting comments in the Pratt E() function for binary op RHS tokens
   --    and attaching them to the RHS node (parser.tl).
   -- 2. Rendering those comments inline after the operator with a forced
   --    indented line break in render_op (expr_doc.tl).
   -- This also interacts with the generic trailing_comment rendering design
   -- question in render_expr (call_doc double-render conflict).
   pending("perserves comments in wrapped expressions", helpers.format([[
      local a = 5 * --hmm
            7
   ]], [[
      local a = 5 * --hmm
          7
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
end)
