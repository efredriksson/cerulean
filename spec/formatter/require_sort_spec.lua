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

   it("sorts all top-level requires into one group and removes blank lines between them", helpers.format([[
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

   it("does not sort requires after a non-require statement", helpers.check([[
      local a = require("a")
      local x = 1
      local b = require("b")
   ]]))

   it("does not sort local type requires", helpers.check([[
      local type B = require("b")
      local type A = require("a")
   ]]))

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

   it("removes blank lines from an already-sorted require block", helpers.format([[
      local a = require("a")

      local b = require("b")
   ]], [[
      local a = require("a")
      local b = require("b")
   ]], { skip_ast_equivalence = true }))

   it("stops sorting at a fmt:off region", helpers.check([[
      -- fmt:off
      local b = require("b")
      local a = require("a")
      -- fmt:on
   ]]))

   it("stops sorting at the first non-require statement", helpers.check([[
      local a = require("a")
      local x = 1
      local b = require("b")
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

   it("keep trailing comments on sorted require statement", helpers.format([[
      local b = require("b") -- keep this where it is
      local a = require("a")
   ]], [[
      local a = require("a")
      local b = require("b") -- keep this where it is
   ]], { skip_ast_equivalence = true }))

   it("excludes multi-local declarations with require from the sort block", helpers.check([[
      local b <const>, extra = require("b"), 1
      local a <total> = require("a")
   ]]))

   it("blank line after require group", helpers.format([[
      local b = require("b")

      local a = require("a")

      local type A = b.A
   ]], [[
      local a = require("a")
      local b = require("b")

      local type A = b.A
   ]], { skip_ast_equivalence = true }))

   it("leading attached comment before stays as module doc", helpers.check([[
      -- load order matters
      local a = require("a")
      local b = require("b")
   ]]))

   it("leading attached comment before is assumed to be module doc", helpers.format([[
      -- module documentation
      local b = require("b")
      local a = require("a")
   ]], [[
      -- module documentation
      local a = require("a")
      local b = require("b")
   ]], { skip_ast_equivalence = true }))

   it("leading floating comments are module doc and not pushed down", helpers.format([[
      -- module documentation 1

      -- module documentation 2

      -- attached
      local b = require("b")
      local a = require("a")
   ]], [[
      -- module documentation 1

      -- module documentation 2

      local a = require("a")
      -- attached
      local b = require("b")
   ]], { skip_ast_equivalence = true }))

   it("leading floating comments are module doc and not connected with pushed up attached comment", helpers.format([[
      -- module documentation 1

      -- module documentation 2

      -- attached 2
      local b = require("b")
      -- attached 1
      local a = require("a")
   ]], [[
      -- module documentation 1

      -- module documentation 2

      -- attached 1
      local a = require("a")
      -- attached 2
      local b = require("b")
   ]], { skip_ast_equivalence = true }))

   it("leading floating comment blocks are module doc and spacing is perserved", helpers.format([[
      -- module documentation 1

      -- module documentation 2
      -- module documentation 3

      -- module documentation 4

      local b = require("b")
      local a = require("a")
   ]], [[
      -- module documentation 1

      -- module documentation 2
      -- module documentation 3

      -- module documentation 4

      local a = require("a")
      local b = require("b")
   ]], { skip_ast_equivalence = true }))

   it("multiple leading attached are module doc and kept in place", helpers.format([[
      -- module documentation 1
      -- module documentation 2
      local b = require("b")
      local a = require("a")
   ]], [[
      -- module documentation 1
      -- module documentation 2
      local a = require("a")
      local b = require("b")
   ]], { skip_ast_equivalence = true }))

   it("leading floating block comment is module doc and is perserved", helpers.format([=[
      --[[
      this is a
      documented module
      ]]

      local b = require("b")
      local a = require("a")
   ]=], [=[
      --[[
      this is a
      documented module
      ]]

      local a = require("a")
      local b = require("b")
   ]=], { skip_ast_equivalence = true }))

   it("comment attached between already-sorted requires is left in place", helpers.check([[
      local a = require("a")
      -- section break
      local b = require("b")
   ]]))

   it("comment floating between already-sorted requires is pushed out to end", helpers.format([[
      local b = require("b")

      -- i am floating!
      
      local a = require("a")
   ]], [[
      local a = require("a")
      local b = require("b")

      -- i am floating!
   ]], { skip_ast_equivalence = true }))

   it("comment floating between already-sorted requires is pushed out before next stmt", helpers.format([[
      local b = require("b")

      -- i am floating!
      
      local a = require("a")

      local x = 1
   ]], [[
      local a = require("a")
      local b = require("b")

      -- i am floating!

      local x = 1
   ]], { skip_ast_equivalence = true }))

   it("comments floating between are all pushed out", helpers.format([[
      local b = require("b")

      -- i am floating 3
      
      local a = require("a")

      -- i am floating 2

      -- i am floating 1

      local c = require("c")
   ]], [[
      local a = require("a")
      local b = require("b")
      local c = require("c")

      -- i am floating 3

      -- i am floating 2

      -- i am floating 1
      ]], { skip_ast_equivalence = true }))

   it("attached comment above require travels with it", helpers.format([[
      local b = require("b")
      local a = require("a")
      -- section break
      local d = require("d")
      local c = require("c")
   ]], [[
      local a = require("a")
      local b = require("b")
      local c = require("c")
      -- section break
      local d = require("d")
   ]], { skip_ast_equivalence = true }))

   it("comment immediately after last require does not join the sort block", helpers.check([[
      local a = require("a")
      local b = require("b")
      -- end of requires
   ]]))

   it("blank line before comment and require is removed", helpers.format([[
      local a = require("a")

      -- lazy load
      local b = require("b")
   ]], [[
      local a = require("a")
      -- lazy load
      local b = require("b")
   ]], { skip_ast_equivalence = true }))

   it("trailing comment moves with require when sorted to first position", helpers.format([[
      local b = require("b") -- important
      local a = require("a")
      local c = require("c")
   ]], [[
      local a = require("a")
      local b = require("b") -- important
      local c = require("c")
   ]], { skip_ast_equivalence = true }))

   it("trailing comments follow on sort", helpers.format([[
      local b = require("b") -- second
      local a = require("a") -- first
   ]], [[
      local a = require("a") -- first
      local b = require("b") -- second
   ]], { skip_ast_equivalence = true }))

   it("trailing comments follow on sort", helpers.format([[
      local b = require("b") -- second
      local a = require("a") -- first
   ]], [[
      local a = require("a") -- first
      local b = require("b") -- second
   ]], { skip_ast_equivalence = true }))

   it("check with both many module doc and statment after with space", helpers.format([[
      -- first line of doc
      -- second line of doc
      local b = require("b")
      local a = require("a")

      local type A = a.A
   ]], [[
      -- first line of doc
      -- second line of doc
      local a = require("a")
      local b = require("b")

      local type A = a.A
   ]], { skip_ast_equivalence = true }))

   it("block comment that are attached also follows on sort", helpers.format([=[
      local b = require("b")
      local a = require("a")
      --[[
      this is a
      block comment
      ]]
      local d = require("d")
      local c = require("c")
   ]=], [=[
      local a = require("a")
      local b = require("b")
      local c = require("c")
      --[[
      this is a
      block comment
      ]]
      local d = require("d")
   ]=], { skip_ast_equivalence = true }))

   it("block comment that are floating is pushed down", helpers.format([=[
      local b = require("b")
      local a = require("a")

      --[[
      this is a floating
      block comment
      ]]

      local d = require("d")
      local c = require("c")
   ]=], [=[
      local a = require("a")
      local b = require("b")
      local c = require("c")
      local d = require("d")

      --[[
      this is a floating
      block comment
      ]]
   ]=], { skip_ast_equivalence = true }))
end)
