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

      it("keeps structural formatting enabled around fmt:off in the same block", helpers.format([[
         local function demo()
            local before = one +  two
            -- fmt: off
            local frozen  =   one+two
            -- fmt: on
            local after = three +  four
         end
      ]], [[
         local function demo()
             local before = one + two
            -- fmt: off
            local frozen  =   one+two
             -- fmt: on
             local after = three + four
         end
      ]]))

      it("supports multiple fmt:off regions in a single block", helpers.format([[
         local function demo()
            local first = one +  two
            -- fmt: off
            local frozen_a  =   one+two
            -- fmt: on
            local middle = three +  four
            -- fmt: off
            local frozen_b  =   five+six
            -- fmt: on
            local last = seven +  eight
         end
      ]], [[
         local function demo()
             local first = one + two
            -- fmt: off
            local frozen_a  =   one+two
             -- fmt: on
             local middle = three + four
            -- fmt: off
            local frozen_b  =   five+six
             -- fmt: on
             local last = seven + eight
         end
      ]]))

      it("keeps nested fmt:off region frozen while formatting sibling statements", helpers.format([[
         local function nested()
            if enabled then
               local before = one +  two
               -- fmt: off
               local frozen  =   one+two
               -- fmt: on
               local after = three +  four
            end
         end
      ]], [[
         local function nested()
             if enabled then
                 local before = one + two
               -- fmt: off
               local frozen  =   one+two
                 -- fmt: on
                 local after = three + four
             end
         end
      ]]))

      it("keeps a nested literal block unchanged inside fmt:off", helpers.check([[
         local config = {
             entries = {
               -- fmt: off
               ALPHA = 1,
               BETA  = 2,
               -- fmt: on
             },
         }
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

   describe("line width guards", function()
      it("does not collapse a wrapped and-or call argument when the single-line form would exceed 88 columns", helpers.format([[
         local values = {
            write_text(use_first_value and ("prefix_" .. first_name_long_identifier .. first_suffix_long_identifier .. "_tail") or ("prefix_" .. second_name_long_identifier .. second_suffix_long_identifier .. "_tail")),
         }
      ]], [[
         local values = {
             write_text(
                 use_first_value and ("prefix_" .. first_name_long_identifier .. first_suffix_long_identifier .. "_tail")
                     or ("prefix_" .. second_name_long_identifier .. second_suffix_long_identifier .. "_tail")
             ),
         }
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

      it("does not crash on anonymous function expressions with unsupported statement kinds", helpers.check([[
         local value = function()
             if enabled then
                 return 1
             end
         end
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
