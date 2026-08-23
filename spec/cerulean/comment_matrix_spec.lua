local helpers = require("spec.cerulean.helpers")

describe("formatter comment matrix (single-line)", function()
   describe("single block cases", function()
      it("[function|single|leading_before_first|call_arg_comment_blocked]", helpers.format([[
         local function f()
           -- before first statement
           call(
             -- arg comment
             x,
             y
           )
           return x
         end
      ]], [[
         local function f()
             -- before first statement
             call(
                 -- arg comment
                 x,
                 y
             )
             return x
         end
      ]]))

      it("[function|single|leading_between|call_arg_comment_blocked]", helpers.format([[
         local function f()
           local x = 1
           -- between statements
           call(
             -- arg comment
             x
           )
           return x
         end
      ]], [[
         local function f()
             local x = 1
             -- between statements
             call(
                 -- arg comment
                 x
             )
             return x
         end
      ]]))

      it("[function|single|trailing_last|call_arg_comment_blocked]", helpers.format([[
         local function f()
           call(
             -- arg comment
             x
           ) -- trailing on last statement
         end
      ]], [[
         local function f()
             call(
                 -- arg comment
                 x
             ) -- trailing on last statement
         end
      ]]))

      it("[function|single|between_last_and_end|call_arg_comment_blocked]", helpers.format([[
         local function f()
           call(
             -- arg comment
             x
           )
           -- before end
         end
      ]], [[
         local function f()
             call(
                 -- arg comment
                 x
             )
             -- before end
         end
      ]]))

      it("[if|single|leading_before_first|call_arg_comment_blocked]", helpers.format([[
         if cond then
           -- before first statement
           call(
             -- arg comment
             x
           )
           return x
         end
      ]], [[
         if cond then
             -- before first statement
             call(
                 -- arg comment
                 x
             )
             return x
         end
      ]]))

      it("[if|single|trailing_last|call_arg_comment_blocked]", helpers.format([[
         if cond then
           call(
             -- arg comment
             x
           ) -- trailing on last statement
         end
      ]], [[
         if cond then
             call(
                 -- arg comment
                 x
             ) -- trailing on last statement
         end
      ]]))

      it("[if|single|between_last_and_end|call_arg_comment_blocked]", helpers.format([[
         if cond then
           call(
             -- arg comment
             x
           )
           -- before end
         end
      ]], [[
         if cond then
             call(
                 -- arg comment
                 x
             )
             -- before end
         end
      ]]))

      it("[record_function|single|leading_between|call_arg_comment_blocked]", helpers.format([[
         function Obj.value(): integer
           local x = 1
           -- between statements
           call(
             -- arg comment
             x
           )
           return x
         end
      ]], [[
         function Obj.value(): integer
             local x = 1
             -- between statements
             call(
                 -- arg comment
                 x
             )
             return x
         end
      ]]))

      it("[record_function|single|consecutive_end_comments|call_arg_comment_blocked]", helpers.format([[
         function Obj.value(): integer
           call(
             -- arg comment
             x
           )
           -- before end 1
           -- before end 2
         end
      ]], [[
         function Obj.value(): integer
             call(
                 -- arg comment
                 x
             )
             -- before end 1
             -- before end 2
         end
      ]]))

      it("[record|single|leading_before_first|top_level_comment_prelude]", helpers.format([[
         -- top-level prelude comment
         local record Box
           value: integer -- inline field comment
           -- end comment
         end
      ]], [[
         -- top-level prelude comment
         local record Box
             value: integer -- inline field comment
             -- end comment
         end
      ]]))

      it("[enum|single|leading_before_first|top_level_comment_prelude]", helpers.format([[
         -- top-level prelude comment
         local enum E
           "a" -- inline value comment
           -- end comment
         end
      ]], [[
         -- top-level prelude comment
         local enum E
             "a" -- inline value comment
             -- end comment
         end
      ]]))
   end)

   -- A block comment in the name->first-item gap is body-owned: it leads the first
   -- item on its own line. The header must not also read it (that double-counts the
   -- comment and safe-skips the whole file to verbatim).
   describe("enum/record name block comment", function()
      it("[enum|name_block|leads_first_item]", helpers.format([==[
         local enum E --[[c]] "x" end
      ]==], [==[
         local enum E
             --[[c]]
             "x"
         end
      ]==]))

      it("[enum|name_block|global|leads_first_item]", helpers.format([==[
         global enum E --[[c]] "x" end
      ]==], [==[
         global enum E
             --[[c]]
             "x"
         end
      ]==]))

      it("[record|name_block|leads_first_field]", helpers.format([==[
         local record R --[[c]] x: integer end
      ]==], [==[
         local record R
             --[[c]]
             x: integer
         end
      ]==]))

      it("[record>enum|nested|name_block|leads_first_item]", helpers.format([==[
         local record Box
             enum Color --[[c]] "red" end
         end
      ]==], [==[
         local record Box
             enum Color
                 --[[c]]
                 "red"
             end
         end
      ]==]))

      it("[record|name_block|empty_body_dangles]", helpers.format([==[
         local record R --[[c]] end
      ]==], [==[
         local record R
             --[[c]]
         end
      ]==]))

      it("[enum|name_block|empty_body_dangles]", helpers.format([==[
         local enum E --[[c]] end
      ]==], [==[
         local enum E
             --[[c]]
         end
      ]==]))

      it("[table|empty|only_comment_dangles]", helpers.format([==[
         local t = { --[[c]] }
      ]==], [==[
         local t = {
             --[[c]]
         }
      ]==]))

      it("[record|field|trailing_line_comment]", helpers.check([[
         local record R
             x: number -- c
         end
      ]]))

      -- A nested type alias's value-trailing block comment must be read once (the
      -- value's trailing), not also by the header. The nested newtype node spans the
      -- value, so a header-gap read off it would re-claim the value's trailing and
      -- duplicate it (`type --[[c]] T = boolean --[[c]]`).
      it("[record>type_alias|nested|value_trailing_block|no_dup]", helpers.check([==[
         local record R
             type T = boolean --[[c]]
         end
      ]==]))

      -- A bare `userdata` marker mid-body (hoisted into the header's `is` clause,
      -- unlike a real interface-list entry) has no true leading anchor: whatever
      -- token happens to precede it in source is unrelated, here the preceding
      -- nested alias's own value-trailing comment. Reading it as userdata's inline
      -- leading too would duplicate it.
      it("[record>type_alias|nested|bare_userdata_after_value_trailing_block|no_dup]", helpers.format([==[
         local record R
             type T = boolean --[[c]] userdata
         end
      ]==], [==[
         local record R is userdata
             type T = boolean --[[c]]
         end
      ]==]))

      -- A block comment in the name gap (before a `=`/`is`) has no slot; the
      -- per-statement sweep relocates it to the statement's own-line leading.
      it("[enum|name_block|type_alias_relocates_to_leading]", helpers.format([==[
         local type E --[[c]] = enum "a" end
      ]==], [==[
         --[[c]]
         local type E = enum
             "a"
         end
      ]==]))

      it("[record|name_block|is_clause_relocates_to_leading]", helpers.format([==[
         local interface I end
         local record R --[[c]] is I x: integer end
      ]==], [==[
         local interface I
         end
         --[[c]]
         local record R is I
             x: integer
         end
      ]==]))

      -- A line comment after the name was always body-owned (header reads only block
      -- comments), so this placement must be unchanged by the fix.
      it("[enum|name_line|leads_first_item]", helpers.format([[
         local enum E -- c
             "x"
         end
      ]], [[
         local enum E
             -- c
             "x"
         end
      ]]))
   end)

   -- A line comment trailing an interior header keyword (`local record -- c`)
   -- can't sit inline (it runs to end of line), so the per-statement sweep moves it
   -- to the statement's own-line leading -- the only idempotent home for a stray.
   describe("header keyword run line comment", function()
      it("[record|header_kw_line|relocates_to_leading]", helpers.format([[
         local record -- c
             R
             x: integer
         end
      ]], [[
         -- c
         local record R
             x: integer
         end
      ]]))

      it("[interface|header_kw_line|relocates_to_leading]", helpers.format([[
         local interface -- c
             I
             x: integer
         end
      ]], [[
         -- c
         local interface I
             x: integer
         end
      ]]))

      it("[enum|header_kw_line|relocates_to_leading]", helpers.format([[
         local enum -- c
             E
             "x"
         end
      ]], [[
         -- c
         local enum E
             "x"
         end
      ]]))

      -- A block comment in the same gap relocates too: the sweep is the one home
      -- for every comment without a kept slot, line or block alike.
      it("[record|header_kw_block|relocates_to_leading]", helpers.format([==[
         local record --[[c]] R
             x: integer
         end
      ]==], [==[
         --[[c]]
         local record R
             x: integer
         end
      ]==]))
   end)

   -- A line comment trailing a type declaration's top-level `=` can't sit inline,
   -- so the per-statement sweep moves it to the statement's own-line leading.
   describe("declaration = line comment", function()
      it("[local_type|eq_line|relocates_to_leading]", helpers.format([[
         local type T = -- c
             integer
      ]], [[
         -- c
         local type T = integer
      ]]))

      -- Control: an expression value's leading run already collects the `=`-trailing
      -- comment, so a plain declaration is left untouched (relocating would dup it).
      it("[local_decl|eq_line|unchanged]", helpers.check([[
         local x = -- c
             1
      ]]))
   end)

   -- Regression: a line comment after the opening keyword and a genuine block
   -- comment trailing the value once shared the inline trailing slot, where the
   -- line comment ran to end of line and swallowed the block
   -- (`local x = 1 -- a --[[b]]`, dropping `--[[b]]`). The line comment now sweeps
   -- to own-line leading; the block stays genuine same-line trailing.
   describe("keyword line comment beside a trailing block", function()
      it("[local|keyword_line+value_block|no_swallow]", helpers.format([=[
         local -- a
         x = 1 --[[b]]
      ]=], [=[
         -- a
         local x = 1 --[[b]]
      ]=]))
   end)

   -- Several line comments stranded deep in one statement's type/expression can't
   -- relocate to the trailing (it joins comments on one line, which re-lexes as a
   -- single comment), so the per-statement sweep moves each to the statement's
   -- own-line leading -- the only idempotent home for a multi-comment strand.
   describe("stranded line comment sweep", function()
      it("[local_type|multi_drop|sweeps_to_leading]", helpers.format([[
         local type T =
             integer -- a
             | string -- b
             | boolean
      ]], [[
         -- a
         -- b
         local type T = integer | string | boolean
      ]]))

      -- Parking this one after the type instead would move it past the `:`, where
      -- the next pass reads it off a different token and sweeps it anyway.
      it("[local_decl|name_line|sweeps_to_leading]", helpers.format([[
         local x -- c
         : integer = 1
      ]], [[
         -- c
         local x: integer = 1
      ]]))

      -- Control: item-trailing comments already have a slot, so the sweep must not
      -- relocate them too (a dup would trip the audit and the file would safe-skip).
      it("[table|item_trailing|no_sweep_dup]", helpers.check([[
         local t = {
             a, -- a
             b, -- b
         }
      ]]))

      -- Control: a stranded comment frozen by fmt:off is emitted verbatim, never
      -- through an accessor, so the sweep must skip it rather than double-emit.
      it("[fmt_off|stranded|frozen_not_swept]", helpers.check([[
         -- fmt:off
         local type T =
             integer -- a
             | string -- b
         -- fmt:on
      ]]))

      -- A comment stranded deep in an expression is reachable by the sweep only
      -- because the source-extent walk reads trailing comments without consuming
      -- them (trailing_extent); a consuming geometry read would mark it taken and
      -- the sweep would skip it. The op's own gap comment (`-- inner`/`-- one`)
      -- stays inline via op_leading; only the truly slot-less stray relocates.
      it("[paren_expr|multi_drop|sweeps_to_leading]", helpers.format([[
         local x = ((
             a -- inner
         ) -- outer
         )
      ]], [[
         -- inner
         -- outer
         local x = ((a))
      ]]))

      it("[return>paren|nested|multi_drop|sweeps_to_leading]", helpers.format([[
         local function g(): integer
             return (
                 1 -- one
                 + 2 -- two
             )
         end
      ]], [[
         local function g(): integer
             -- two
             return (
                 1 -- one
                     + 2
             )
         end
      ]]))

      -- The swept stray lands as the body's own-line leading. The body sits in the
      -- anonymous-function group, which would flatten the block separator (`; `) onto
      -- the comment's line and swallow `return …`; the line comment now carries
      -- break_parent, so the group opens and the code reaches its own line.
      it("[anon_fn>return>index|stray|sweeps_to_leading_no_swallow]", helpers.format([[
         x = function() return z[nil > w -- dash
         ] end
      ]], [[
         x = function()
             -- dash
             return z[nil > w]
         end
      ]]))

      -- An empty `return` carrying a trailing line comment inside an inline anonymous
      -- function: the comment must end its line so `end` is not swallowed.
      it("[anon_fn>empty_return|trailing|no_swallow]", helpers.format([[
         x = function() return -- c
         end
      ]], [[
         x = function()
             return -- c
         end
      ]]))
   end)

   describe("unconsumed comment fallback", function()
      -- The parser deletes the gap `;` outright, so the block comment before it
      -- is simply the statement's trailing run and stays inline where written.
      it("[local|trailing_semi|block_stays_inline]", helpers.format([=[
         local x = 1 --[[c]] ;
      ]=], [=[
         local x = 1 --[[c]]
      ]=]))

      it("[local|own_line_semi|block_stays_inline]", helpers.format([=[
         local x = 1 --[[c]]
         ;
      ]=], [=[
         local x = 1 --[[c]]
      ]=]))

      -- A block comment in a block's tail -- on a bare discarded `;` with no
      -- statement to cover it -- relocates to the block's dangling.
      it("[toplevel|bare_semi_leading|block_dangles]", helpers.format([=[
         --[[c]] ;
      ]=], [=[
         --[[c]]
      ]=]))

      it("[toplevel|bare_semi_trailing|block_dangles]", helpers.format([=[
         ;--[[c]]
      ]=], [=[
         --[[c]]
      ]=]))

      it("[toplevel|two_bare_semis|both_block_dangle]", helpers.format([=[
         --[[a]] ; --[[b]] ;
      ]=], [=[
         --[[a]]
         --[[b]]
      ]=]))

      it("[do|bare_semi|block_relocates]", helpers.format([=[
         do --[[c]] ;
         end
      ]=], [=[
         --[[c]]
         do
         end
      ]=]))

      -- Control: a dangling comment before a block's closer must stay inside the
      -- block, not escape to the enclosing block's dangling. The eager
      -- dangling scan steps past its own children so the outer block cannot steal
      -- the inner closer's leading comment.
      it("[do|own_line_dangling|stays_inside]", helpers.format([=[
         do
         --[[c]]
         end
      ]=], [=[
         do
             --[[c]]
         end
      ]=]))

      -- Control: a line comment trailing a statement before a discarded own-line
      -- `;` keeps its trailing slot; the dangling scan must not also emit it (a
      -- duplicate would trip the audit and the file would safe-skip).
      it("[local|line_trailing_then_semi|no_dangling_dup]", helpers.format([=[
         local x = 1 -- c
         ;
      ]=], [=[
         local x = 1 -- c
      ]=]))
   end)

   describe("nested cases", function()
      it("[function>if|nested|inner_between_last_and_end|call_arg_comment_blocked]", helpers.format([[
         local function f(cond: boolean)
           if cond then
             call(
               -- arg comment
               x
             )
             -- inner before end
           end
           return 0
         end
      ]], [[
         local function f(cond: boolean)
             if cond then
                 call(
                     -- arg comment
                     x
                 )
                 -- inner before end
             end
             return 0
         end
      ]]))

      it("[function>if|nested|inner_trailing_last|call_arg_comment_blocked]", helpers.format([[
         local function f(cond: boolean)
           if cond then
             call(
               -- arg comment
               x
             ) -- inner trailing last
           end
           return 0
         end
      ]], [[
         local function f(cond: boolean)
             if cond then
                 call(
                     -- arg comment
                     x
                 ) -- inner trailing last
             end
             return 0
         end
      ]]))

      it("[if>function|nested|leading_before_first|call_arg_comment_blocked]", helpers.format([[
         if cond then
           -- before nested function
           local function f()
             call(
               -- arg comment
               x
             )
           end
         end
      ]], [[
         if cond then
             -- before nested function
             local function f()
                 call(
                     -- arg comment
                     x
                 )
             end
         end
      ]]))

      it("[if>function|nested|nested_end_comments|call_arg_comment_blocked]", helpers.format([[
         if cond then
           local function f()
             call(
               -- arg comment
               x
             )
             -- nested before end
           end
         end
      ]], [[
         if cond then
             local function f()
                 call(
                     -- arg comment
                     x
                 )
                 -- nested before end
             end
         end
      ]]))

      it("[record_function>if|nested|inner_consecutive_end_comments|call_arg_comment_blocked]", helpers.format([[
         function Obj.compute(cond: boolean): integer
           if cond then
             call(
               -- arg comment
               x
             )
             -- inner before end 1
             -- inner before end 2
           end
           return 0
         end
      ]], [[
         function Obj.compute(cond: boolean): integer
             if cond then
                 call(
                     -- arg comment
                     x
                 )
                 -- inner before end 1
                 -- inner before end 2
             end
             return 0
         end
      ]]))

      it("[function>if>function|nested|multi_level_boundary_comments|call_arg_comment_blocked]", helpers.format([[
         local function outer(cond: boolean)
           if cond then
             -- before nested function
             local function inner()
               call(
                 -- arg comment
                 x
               )
               -- inner before end
             end
             -- middle before end
           end
         end
      ]], [[
         local function outer(cond: boolean)
             if cond then
                 -- before nested function
                 local function inner()
                     call(
                         -- arg comment
                         x
                     )
                     -- inner before end
                 end
                 -- middle before end
             end
         end
      ]]))

      it("[function>local_record|nested|record_plus_blocked_stmt]", helpers.format([[
         local function make()
           local record Box
             value: integer -- field comment
             -- record end comment
           end
           call(
             -- arg comment
             x
           )
         end
      ]], [[
         local function make()
             local record Box
                 value: integer -- field comment
                 -- record end comment
             end
             call(
                 -- arg comment
                 x
             )
         end
      ]]))

      it("[function>local_enum|nested|enum_plus_blocked_stmt]", helpers.format([[
         local function make()
           local enum E
             "a" -- value comment
             -- enum end comment
           end
           call(
             -- arg comment
             x
           )
         end
      ]], [[
         local function make()
             local enum E
                 "a" -- value comment
                 -- enum end comment
             end
             call(
                 -- arg comment
                 x
             )
         end
      ]]))
   end)

   describe("sibling block cases", function()
      it("[function+function|siblings|first_trailing_last_second_leading|second_blocked]", helpers.format([[
         local function first()
           return x -- trailing last
         end
         local function second()
           -- leading first
           call(
             -- arg comment
             x
           )
         end
      ]], [[
         local function first()
             return x -- trailing last
         end
         local function second()
             -- leading first
             call(
                 -- arg comment
                 x
             )
         end
      ]]))

      it("[if+if|siblings|first_between_last_and_end_second_trailing_last|second_blocked]", helpers.format([[
         if first then
           return x
           -- before end
         end
         if second then
           call(
             -- arg comment
             x
           ) -- trailing last
         end
      ]], [[
         if first then
             return x
             -- before end
         end
         if second then
             call(
                 -- arg comment
                 x
             ) -- trailing last
         end
      ]]))

      it("[record_function+record_function|siblings|first_end_comments_second_leading_between|second_blocked]", helpers.format([[
         function Obj.a(): integer
           return x
           -- before end 1
           -- before end 2
         end
         function Obj.b(): integer
           local y = 1
           -- between
           call(
             -- arg comment
             y
           )
           return y
         end
      ]], [[
         function Obj.a(): integer
             return x
             -- before end 1
             -- before end 2
         end
         function Obj.b(): integer
             local y = 1
             -- between
             call(
                 -- arg comment
                 y
             )
             return y
         end
      ]]))

      it("[record+function|siblings|record_end_comments_function_blocked]", helpers.format([[
         local record Box
           value: integer -- field comment
           -- record end comment
         end
         local function f()
           call(
             -- arg comment
             x
           )
         end
      ]], [[
         local record Box
             value: integer -- field comment
             -- record end comment
         end
         local function f()
             call(
                 -- arg comment
                 x
             )
         end
      ]]))

      it("[enum+function|siblings|enum_end_comments_function_blocked]", helpers.format([[
         local enum E
           "a" -- value comment
           -- enum end comment
         end
         local function f()
           call(
             -- arg comment
             x
           )
         end
      ]], [[
         local enum E
             "a" -- value comment
             -- enum end comment
         end
         local function f()
             call(
                 -- arg comment
                 x
             )
         end
      ]]))

      it("[record+enum|siblings|both_with_comments_plus_top_level_prelude]", helpers.format([[
         -- top-level prelude
         local record Box
           value: integer -- field comment
           -- record end comment
         end
         local enum E
           "a" -- value comment
           -- enum end comment
         end
      ]], [[
         -- top-level prelude
         local record Box
             value: integer -- field comment
             -- record end comment
         end
         local enum E
             "a" -- value comment
             -- enum end comment
         end
      ]]))

      it("[if+record_function|siblings|first_consecutive_end_comments_second_blocked_between]", helpers.format([[
         if cond then
           return x
           -- before end 1
           -- before end 2
         end
         function Obj.c(): integer
           local y = 1
           -- between
           call(
             -- arg comment
             y
           )
           return y
         end
      ]], [[
         if cond then
             return x
             -- before end 1
             -- before end 2
         end
         function Obj.c(): integer
             local y = 1
             -- between
             call(
                 -- arg comment
                 y
             )
             return y
         end
      ]]))
   end)

   describe("general block comment rendering", function()
      it("reindents a function body with a trailing inline comment on a non-last statement",
         helpers.format([[
            local function f()
              local x = 1 -- keep this comment
              return x
            end
         ]], [[
            local function f()
                local x = 1 -- keep this comment
                return x
            end
         ]]))

      it("reindents a function body with a standalone leading comment before return",
         helpers.format([[
            local function f()
              local x = 1
              -- compute final value
              return x + 1
            end
         ]], [[
            local function f()
                local x = 1
                -- compute final value
                return x + 1
            end
         ]]))

      it("reindents a function body with both trailing and leading comments at a boundary",
         helpers.format([[
            local function f()
              local x = 1 -- trailing comment
              -- leading comment
              return x
            end
         ]], [[
            local function f()
                local x = 1 -- trailing comment
                -- leading comment
                return x
            end
         ]]))

      it("reindents a function body with multiple consecutive leading comments",
         helpers.format([[
            local function f()
              local x = 1
              -- first leading comment
              -- second leading comment
              return x
            end
         ]], [[
            local function f()
                local x = 1
                -- first leading comment
                -- second leading comment
                return x
            end
         ]]))

      it("reindents a nested if block containing a statement with a trailing comment",
         helpers.format([[
            local function f(flag: boolean)
              if flag then
                local x = 1 -- note
                return x
              end
              return 0
            end
         ]], [[
            local function f(flag: boolean)
                if flag then
                    local x = 1 -- note
                    return x
                end
                return 0
            end
         ]]))

      it("reindents while preserving trailing comment on the last statement of a body",
         helpers.format([[
            local function f()
              return compute() -- trailing on last statement
            end
         ]], [[
            local function f()
                return compute() -- trailing on last statement
            end
         ]]))

      it("reindents while preserving comments between last statement and end",
         helpers.format([[
            local function f()
              local x = 1
              return x
              -- comment before end
            end
         ]], [[
            local function f()
                local x = 1
                return x
                -- comment before end
            end
         ]]))

      it("keeps a single blank line before a lone end comment stable", helpers.check([[
         local function f()
             local x = 1
             return x

             -- comment before end
         end
      ]]))

      it("regular comment that are end comments are stable", helpers.format([[
         local x =  1

         -- regular comment
      ]], [[
         local x = 1

         -- regular comment
      ]]))

      it("unattached comments are stable", helpers.check([[   
         -- regular comment
      ]]))

      it("hashbang are kept and supported", helpers.format([[
         #!/usr/bin/env tl run
         local x =  1
      ]], [[
         #!/usr/bin/env tl run
         local x = 1
      ]]))

      it("empty lines between hashbang and stmt are removed, consider changing this behaviour", helpers.format([[
         #!/usr/bin/env tl run


         local x =  1
      ]], [[
         #!/usr/bin/env tl run
         local x = 1
      ]]))

      it("empty lines between hashbang and comment are kept", helpers.format([[
         #!/usr/bin/env tl run


         -- hello
      ]], [[
         #!/usr/bin/env tl run

         -- hello
      ]]))

      -- A block comment spanning lines ends the line it opens on, so the value
      -- after it moves below rather than continuing a line the comment closed.
      it("breaks the value below a multi-line block comment in an expression",
         helpers.format(
            "local x = --[[\nspanning\nlines]] 1\n",
            "local x = --[[\nspanning\nlines]]\n    1\n"
         ))

      it("block comment that are end comments are stable", helpers.format([=[
         local x =  1

         --[[
         this is a
         block comment
         ]]
      ]=], [=[
         local x = 1

         --[[
         this is a
         block comment
         ]]
      ]=]))

      it("preserves a leading comment on the sole statement of an if body",
         helpers.format([[
            local function f(flag: boolean)
              if flag then
                -- sole statement comment
                local x = 1
              end
            end
         ]], [[
            local function f(flag: boolean)
                if flag then
                    -- sole statement comment
                    local x = 1
                end
            end
         ]]))

      it("preserves a leading comment on the first statement in a multi-statement if body",
         helpers.format([[
            local function f(flag: boolean)
              if flag then
                -- setup x
                local x = 1
                return x
              end
            end
         ]], [[
            local function f(flag: boolean)
                if flag then
                    -- setup x
                    local x = 1
                    return x
                end
            end
         ]]))

      it("preserves a single comment in an otherwise empty function body", helpers.format([[
         function f()
            -- does something
         end
      ]], [[
         function f()
             -- does something
         end
      ]]))

      it("preserves a single comment in an otherwise empty function bodies", helpers.format([[
         function f1()
                -- First
         end

         function f2()
                -- Second
         end
      ]], [[
         function f1()
             -- First
         end

         function f2()
             -- Second
         end
      ]]))

      it("preserves blank line before comment at start of body", helpers.format([[
         function f()
            
         -- does something
         end
      ]], [[
         function f()
             
             -- does something
         end
      ]]))

      it("preserves blank lines between comment-only lines in an empty function body", helpers.format([[
         function f()
            -- does something 1

            -- does something 2
         end
      ]], [[
         function f()
             -- does something 1

             -- does something 2
         end
      ]]))

      it("keeps leading and trailing comment blocks around a statement stable", helpers.format([[
         function f()
            -- pre comment 1
            -- pre comment 2
            statement() -- comment on line
            -- post comment 1
            -- post comment 2
         end
      ]], [[
         function f()
             -- pre comment 1
             -- pre comment 2
             statement() -- comment on line
             -- post comment 1
             -- post comment 2
         end
      ]]))

      it("preserves inline enum comments", helpers.format([[
         local enum TestEnum
            "a" -- does something
            "b"
         end
      ]], [[
         local enum TestEnum
             "a" -- does something
             "b"
         end
      ]]))

      it("preserves enum end comments", helpers.format([[
         local type TestEnum = enum
            "a"
            -- enum end comment
         end
      ]], [[
         local type TestEnum = enum
             "a"
             -- enum end comment
         end
      ]]))

      it("preserves a trailing return comment inside an if block", helpers.format([[
         if test == nil then
            return -- exit
         end
      ]], [[
         if test == nil then
             return -- exit
         end
      ]]))
   end)

   describe("trailing comments on control flow keywords", function()
      it("[if|then_trailing|single_stmt_body]", helpers.check([[
         if condition then -- why this branch
             stmt()
         end
      ]]))

      it("[elseif|then_trailing|single_stmt_body]", helpers.check([[
         if first then
             stmt()
         elseif condition then -- why this elseif
             other()
         end
      ]]))

      it("[else|trailing|single_stmt_body]", helpers.check([[
         if first then
             stmt()
         else -- fallback case
             other()
         end
      ]]))

      it("[if_else|both_then_and_else_trailing|two_branches]", helpers.check([[
         if x == "a" then -- first branch
             handle_a(x)
         else -- fallback branch
             handle_b(x)
         end
      ]]))

      it("[while|do_trailing|single_stmt_body]", helpers.check([[
         while running do -- check each iteration
             step()
         end
      ]]))

      it("[fornum|do_trailing|single_stmt_body]", helpers.check([[
         for i = 1, 10 do -- iterate in order
             process(i)
         end
      ]]))

      it("[forin|do_trailing|single_stmt_body]", helpers.check([[
         for k, v in pairs(t) do -- all entries
             use(k, v)
         end
      ]]))

      it("[repeat|keyword_trailing|single_stmt_body]", helpers.check([[
         repeat -- setup pass
             step()
         until done
      ]]))

      it("[if|then_trailing|empty_body]", helpers.check([[
         if cond then -- branch reason
         end
      ]]))

      it("[if|then_trailing|nested_in_forin]", helpers.check([[
         for _, item in ipairs(items) do
             local kind, value = classify(item)
             if kind == "special" then -- must handle before default
                 assert(value)
                 handle(value)
             end
         end
      ]]))

      it("[if|then_trailing|nested_in_function]", helpers.check([[
         local function check(x: integer): boolean
             if x == 0 or x == 1 then -- check common cases first
                 return true
             end
             return false
         end
      ]]))

      it("[elseif|then_trailing|comment_is_commented_out_code]", helpers.check([[
         local function classify(item: Item)
             if item.kind == "a" then
                 handle_a(item)
             elseif item.kind == "b" then -- handle_b(item)
                 dispatch(item)
             end
         end
      ]]))
   end)

   describe("trailing comments on function headers", function()
      it("[local_function|no_return_type|single_stmt_body]", helpers.check([[
         local function foo() -- why this function
             stmt()
         end
      ]]))

      it("[local_function|with_return_type|single_stmt_body]", helpers.check([[
         local function foo(): boolean -- why this function
             return true
         end
      ]]))

      it("[anonymous_function|no_return_type|single_stmt_body]", helpers.check([[
         local foo = function() -- why this function
             stmt()
         end
      ]]))

      it("[anonymous_function|with_return_type|single_stmt_body]", helpers.check([[
         local foo = function(): boolean -- why this function
             return true
         end
      ]]))
   end)

   describe("known comment regressions", function()
      it("preserves multiline table shape and trailing comma when call closing line has a trailing comment", helpers.format([[
         local function f()
           return process(
             {
               a = 1,
               b = 2,
             }
           ) -- trailing call comment
         end
      ]], [[
         local function f()
             return process(
                 {
                     a = 1,
                     b = 2,
                 }
             ) -- trailing call comment
         end
      ]]))

      it("preserves inline interface field comments in local type interface declarations", helpers.format([[
         local type EntityType = interface
           method_a: function(self)
           method_b: function(self, value: number)
           method_c: function(self)
           -- Internal-only field marker:
           extra_flag: boolean
         end
      ]], [[
         local type EntityType = interface
             method_a: function(self)
             method_b: function(self, value: number)
             method_c: function(self)
             -- Internal-only field marker:
             extra_flag: boolean
         end
      ]]))

      it("preserves empty line between comment and following record", helpers.format([[
         -- module docs

         local record A
            n: integer
         end
      ]], [[
         -- module docs

         local record A
             n: integer
         end
      ]]))

      it("preserves empty line between comment and following enum item", helpers.format([[
         local enum A
            -- stuff

            "a1"
            "a2"
         end
      ]], [[
         local enum A
             -- stuff

             "a1"
             "a2"
         end
      ]]))

      it("preserves empty line between comment and following record field", helpers.format([[
         local record Box
            -- describes n

            n: integer
         end
      ]], [[
         local record Box
             -- describes n

             n: integer
         end
      ]]))

      it("preserves empty line between comment and following table entry", helpers.format([[
         local t = {
            -- the answer

            value = 42,
         }
      ]], [[
         local t = {
             -- the answer

             value = 42,
         }
      ]]))

      it("preserves empty line between comment and following call arg", helpers.format([[
         local function f()
            call(
               -- the arg

               x
            )
         end
      ]], [[
         local function f()
             call(
                 -- the arg

                 x
             )
         end
      ]]))

      it("preserves a trailing line comment in a file with no trailing newline", helpers.format_raw(
         "-- hello",
         "-- hello\n"
      ))

      it("preserves an ambiguous trailing line comment in a file with no trailing newline", helpers.format_raw(
         "--[",
         "--[\n"
      ))

      it("preserves an empty trailing line comment in a file with no trailing newline", helpers.format_raw(
         "--",
         "--\n"
      ))
   end)

   describe("empty function body with comments", function()
      it("preserves a comment inside an empty local function body", helpers.check([[
         local function no_op()
             -- not yet implemented
         end
      ]]))

      it("preserves multiple comments inside an empty local function body", helpers.check([[
         local function no_op()
             -- first note
             -- second note
         end
      ]]))

      it("preserves a blank line before a comment inside an empty local function body", helpers.check([[
         local function no_op()

             -- not yet implemented
         end
      ]]))

      it("reindents a comment inside a poorly-indented empty local function body", helpers.format([[
         local function no_op()
           -- not yet implemented
         end
      ]], [[
         local function no_op()
             -- not yet implemented
         end
      ]]))

      it("preserves a comment inside an empty record function body", helpers.check([[
         function Obj:on_event()
             -- not yet implemented
         end
      ]]))

      it("reindents a comment inside a poorly-indented empty record function body", helpers.format([[
         function Obj:on_event()
           -- not yet implemented
         end
      ]], [[
         function Obj:on_event()
             -- not yet implemented
         end
      ]]))

      it("preserves multiple comments with a blank line between them in an empty body", helpers.check([[
         local function no_op()
             -- first note

             -- second note
         end
      ]]))
   end)

   describe("inline comment after logical operator", function()
      it("preserves comment before 'and' operator", helpers.check([[
         local x = a --hmm
             and b
      ]]))

      it("preserves comment after 'and' operator", helpers.check([[
         local x = a and --hmm
             b
      ]]))

      it("preserves comment before 'or' operator", helpers.check([[
         local x = a --hmm
             or b
      ]]))

      it("preserves comment after 'or' operator", helpers.check([[
         local x = a or --hmm
             b
      ]]))
   end)

   describe("inline comment after control flow keyword", function()
      it("preserves comment between 'while' and condition", helpers.check([[
         while --hmm
             cond do
         end
      ]]))

      it("preserves comment between 'for =' and range", helpers.check([[
         for i = --hmm
             1, 10 do
         end
      ]]))

      it("preserves comment between 'in' and iterator", helpers.check([[
         for k in --hmm
             iter do
         end
      ]]))

      it("preserves comment between 'until' and condition", helpers.check([[
         repeat
         until --hmm
             cond
      ]]))
   end)

   describe("inline comment in table initializer", function()
      it("preserves comment between table key '=' and value", helpers.check([[
         local t = {
             key = --hmm
                 value,
         }
      ]]))
   end)

   describe("trailing comment in comma-separated expression list", function()
      it("preserves trailing comment after first exp in assignment list", helpers.check([[
         a, b = 1, --hmm
             2
      ]]))

      it("preserves trailing comment after first exp in return list", helpers.check([[
         local function f()
             return a, --hmm
                 b
         end
      ]]))

      it("keeps a comment trailing the exp separate from one trailing the comma", helpers.format([[
         return a -- one
             , -- two
             b
      ]], [[
         return a, -- one
             -- two
             b
      ]]))

      it("indents an own-line comment between a comma and the next exp", helpers.format([[
         return a,
         -- note
         b
      ]], [[
         return a,
             -- note
             b
      ]]))
   end)

   describe("trailing comment in comma-separated variable list", function()
      it("preserves trailing comment after first var in assignment lhs", helpers.check([[
         a, --hmm
             b = 1, 2
      ]]))

      it("preserves trailing comment after middle var in assignment lhs", helpers.check([[
         a, b, --hmm
             c = 1, 2, 3
      ]]))

      it("preserves trailing comment after first name in local declaration", helpers.check([[
         local a, --hmm
             b = 1
      ]]))
   end)

   describe("dropped comments in multi-line expressions (regression)", function()
      it("preserves trailing comment on is-narrowing line in multi-line and/or assignment", helpers.check([[
         local x = a is integer -- only ints
             and 1 or 0
      ]]))

      -- Empty inner type: old design emitted a trailing space `(--[[]] )`.
      it("preserves block comment inside empty parenthesized is-cast", helpers.format([=[
         x = b is(--[[]])
      ]=], [=[
         x = b is (--[[]])
      ]=]))

      it("preserves block comment inside empty parenthesized as-cast", helpers.format([=[
         x = b as(--[[]])
      ]=], [=[
         x = b as (--[[]])
      ]=]))

      -- Comments buried in parenthesized cast types have no kept slot; the
      -- per-statement sweep relocates them to the statement's own-line leading.
      it("preserves block comment before nominal type in parenthesized is-cast", helpers.format([=[
         x = b is(--[[note]] integer)
      ]=], [=[
         --[[note]]
         x = b is (integer)
      ]=]))

      it("preserves block comment before array type in parenthesized is-cast", helpers.format([=[
         x = b is(--[[note]] {integer})
      ]=], [=[
         --[[note]]
         x = b is ({integer})
      ]=]))

      it("preserves block comment before map type in parenthesized as-cast", helpers.format([=[
         x = b as(--[[note]] {string: integer})
      ]=], [=[
         --[[note]]
         x = b as ({string: integer})
      ]=]))

      it("preserves block comment before union type in parenthesized is-cast", helpers.format([=[
         x = b is(--[[note]] integer | string)
      ]=], [=[
         --[[note]]
         x = b is (integer | string)
      ]=]))

      it("preserves block comment before multi-type tuple in parenthesized as-cast", helpers.format([=[
         x = b as(--[[note]] integer, string)
      ]=], [=[
         --[[note]]
         x = b as (integer, string)
      ]=]))

      it("preserves multiple block comments before type in parenthesized is-cast", helpers.format([=[
         x = b is(--[[a]] --[[b]] integer)
      ]=], [=[
         --[[a]]
         --[[b]]
         x = b is (integer)
      ]=]))

      it("preserves block comment before second type in parenthesized as-cast", helpers.format([=[
         x = b as(integer, --[[note]] string)
      ]=], [=[
         --[[note]]
         x = b as (integer, string)
      ]=]))

      it("preserves block comment between type and comma in parenthesized as-cast", helpers.format([=[
         x = b as(integer --[[between]], string)
      ]=], [=[
         --[[between]]
         x = b as (integer, string)
      ]=]))

      it("preserves trailing block comment before close-paren in parenthesized as-cast", helpers.format([=[
         x = b as(integer, string --[[trailing]])
      ]=], [=[
         --[[trailing]]
         x = b as (integer, string)
      ]=]))

      it("preserves comments interleaved between and/or parts in if condition", helpers.format([[
         if (not a) and
            -- try first
            ((b == 1)
            -- then second
            or (b == 2))
         then
             f()
         end
      ]], [[
         if (not a) and
             -- try first
             (
                 (b == 1)
                     -- then second
                     or (b == 2)
             ) then
             f()
         end
      ]]))

      it("keeps a block comment between multi-assignment lhs and equals inline", helpers.check([=[
         i, t --[[what is t for?]] = f(i)
      ]=]))

      it("keeps a block comment before equals inline with an index expression as last var", helpers.check([=[
         i, node[k] --[[, node.min_arity]] = f(ps, i)
      ]=]))

      it("preserves block comment in middle of multi-assignment lhs and equals", helpers.format([=[
         i, t --[[what is t for?]], k = f(i)
      ]=], [=[
         --[[what is t for?]]
         i, t, k = f(i)
      ]=]))

      it("preserves block comment after first var in multi-assignment lhs", helpers.format([=[
         i --[[what is i?]], t = f(i)
      ]=], [=[
         --[[what is i?]]
         i, t = f(i)
      ]=]))

      it("preserves block comment after first call arg before comma", helpers.format([=[
         f(x --[[what is x?]], y)
      ]=], [=[
         --[[what is x?]]
         f(x, y)
      ]=]))

      it("preserves block comment after first table field before comma", helpers.format([=[
         local t = {1 --[[first?]], 2}
      ]=], [=[
         --[[first?]]
         local t = {1, 2}
      ]=]))

      it("keeps multiple block comments after declaration lhs before equals inline", helpers.check([=[
         local x --[[c1]] --[[c2]] = 1
      ]=]))

      it("keeps a line comment after declaration lhs, breaking before equals", helpers.format([[
         local x -- c
         = 1
      ]], [[
         local x -- c
             = 1
      ]]))

      it("relocates a multiline block comment between lhs and equals", helpers.format([=[
         i, t --[[what
         is t?]] = f(i)
      ]=], [=[
         --[[what
         is t?]]
         i, t = f(i)
      ]=]))

      it("preserves block comment after first rhs exp before comma in declaration", helpers.format([=[
         local x, y = 1 --[[first?]], 2
      ]=], [=[
         --[[first?]]
         local x, y = 1, 2
      ]=]))

      it("preserves block comment after first rhs exp before comma in assignment", helpers.format([=[
         x, y = 1 --[[first?]], 2
      ]=], [=[
         --[[first?]]
         x, y = 1, 2
      ]=]))

      it("preserves multiple block comments after first rhs exp before comma", helpers.format([=[
         local x, y = 1 --[[c1]] --[[c2]], 2
      ]=], [=[
         --[[c1]]
         --[[c2]]
         local x, y = 1, 2
      ]=]))

      it("relocates a block comment after a call-arg comma to statement leading", helpers.format([=[
         f(x, --[[why y?]] y)
      ]=], [=[
         --[[why y?]]
         f(x, y)
      ]=]))

      it("relocates a block comment after a table-field comma to statement leading", helpers.format([=[
         local t = {1, --[[second]] 2}
      ]=], [=[
         --[[second]]
         local t = {1, 2}
      ]=]))

      -- The formatter writes the comma the source omitted, so this ends up past
      -- a separator like the cases above.
      it("relocates a block comment after the last table field to statement leading", helpers.format([=[
         local t = {1 --[[last?]]}
      ]=], [=[
         --[[last?]]
         local t = {1}
      ]=]))

      it("relocates a block comment after a declaration-rhs comma to statement leading", helpers.format([=[
         local x, y = 1, --[[second]] 2
      ]=], [=[
         --[[second]]
         local x, y = 1, 2
      ]=]))

      it("relocates a block comment after an assignment-rhs comma to statement leading", helpers.format([=[
         x, y = 1, --[[second]] 2
      ]=], [=[
         --[[second]]
         x, y = 1, 2
      ]=]))

      it("relocates a block comment after an assignment-lhs comma to statement leading", helpers.format([=[
         x, --[[why y?]] y = f()
      ]=], [=[
         --[[why y?]]
         x, y = f()
      ]=]))

      it("relocates a block comment after a declaration-name comma to statement leading", helpers.format([=[
         local x, --[[why y?]] y = 1, 2
      ]=], [=[
         --[[why y?]]
         local x, y = 1, 2
      ]=]))

      it("preserves multiple block comments after while do keyword", helpers.check([=[
         while running do --[[a]] --[[b]]
             step()
         end
      ]=]))

      it("preserves multiple block comments after for-num do keyword", helpers.check([=[
         for i = 1, 10 do --[[a]] --[[b]]
             process(i)
         end
      ]=]))

      it("preserves multiple block comments after for-in do keyword", helpers.check([=[
         for k, v in pairs(t) do --[[a]] --[[b]]
             use(k, v)
         end
      ]=]))

      it("preserves multiple block comments after repeat keyword", helpers.check([=[
         repeat --[[a]] --[[b]]
             step()
         until done
      ]=]))

      it("preserves multiple block comments after function header", helpers.check([=[
         local function f() --[[a]] --[[b]]
             step()
         end
      ]=]))

      it("preserves multiple block comments after anonymous function header", helpers.check([=[
         local f = function() --[[a]] --[[b]]
             step()
         end
      ]=]))

      it("preserves multiple block comments after declaration equals", helpers.check([=[
         local x = --[[a]] --[[b]]
             1
      ]=]))

      it("preserves multiple block comments after assignment equals", helpers.check([=[
         x = --[[a]] --[[b]]
             1
      ]=]))

      it("preserves multiple block comments after call open paren", helpers.format([=[
         f( --[[a]] --[[b]] x)
      ]=], [=[
         f( --[[a]] --[[b]]
             x
         )
      ]=]))

      it("preserves multiple block comments after while keyword", helpers.format([=[
         while --[[a]] --[[b]] cond do
             step()
         end
      ]=], [=[
         while --[[a]] --[[b]]
             cond do
             step()
         end
      ]=]))

      it("preserves multiple block comments after for-num equals", helpers.format([=[
         for i = --[[a]] --[[b]] 1, 10 do
             step()
         end
      ]=], [=[
         for i = --[[a]] --[[b]]
             1, 10 do
             step()
         end
      ]=]))

      it("preserves multiple block comments after for-in keyword", helpers.format([=[
         for k, v in --[[a]] --[[b]] pairs(t) do
             step()
         end
      ]=], [=[
         for k, v in --[[a]] --[[b]]
             pairs(t) do
             step()
         end
      ]=]))

      it("preserves multiple block comments after until", helpers.check([=[
         repeat
             step()
         until --[[a]] --[[b]]
             cond
      ]=]))

      it("preserves multiple block comments after return", helpers.check([=[
         return --[[a]] --[[b]]
             x
      ]=]))

      it("preserves multiple block comments after if cond keyword", helpers.format([=[
         if --[[a]] --[[b]] cond then
             step()
         end
      ]=], [=[
         if --[[a]] --[[b]]
             cond then
             step()
         end
      ]=]))

      it("preserves multiple block comments after table short key equals", helpers.check([=[
         local t = {
             key = --[[a]] --[[b]]
                 value,
         }
      ]=]))

      it("preserves trailing comment on nested logical expressions", helpers.format([[
         local x = expression_1 -- Keep me
            or expression_2
            or expression_3
      ]], [[
         local x = expression_1 -- Keep me
             or expression_2
             or expression_3
      ]]))
   end)

   -- A comment buried inside type syntax has no kept slot; the per-statement
   -- sweep relocates it to the statement's own-line leading.
   describe("block comments inside type syntax", function()
      it("preserves block comment before first type argument", helpers.format([=[
         local x: Map<--[[k]]string, integer>
      ]=], [=[
         --[[k]]
         local x: Map<string, integer>
      ]=]))

      it("preserves block comment before later type argument", helpers.format([=[
         local x: Map<string, --[[v]]integer>
      ]=], [=[
         --[[v]]
         local x: Map<string, integer>
      ]=]))

      it("preserves block comment after last type argument", helpers.format([=[
         local x: Foo<integer--[[t]]>
      ]=], [=[
         --[[t]]
         local x: Foo<integer>
      ]=]))

      it("preserves block comment before a declared type parameter", helpers.format([=[
         local type F = function<T, --[[c]]U>(T): U
      ]=], [=[
         --[[c]]
         local type F = function<T, U>(T): U
      ]=]))

      it("preserves block comments throughout a tuple table type", helpers.format([=[
         local x: {--[[a]]integer, string--[[b]], boolean}
      ]=], [=[
         --[[a]]
         --[[b]]
         local x: {integer, string, boolean}
      ]=]))

      it("preserves block comment before an array element type", helpers.format([=[
         local x: {--[[c]]integer}
      ]=], [=[
         --[[c]]
         local x: {integer}
      ]=]))

      it("preserves block comment after an array element type", helpers.format([=[
         local x: {integer--[[c]]}
      ]=], [=[
         --[[c]]
         local x: {integer}
      ]=]))

      it("preserves block comment before a map key type", helpers.format([=[
         local x: {--[[k]]string: integer}
      ]=], [=[
         --[[k]]
         local x: {string: integer}
      ]=]))

      it("preserves block comment before a map value type", helpers.format([=[
         local x: {string: --[[v]]integer}
      ]=], [=[
         --[[v]]
         local x: {string: integer}
      ]=]))

      it("preserves block comment after a map key type", helpers.format([=[
         local x: {string--[[bk]]: integer}
      ]=], [=[
         --[[bk]]
         local x: {string: integer}
      ]=]))

      it("preserves block comments around a union separator", helpers.format([=[
         local x: integer--[[a]] | --[[b]]string
      ]=], [=[
         --[[a]]
         --[[b]]
         local x: integer | string
      ]=]))

      -- A comment trailing the `(` is the argument list's after_opener slot, which
      -- forces the parens to wrap, exactly as a function declaration's would.
      it("preserves block comment before a function-type argument", helpers.format([=[
         local x: function(--[[a]]p: integer)
      ]=], [=[
         local x: function( --[[a]]
             p: integer
         )
      ]=]))

      it("preserves block comment between a function argument's colon and type", helpers.format([=[
         local x: function(p: --[[c]]integer)
      ]=], [=[
         --[[c]]
         local x: function(p: integer)
      ]=]))

      it("preserves a block comment after a non-last function-type argument's type", helpers.format([=[
         local x: function(p: integer --[[t]], q: string)
      ]=], [=[
         --[[t]]
         local x: function(p: integer, q: string)
      ]=]))

      it("preserves a block comment after an unnamed function-type argument's type", helpers.format([=[
         local x: function(integer --[[t]], string)
      ]=], [=[
         --[[t]]
         local x: function(integer, string)
      ]=]))

      it("preserves a block comment after the last function-type argument's type", helpers.format([=[
         local x: function(p: integer --[[t]])
      ]=], [=[
         local x: function(
             p: integer --[[t]]
         )
      ]=]))

      it("preserves a block comment in a function type's type-argument list", helpers.format([=[
         local x: function<T --[[b]]>()
      ]=], [=[
         --[[b]]
         local x: function<T>()
      ]=]))

      it("preserves a block comment before a parenthesized function-type argument type", helpers.format([=[
         local x: function(p: --[[b]] (string))
      ]=], [=[
         --[[b]]
         local x: function(p: (string))
      ]=]))

      it("preserves block comment before a function return type", helpers.format([=[
         local x: function(): --[[r]]string
      ]=], [=[
         --[[r]]
         local x: function(): string
      ]=]))

      it("preserves block comment after an interface-list comma", helpers.format([=[
         local record R is A, --[[note]] B end
      ]=], [=[
         --[[note]]
         local record R is A, B
         end
      ]=]))

      it("preserves block comment before an interface-list comma", helpers.format([=[
         local record R is A --[[note]], B end
      ]=], [=[
         --[[note]]
         local record R is A, B
         end
      ]=]))
   end)

   -- Own-line comments inside type syntax relocate to statement leading like
   -- every other slotless placement, collapsing the annotation onto one line.
   describe("line comments inside type syntax", function()
      it("relocates an own-line line comment before a type annotation", helpers.format([=[
         local x:
             -- note
             integer = 1
      ]=], [=[
         -- note
         local x: integer = 1
      ]=]))

      it("relocates an unindented line comment before a type annotation", helpers.format([=[
         local x:
         -- note
         integer = 1
      ]=], [=[
         -- note
         local x: integer = 1
      ]=]))

      it("relocates a line comment before an array element type", helpers.format([=[
         local x: {
             -- note
             integer}
      ]=], [=[
         -- note
         local x: {integer}
      ]=]))

      it("relocates a line comment before a map value type", helpers.format([=[
         local x: {string:
             -- v
             integer}
      ]=], [=[
         -- v
         local x: {string: integer}
      ]=]))

      it("relocates a line comment before a type argument", helpers.format([=[
         local x: Map<
             -- k
             string, integer>
      ]=], [=[
         -- k
         local x: Map<string, integer>
      ]=]))

      it("relocates a same-line block comment and a line comment together", helpers.format([=[
         local x: --[[b]]
             -- note
             integer = 1
      ]=], [=[
         --[[b]]
         -- note
         local x: integer = 1
      ]=]))

      it("relocates a line comment before a union member", helpers.format([=[
         local x: integer |
             -- note
             string = 1
      ]=], [=[
         -- note
         local x: integer | string = 1
      ]=]))

      it("relocates a line comment before a function argument type", helpers.format([=[
         local function f(a:
                 -- note
                 integer
         )
         end
      ]=], [=[
         -- note
         local function f(a: integer)
         end
      ]=]))

      it("relocates a line comment before a function return type", helpers.format([=[
         local function f():
             -- note
             integer
         end
      ]=], [=[
         -- note
         local function f(): integer
         end
      ]=]))

      -- A line comment trailing a function-type argument rides that argument's
      -- trailing slot, identical to a definition parameter. The old type-arg path
      -- read the preceding token's comment and emitted it inline, e.g.
      -- `function(integer, -- a` then `string)`, which is invalid Teal.
      it("preserves trailing line comments after unnamed function-type arguments", helpers.check([=[
         local f: function(
             integer, -- a
             string -- b
         )
      ]=]))

      it("preserves trailing line comments on a record field's function-type arguments", helpers.check([=[
         local record R
             f: function(
                 a: integer, -- p
                 b: string -- q
             ): boolean
         end
      ]=]))

      it("wraps a single unnamed function-type argument carrying a trailing line comment", helpers.format([=[
         local f: function(integer -- c
         )
      ]=], [=[
         local f: function(
             integer -- c
         )
      ]=]))
   end)

   describe("multiple same-line trailing block comments", function()
      it("keeps two block comments after a local declaration with the statement", helpers.check([=[
         local x = 1 --[[a]] --[[b]]
         return x
      ]=]))

      it("keeps two block comments after an assignment value", helpers.check([=[
         x = 1 --[[a]] --[[b]]
         return x
      ]=]))

      it("keeps two block comments after a record field", helpers.check([=[
         local record R
             field: integer --[[a]] --[[b]]
         end
      ]=]))
   end)

   -- A comment wedged into a declaration's keyword run has no kept slot; the
   -- per-statement sweep relocates it to the statement's own-line leading.
   describe("inline comment after a declaration keyword", function()
      it("relocates a comment between local and a variable name", helpers.format([=[
         local --[[c]] x = 1
      ]=], [=[
         --[[c]]
         local x = 1
      ]=]))

      it("relocates a comment between global and a variable name", helpers.format([=[
         global --[[c]] x = 1
      ]=], [=[
         --[[c]]
         global x = 1
      ]=]))

      it("relocates a comment between local and type", helpers.format([=[
         local --[[c]] type T = integer
      ]=], [=[
         --[[c]]
         local type T = integer
      ]=]))

      it("relocates a comment between local type and the name", helpers.format([=[
         local type --[[c]] T = integer
      ]=], [=[
         --[[c]]
         local type T = integer
      ]=]))

      it("relocates a comment between global and type", helpers.format([=[
         global --[[c]] type T = integer
      ]=], [=[
         --[[c]]
         global type T = integer
      ]=]))

      it("relocates a comment between global type and the name", helpers.format([=[
         global type --[[c]] T = integer
      ]=], [=[
         --[[c]]
         global type T = integer
      ]=]))

      it("relocates a comment between local and function", helpers.format([=[
         local --[[c]] function f()
         end
      ]=], [=[
         --[[c]]
         local function f()
         end
      ]=]))

      it("relocates a comment between local function and the name", helpers.format([=[
         local function --[[c]] f()
         end
      ]=], [=[
         --[[c]]
         local function f()
         end
      ]=]))

      it("relocates a comment between global and function", helpers.format([=[
         global function --[[c]] f()
         end
      ]=], [=[
         --[[c]]
         global function f()
         end
      ]=]))

      it("relocates a comment between local and record", helpers.format([=[
         local --[[c]] record R
             x: integer
         end
      ]=], [=[
         --[[c]]
         local record R
             x: integer
         end
      ]=]))

      it("relocates a comment between local record and the name", helpers.format([=[
         local record --[[c]] R
             x: integer
         end
      ]=], [=[
         --[[c]]
         local record R
             x: integer
         end
      ]=]))

      it("relocates a comment between global and record", helpers.format([=[
         global --[[c]] record R
             x: integer
         end
      ]=], [=[
         --[[c]]
         global record R
             x: integer
         end
      ]=]))

      it("relocates a comment between local enum and the name", helpers.format([=[
         local enum --[[c]] E
             "a"
         end
      ]=], [=[
         --[[c]]
         local enum E
             "a"
         end
      ]=]))

      it("relocates a comment between local interface and the name", helpers.format([=[
         local interface --[[c]] I
             x: integer
         end
      ]=], [=[
         --[[c]]
         local interface I
             x: integer
         end
      ]=]))

      it("relocates a comment between a record name and where", helpers.format([=[
         local record R --[[c]] where self.x
             x: boolean
         end
      ]=], [=[
         --[[c]]
         local record R where self.x
             x: boolean
         end
      ]=]))
   end)

   describe("inline comment between a type and its assignment", function()
      it("keeps a comment between a generic type and the equals inline", helpers.check([=[
         local x: Map<string, integer> --[[c]] = {}
      ]=]))

      it("keeps a comment between a variable attribute and the equals inline", helpers.check([=[
         local x <const> --[[c]] = 1
      ]=]))

      it("keeps both a pre-equals comment and a statement trailing comment", helpers.check([=[
         local x --[[c]] = 1 -- done
      ]=]))

      it("keeps both a pre-equals comment and a trailing comment on an assignment", helpers.check([=[
         x --[[c]] = 2 -- after
      ]=]))

      it("keeps a run of pre-equals comments with a trailing comment", helpers.check([=[
         local a --[[b1]] --[[b2]] = 3 -- t
      ]=]))

      it("keeps both comments when the initializer wraps", helpers.format([=[
         local long_variable_name --[[note]] = some_function_call(argument_one, argument_two) -- trailing words here
      ]=], [=[
         local long_variable_name --[[note]] = some_function_call(
             argument_one, argument_two
         ) -- trailing words here
      ]=]))
   end)

   describe("inline comment after an as/is cast keyword", function()
      it("keeps a comment between as and its type", helpers.check([=[
         local x = y as --[[c]] integer
      ]=]))

      it("keeps a comment between as and a parenthesized type", helpers.check([=[
         local x = y as --[[c]] (integer)
      ]=]))

      it("keeps a comment between is and its type", helpers.check([=[
         local x = y is --[[c]] integer
      ]=]))
   end)

   describe("inline comment inside a function header", function()
      it("relocates a comment between a method receiver and its colon", helpers.format([=[
         function a.b --[[c]] : c()
         end
      ]=], [=[
         --[[c]]
         function a.b:c()
         end
      ]=]))

      it("relocates a comment between a parameter name and its colon", helpers.format([=[
         local function f(a --[[c]]: integer)
         end
      ]=], [=[
         --[[c]]
         local function f(a: integer)
         end
      ]=]))
   end)

   describe("inline comment inside parentheses", function()
      it("relocates a comment after an opening parenthesis", helpers.format([=[
         local x = ( --[[c]] 1 )
      ]=], [=[
         --[[c]]
         local x = (1)
      ]=]))

      it("relocates a comment before a closing parenthesis", helpers.format([=[
         local x = ( 1 --[[c]] )
      ]=], [=[
         --[[c]]
         local x = (1)
      ]=]))
   end)

   describe("inline comment around labels and for-in", function()
      it("relocates a comment between :: and a label name", helpers.format([=[
         :: --[[c]] L ::
      ]=], [=[
         --[[c]]
         ::L::
      ]=]))

      it("relocates a comment between a label name and ::", helpers.format([=[
         :: L --[[c]] ::
      ]=], [=[
         --[[c]]
         ::L::
      ]=]))

      it("relocates a comment between a for-in variable and in", helpers.format([=[
         for x --[[c]] in p() do
         end
      ]=], [=[
         --[[c]]
         for x in p() do
         end
      ]=]))
   end)
end)

