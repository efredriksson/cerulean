local helpers = require("spec.formatter.helpers")

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

      it("preserves inline interface field comments in local type interface declarations (anonymized)", helpers.format([[
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
   end)
end)
