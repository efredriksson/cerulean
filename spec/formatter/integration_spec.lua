local helpers = require("spec.formatter.helpers")

describe("formatter integration", function()


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

   describe("multi-line expressions in local declarations", function()
      it("does not collapse a call inside a table when the joined line would exceed 88 columns", helpers.check([[
         local START_POSITION_OF_SIDE = {
             down = PLAYER_AREA:top_left():move(
                 vectors.new(PLAYER_AREA.width, PLAYER_AREA.height)
             ),
             left = PLAYER_AREA:top_left():move(vectors.new(0, PLAYER_AREA.height)),
         }

         function rail.get_side(position: number): string
             return position
         end
      ]]))

      it("preserves mixed attributes in a multi-local declaration assigned from a multi-return call", helpers.check([[
         local function get_pair(): number, number
             return 1, 2
         end

         local first <const>, second <total> = get_pair()
      ]]))
   end)

   describe("resilience", function()
      it("returns an empty file unchanged", helpers.check([[
      ]]))

      it("returns a file with only comments unchanged", helpers.check([[
         -- this is a comment
         -- another comment
      ]]))

      it("preserves leading unattached comments before a structurally renderable block", helpers.check([[
         -- This ...
         local record A
             data: string
         end

         return A
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

end)
