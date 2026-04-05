local helpers = require("spec.formatter.helpers")

describe("formatter require sorting", function()

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

   it("sorts attributed local requires and preserves const/total attributes", helpers.format([[
      local b <const> = require("b")
      local a <total> = require("a")
   ]], [[
      local a <total> = require("a")
      local b <const> = require("b")
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

   it("excludes multi-local declarations with require from the sort block", helpers.check([[
      local b <const>, extra = require("b"), 1
      local a <total> = require("a")
   ]]))

end)