-- Post-parse attachment regressions: positions where the old per-site drains
-- silently dropped a comment (the file then safe-skipped). The attachment pass
-- routes each to an owner by token span, so these now round-trip. One pin per
-- position class; each was an observed fuzz/corpus drop.
describe("comment attachment regressions", function()
   -- A bare `;` carries no node; its own-line leading comment must survive the
   -- statement separator being dropped (it relocates to the next gap).
   it("keeps an own-line comment before a discarded semicolon", helpers.format([[
      local x = 1
      -- note before semi
      ;
   ]], [[
      local x = 1
      -- note before semi
   ]]))

   -- The return value's trailing slot renders; the comment must not be lost to
   -- the return statement's own (unrendered) trailing position.
   it("keeps a trailing comment on a return value", helpers.check([[
      local function f()
          return x -- done
      end
   ]]))

   -- The `where` clause renders its predicate with no trailing slot, so a
   -- comment after it bubbles to the first field's leading position.
   it("moves a where-clause trailing comment to the first field", helpers.format([[
      local record r where "@" -- note
          type F = enum end
      end
   ]], [[
      local record r where "@"
          -- note
          type F = enum
          end
      end
   ]]))

   -- A block comment before a `:` type-separator has no kept slot; the sweep
   -- relocates it to statement leading rather than dropping it.
   it("relocates a block comment before a type-annotation colon", helpers.format([=[
      local x --[[ty]]: integer = 1
   ]=], [=[
      --[[ty]]
      local x: integer = 1
   ]=]))

   -- A line comment after a list separator stays as the preceding item's
   -- trailing comment even when it is the last item.
   it("keeps a trailing line comment after a table's last separator", helpers.check([[
      local t = {
          1, -- one
      }
   ]]))

   -- A leading line comment inside a nested record/interface body attaches to
   -- the first field and stays in place, rather than detaching from the body.
   it("keeps a leading comment inside a nested interface body", helpers.check([[
      local record ast
          interface I
              -- doc
              slot: integer
          end
      end
   ]]))
end)

