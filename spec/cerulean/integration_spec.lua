local helpers = require("spec.cerulean.helpers")

describe("formatter integration", function()

   describe("fmt: off / fmt: on", function()
      it("does not duplicate a record declaration split by a fmt:off region", helpers.check([[
         function M () return
         -- fmt:off
         true; end global record e where
         true
         -- fmt:on
         end
      ]]))

      it("freezes an if header whose fmt:off is a trailing comment", helpers.check([=[
         if Cn -- fmt:off
         then return end
         -- fmt:on
      ]=]))

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

      it("preserves blank lines between verbatim statements inside a fmt:off block", helpers.check([[
         do
            -- fmt: off

            local function foo()
               local x = 1
            end

            local function bar()
               local y = 2
            end
         end
      ]]))

      it("preserves blank lines before off comment after block", helpers.format([[
         local function f( )
         end

         -- fmt: off
         local a  =  5
      ]], [[
         local function f()
         end

         -- fmt: off
         local a  =  5
      ]]))

      it("fmt: off after multiple comments, still formats all comments", helpers.format([[
              -- first comment
              -- second comment
           -- fmt: off
           local x = {1,  2,  3}
      ]], [[
           -- first comment
           -- second comment
           -- fmt: off
           local x = {1,  2,  3}
      ]]))

      it("fmt: off preserves blank line between pre-comment and directive", helpers.format([[
              -- comment to format

           -- fmt: off
           local x = {1,  2,  3}
      ]], [[
           -- comment to format

           -- fmt: off
           local x = {1,  2,  3}
      ]]))

      it("fmt: off after comment inside nested block, still formats comment", helpers.format([[
         local function f()
              -- comment to format
            -- fmt: off
            local x = {1,  2,  3}
         end
      ]], [[
         local function f()
             -- comment to format
            -- fmt: off
            local x = {1,  2,  3}
         end
      ]]))

      it("fmt: off after comment preserves blank line before comment", helpers.format([[
         local x = 1

              -- comment to format
            -- fmt: off
            local y = {1,  2,  3}
      ]], [[
         local x = 1

         -- comment to format
            -- fmt: off
            local y = {1,  2,  3}
      ]]))

      it("fmt: off after comment in second fmt:off region of same block", helpers.format([[
         local function demo()
            local first = one +  two
            -- fmt: off
            local frozen_a  =   one+two
            -- fmt: on
            local middle = three +  four
                 -- leading comment
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
             -- leading comment
               -- fmt: off
               local frozen_b  =   five+six
             -- fmt: on
             local last = seven + eight
         end
      ]]))

      it("fmt: off after two pre-comments with blank between them", helpers.check([[
         -- first line of logical comment

         -- second line, still before fmt: off
         -- fmt: off
         local x = {1,  2,  3}
      ]]))

      it("does not drop the closing of a multiline block comment trailing a statement in a fmt:off block", helpers.check([=[
         function a( -- fmt:off
         ) end ; --[[
         ]]
      ]=]))

      it("does not drop the closing of a multiline block comment trailing a statement in a fmt:off block", helpers.format([=[
         function a( -- keep me
         ) end ; --[[ keep me
         ]]
      ]=], [=[
         function a( -- keep me
         )
         end
         --[[ keep me
         ]]
      ]=]))

      it("keeps two back-to-back fmt:off regions frozen with no structural statement between", helpers.check([[
         -- fmt:off
         local x  =  1
         -- fmt:on
         -- fmt:off
         local y  =  2
         -- fmt:on
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
      it("wraps a long and-or expression with parenthesized concatenation chains", helpers.format([[
         local values = {
            write_text(use_first_value and ("prefix_" .. first_name_long_identifier .. first_suffix_long_identifier .. "_tail") or ("prefix_" .. second_name_long_identifier .. second_suffix_long_identifier .. "_tail")),
         }
      ]], [[
         local values = {
             write_text(
                 use_first_value
                     and (
                         "prefix_"
                         .. first_name_long_identifier
                         .. first_suffix_long_identifier
                         .. "_tail"
                     )
                     or (
                         "prefix_"
                         .. second_name_long_identifier
                         .. second_suffix_long_identifier
                         .. "_tail"
                     )
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

      it("fmt: off after comment, still formats comment", helpers.format([[
           -- comment to format
         -- fmt: off
         local x = {1,  2,  3}
      ]], [[
         -- comment to format
         -- fmt: off
         local x = {1,  2,  3}
      ]]))

      it("fmt: on before comment, still formats comment", helpers.format([[
         -- fmt: off
         local x = {1,  2,  3}
         -- fmt: on
          -- comment to format
      ]], [[
         -- fmt: off
         local x = {1,  2,  3}
         -- fmt: on
         -- comment to format
      ]]))

      it("formats anonymous function expressions with multi-statement bodies", helpers.check([[
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

      it("does not crash on bracket index followed by line comment at EOF", helpers.parse_error([[
         a[
         --
      ]]))

      it("does not duplicate fmt:off content when parse errors precede the block", helpers.check([[
         local x:a<
         -- fmt:off
         b>return
      ]]))

      it("produces stable output when fmt:off appears as trailing comment after invalid syntax", helpers.format([[
         do
         end local interface b where function(): b local enum b -- fmt:off
         end end end
      ]], [[
         do
         end
         local interface b where function(): b local enum b -- fmt:off
         end end end
      ]]))

      it("formats a trailing return sharing the last line of a fmt:off for-loop", helpers.format([[
         for d = 1,
         -- fmt:off
         x
         -- fmt:on
         do end return
      ]], [[
         for d = 1,
         -- fmt:off
         x
         -- fmt:on
         do end
         return
      ]]))

      it("keeps a trailing multi-line comment closed when fmt:off splits a function header from its body", helpers.check([=[
         function Y
         -- fmt:off
         ( ) end --[[
         ]]
      ]=]))

      it("does not drop the closing ]] of a block comment spanning lines inside a fmt:off region", helpers.check([=[
         function a
         -- fmt:off
         ()end;--[[
         ]]return
         -- fmt:on
      ]=]))

      it("formats an out-of-region declaration sharing a frozen statement's last line", helpers.format([=[
         local function f() -- fmt:off
         end --[[block comment]] local type
         A = B
      ]=], [=[
         local function f() -- fmt:off
         end --[[block comment]]
         local type A = B
      ]=]))

      it("does not duplicate a nested function declaration frozen by fmt:off", helpers.format([[
         function f1 ( ) function f2 ( )
         -- fmt:off
         end
         end
      ]], [[
         function f1()
         function f2 ( )
         -- fmt:off
         end
         end
      ]]))

      it("does not duplicate a statement split across a fmt:on directive", helpers.format([[
         x = a
         -- fmt:on
         . Y
      ]], [[
         x = a
             -- fmt:on
             .Y
      ]]))

      it("produces parseable output after formatting a fmt:off region with nested long-string delimiters in comments", helpers.check([==[
         do return function() -- fmt:off
         end;--[[
         ]]end
      ]==]))

      it("does not duplicate the fmt:off directive after a declaration with a trailing return", helpers.check([[
         local record K
         end
         return 0
         -- fmt:off
         ;
      ]]))

      it("does not duplicate the fmt:off directive when a trailing fmt:on closes the region", helpers.check([[
         local record K
         end
         return 0
         -- fmt:off
         ;

         -- fmt:on
      ]]))

      it("does not duplicate the trailing return of a fmt:off block whose last line ends a multiline comment", helpers.format([=[
         a : --[==[a]==] a { [ a is nil ] = a } function a (
         -- fmt:off
         ) local enum a end do end end --[[a
         a]] return a
         -- fmt:on
      ]=], [=[
         a: --[==[a]==]
             a({[a is nil] = a})
         function a (
         -- fmt:off
         ) local enum a end do end end --[[a
         a]] return a
         -- fmt:on
      ]=]))

      it("does not drop a leading fmt:off comment preceding a semicolon and nested record", helpers.check([[
         -- fmt:off
         ; local record r is end end
      ]]))

      it("keeps a leading comment when the semicolon it precedes is removed", helpers.format([[
         -- keep
         ; local x = 1
      ]], [[
         -- keep
         local x = 1
      ]]))

      it("keeps source order of a semicolon's leading comment and the next statement's comment", helpers.format([[
         local a = 1
         -- before semi
         ;
         -- before next
         local b = 2
      ]], [[
         local a = 1
         -- before semi

         -- before next
         local b = 2
      ]]))
   end)

   describe("pragma", function()
      it("preserves pragma directive unchanged", helpers.check([[
         --#pragma arity on
         local x = 1
      ]]))
   end)

end)
