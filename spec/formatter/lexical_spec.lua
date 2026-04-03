local helpers = require("spec.formatter.helpers")

describe("formatter lexical transforms", function()

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

      it("does not touch operators where the next token is on the next line", helpers.format([[
         local x = 1 +
            2
      ]], [[
         local x = 1 + 2
      ]]))
   end)

   describe("quote normalisation", function()
      it("converts single-quoted strings to double quotes", helpers.format([[
         local x = 'hello'
      ]], [[
         local x = "hello"
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

end)