describe("formatter comment matrix (construct gaps)", function()
   describe("statement leaves", function()
      it("[label|leading_and_trailing|kept_in_place]", helpers.check([[
         do
             -- before label
             ::top:: -- loop head
             goto top
         end
      ]]))

      it("[goto|leading_and_trailing|kept_in_place]", helpers.check([[
         do
             ::top::
             -- retry from the top
             goto top -- jump
         end
      ]]))

      it("[break|leading_and_trailing|kept_in_place]", helpers.check([[
         while true do
             -- stop here
             break -- done
         end
      ]]))

      it("[varargs|leading_and_trailing|kept_in_place]", helpers.check([[
         local function f(...)
             -- forward everything
             return ... -- unchanged
         end
      ]]))

      -- tl.lex rejects a trailing comment on a pragma line ("invalid token"),
      -- so leading is the only comment placement a pragma has.
      it("[pragma|leading|kept_in_place]", helpers.check([[
         -- enable arity checks
         --#pragma arity on
      ]]))
   end)

   describe("record body entries", function()
      it("[record|metamethod|leading_and_trailing|kept_in_place]", helpers.check([[
         local record R
             -- pairwise addition
             metamethod __add: function(R, R): R -- checked
         end
      ]]))
   end)

   -- A block comment wedged inside inline type syntax has no kept slot; the
   -- per-statement sweep relocates it to the statement's own-line leading.
   describe("type forms", function()
      it("[map_type|key_block|relocates_to_leading]", helpers.format([==[
         local m: {--[[k]] string: integer} = {}
      ]==], [==[
         --[[k]]
         local m: {string: integer} = {}
      ]==]))

      it("[union_type|bar_block|relocates_to_leading]", helpers.format([==[
         local u: integer --[[or]] | string
      ]==], [==[
         --[[or]]
         local u: integer | string
      ]==]))

      it("[tupletable_type|item_block|relocates_to_leading]", helpers.format([==[
         local t: {--[[first]] integer, string}
      ]==], [==[
         --[[first]]
         local t: {integer, string}
      ]==]))
   end)

   -- Interface bodies ride the record-like path; pin the same placements the
   -- [record|...] cases pin so the shared path cannot regress for one construct
   -- only.
   describe("interface parity", function()
      it("[interface|single|leading_before_first|top_level_comment_prelude]", helpers.format([[
         -- top-level prelude comment
         local interface Shape
           area: function(Shape): number -- inline field comment
           -- end comment
         end
      ]], [[
         -- top-level prelude comment
         local interface Shape
             area: function(Shape): number -- inline field comment
             -- end comment
         end
      ]]))

      it("[interface|name_block|leads_first_field]", helpers.format([==[
         local interface I --[[c]] x: integer end
      ]==], [==[
         local interface I
             --[[c]]
             x: integer
         end
      ]==]))

      it("[interface|name_block|empty_body_dangles]", helpers.format([==[
         local interface I --[[c]] end
      ]==], [==[
         local interface I
             --[[c]]
         end
      ]==]))

      it("[interface|field|trailing_line_comment]", helpers.check([[
         local interface I
             x: number -- c
         end
      ]]))

      it("[interface|name_block|is_clause_relocates_to_leading]", helpers.format([==[
         local interface A end
         local interface I --[[c]] is A x: integer end
      ]==], [==[
         local interface A
         end
         --[[c]]
         local interface I is A
             x: integer
         end
      ]==]))

      it("[interface|header_kw_block|relocates_to_leading]", helpers.format([==[
         local interface --[[c]] I
             x: integer
         end
      ]==], [==[
         --[[c]]
         local interface I
             x: integer
         end
      ]==]))
   end)
end)
