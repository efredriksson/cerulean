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

      it("does not touch commas where the next token is on the next line", helpers.check([[
         local x = f(1,
            2)
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

      it("handles all comparison and logical operators", helpers.format([[
         if a==b or c~=d and e<f or g>h and i<=j or k>=l then end
      ]], [[
         if a == b or c ~= d and e < f or g > h and i <= j or k >= l then end
      ]]))

      it("does not add spaces around unary minus", helpers.check([[
         local x = -1
         local y = f(-1, -2)
         local z = 1 + -1
      ]]))

      it("does not touch Teal attribute brackets", helpers.check([[
         local x <const> = 1
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

   describe("quote normalisation", function()
      it("converts single-quoted strings to double quotes", helpers.format([[
         local x = 'hello'
      ]], [[
         local x = "hello"
      ]]))
   end)

end)
