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

      it("preserves block comment before nominal type in parenthesized is-cast", helpers.format([=[
         x = b is(--[[note]] integer)
      ]=], [=[
         x = b is (--[[note]] integer)
      ]=]))

      it("preserves block comment before array type in parenthesized is-cast", helpers.format([=[
         x = b is(--[[note]] {integer})
      ]=], [=[
         x = b is (--[[note]] {integer})
      ]=]))

      it("preserves block comment before map type in parenthesized as-cast", helpers.format([=[
         x = b as(--[[note]] {string: integer})
      ]=], [=[
         x = b as (--[[note]] {string: integer})
      ]=]))

      it("preserves block comment before union type in parenthesized is-cast", helpers.format([=[
         x = b is(--[[note]] integer | string)
      ]=], [=[
         x = b is (--[[note]] integer | string)
      ]=]))

      it("preserves block comment before multi-type tuple in parenthesized as-cast", helpers.format([=[
         x = b as(--[[note]] integer, string)
      ]=], [=[
         x = b as (--[[note]] integer, string)
      ]=]))

      it("preserves multiple block comments before type in parenthesized is-cast", helpers.format([=[
         x = b is(--[[a]] --[[b]] integer)
      ]=], [=[
         x = b is (--[[a]] --[[b]] integer)
      ]=]))

      it("preserves block comment before second type in parenthesized as-cast", helpers.format([=[
         x = b as(integer, --[[note]] string)
      ]=], [=[
         x = b as (integer, --[[note]] string)
      ]=]))

      it("preserves block comment between type and comma in parenthesized as-cast", helpers.format([=[
         x = b as(integer --[[between]], string)
      ]=], [=[
         x = b as (integer --[[between]], string)
      ]=]))

      it("preserves trailing block comment before close-paren in parenthesized as-cast", helpers.format([=[
         x = b as(integer, string --[[trailing]])
      ]=], [=[
         x = b as (integer, string --[[trailing]])
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
             ((b == 1)
                     -- then second
                     or (b == 2)) then
             f()
         end
      ]]))

      it("preserves block comment between multi-assignment lhs and equals", helpers.check([=[
         i, t --[[what is t for?]] = f(i)
      ]=]))

      it("preserves block comment in middle of multi-assignment lhs and equals", helpers.check([=[
         i, t --[[what is t for?]], k = f(i)
      ]=]))

      it("preserves block comment after first var in multi-assignment lhs", helpers.check([=[
         i --[[what is i?]], t = f(i)
      ]=]))

      it("preserves block comment after first call arg before comma", helpers.check([=[
         f(x --[[what is x?]], y)
      ]=]))

      it("preserves block comment after first table field before comma", helpers.check([=[
         local t = {1 --[[first?]], 2}
      ]=]))

      it("preserves multiple block comments after assignment lhs before equals", helpers.check([=[
         local x --[[c1]] --[[c2]] = 1
      ]=]))

      it("preserves block comment after first rhs exp before comma in declaration", helpers.check([=[
         local x, y = 1 --[[first?]], 2
      ]=]))

      it("preserves block comment after first rhs exp before comma in assignment", helpers.check([=[
         x, y = 1 --[[first?]], 2
      ]=]))

      it("preserves multiple block comments after first rhs exp before comma", helpers.check([=[
         local x, y = 1 --[[c1]] --[[c2]], 2
      ]=]))

      it("keeps a block comment after a call-arg comma flat on the next arg", helpers.check([=[
         f(x, --[[why y?]] y)
      ]=]))

      it("keeps a block comment after a table-field comma flat on the next field", helpers.check([=[
         local t = {1, --[[second]] 2}
      ]=]))

      it("keeps a block comment after a declaration-rhs comma flat", helpers.check([=[
         local x, y = 1, --[[second]] 2
      ]=]))

      it("keeps a block comment after an assignment-rhs comma flat", helpers.check([=[
         x, y = 1, --[[second]] 2
      ]=]))

      it("keeps a block comment after an assignment-lhs comma flat", helpers.check([=[
         x, --[[why y?]] y = f()
      ]=]))

      it("keeps a block comment after a declaration-name comma flat", helpers.check([=[
         local x, --[[why y?]] y = 1, 2
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

   describe("block comments inside type syntax", function()
      it("preserves block comment before first type argument", helpers.format([=[
         local x: Map<--[[k]]string, integer>
      ]=], [=[
         local x: Map<--[[k]] string, integer>
      ]=]))

      it("preserves block comment before later type argument", helpers.format([=[
         local x: Map<string, --[[v]]integer>
      ]=], [=[
         local x: Map<string, --[[v]] integer>
      ]=]))

      it("preserves block comment after last type argument", helpers.format([=[
         local x: Foo<integer--[[t]]>
      ]=], [=[
         local x: Foo<integer --[[t]]>
      ]=]))

      it("preserves block comment before a declared type parameter", helpers.format([=[
         local type F = function<T, --[[c]]U>(T): U
      ]=], [=[
         local type F = function<T, --[[c]] U>(T): U
      ]=]))

      it("preserves block comments throughout a tuple table type", helpers.format([=[
         local x: {--[[a]]integer, string--[[b]], boolean}
      ]=], [=[
         local x: {--[[a]] integer, string --[[b]], boolean}
      ]=]))

      it("preserves block comment before an array element type", helpers.format([=[
         local x: {--[[c]]integer}
      ]=], [=[
         local x: {--[[c]] integer}
      ]=]))

      it("preserves block comment after an array element type", helpers.format([=[
         local x: {integer--[[c]]}
      ]=], [=[
         local x: {integer --[[c]]}
      ]=]))

      it("preserves block comment before a map key type", helpers.format([=[
         local x: {--[[k]]string: integer}
      ]=], [=[
         local x: {--[[k]] string: integer}
      ]=]))

      it("preserves block comment before a map value type", helpers.format([=[
         local x: {string: --[[v]]integer}
      ]=], [=[
         local x: {string: --[[v]] integer}
      ]=]))

      it("preserves block comment after a map key type", helpers.format([=[
         local x: {string--[[bk]]: integer}
      ]=], [=[
         local x: {string --[[bk]]: integer}
      ]=]))

      it("preserves block comments around a union separator", helpers.format([=[
         local x: integer--[[a]] | --[[b]]string
      ]=], [=[
         local x: integer --[[a]] | --[[b]] string
      ]=]))

      it("preserves block comment before a function-type argument", helpers.format([=[
         local x: function(--[[a]]p: integer)
      ]=], [=[
         local x: function(--[[a]] p: integer)
      ]=]))

      it("preserves block comment between a function argument's colon and type", helpers.format([=[
         local x: function(p: --[[c]]integer)
      ]=], [=[
         local x: function(p: --[[c]] integer)
      ]=]))

      it("preserves block comment after a function argument's type", helpers.format([=[
         local x: function(p: integer--[[t]], q: string)
      ]=], [=[
         local x: function(p: integer --[[t]], q: string)
      ]=]))

      it("preserves block comment before a function return type", helpers.format([=[
         local x: function(): --[[r]]string
      ]=], [=[
         local x: function(): --[[r]] string
      ]=]))

      it("preserves block comment after an interface-list comma", helpers.format([=[
         local record R is A, --[[note]] B end
      ]=], [=[
         local record R is A, --[[note]] B
         end
      ]=]))

      it("preserves block comment before an interface-list comma", helpers.format([=[
         local record R is A --[[note]], B end
      ]=], [=[
         local record R is A --[[note]], B
         end
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

   pending("inline comment after a declaration keyword", function()
      it("relocates a comment between local and a variable name", helpers.format([=[
         local --[[c]] x = 1
      ]=], [=[
         local x = 1 --[[c]]
      ]=]))

      it("relocates a comment between global and a variable name", helpers.format([=[
         global --[[c]] x = 1
      ]=], [=[
         global x = 1 --[[c]]
      ]=]))

      it("relocates a comment between local and type", helpers.format([=[
         local --[[c]] type T = integer
      ]=], [=[
         local type T = integer --[[c]]
      ]=]))

      it("relocates a comment between local type and the name", helpers.format([=[
         local type --[[c]] T = integer
      ]=], [=[
         local type T = integer --[[c]]
      ]=]))

      it("relocates a comment between global and type", helpers.format([=[
         global --[[c]] type T = integer
      ]=], [=[
         global type T = integer --[[c]]
      ]=]))

      it("relocates a comment between global type and the name", helpers.format([=[
         global type --[[c]] T = integer
      ]=], [=[
         global type T = integer --[[c]]
      ]=]))

      it("relocates a comment between local and function", helpers.format([=[
         local --[[c]] function f()
         end
      ]=], [=[
         local function f() --[[c]]
         end
      ]=]))

      it("relocates a comment between local function and the name", helpers.format([=[
         local function --[[c]] f()
         end
      ]=], [=[
         local function f() --[[c]]
         end
      ]=]))

      it("relocates a comment between global and function", helpers.format([=[
         global function --[[c]] f()
         end
      ]=], [=[
         global function f() --[[c]]
         end
      ]=]))

      it("relocates a comment between local and record", helpers.format([=[
         local --[[c]] record R
             x: integer
         end
      ]=], [=[
         local record R
             --[[c]]
             x: integer
         end
      ]=]))

      it("relocates a comment between local record and the name", helpers.format([=[
         local record --[[c]] R
             x: integer
         end
      ]=], [=[
         local record R
             --[[c]]
             x: integer
         end
      ]=]))

      it("relocates a comment between global and record", helpers.format([=[
         global --[[c]] record R
             x: integer
         end
      ]=], [=[
         global record R
             --[[c]]
             x: integer
         end
      ]=]))

      it("relocates a comment between local enum and the name", helpers.format([=[
         local enum --[[c]] E
             "a"
         end
      ]=], [=[
         local enum E
             --[[c]]
             "a"
         end
      ]=]))

      it("relocates a comment between local interface and the name", helpers.format([=[
         local interface --[[c]] I
             x: integer
         end
      ]=], [=[
         local interface I
             --[[c]]
             x: integer
         end
      ]=]))

      it("relocates a comment between a record name and where", helpers.format([=[
         local record R --[[c]] where self.x
             x: boolean
         end
      ]=], [=[
         local record R where self.x
             --[[c]]
             x: boolean
         end
      ]=]))
   end)

   pending("inline comment between a type and its assignment", function()
      it("keeps a comment between a generic type and the equals", helpers.check([=[
         local x: Map<string, integer> --[[c]] = {}
      ]=]))
   end)

   pending("inline comment after an as/is cast keyword", function()
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

   pending("inline comment inside a function header", function()
      it("relocates a comment between a method receiver and its colon", helpers.format([=[
         function a.b --[[c]] : c()
         end
      ]=], [=[
         function a.b:c() --[[c]]
         end
      ]=]))

      it("keeps a comment between a parameter name and its colon", helpers.check([=[
         local function f(a --[[c]]: integer)
         end
      ]=]))
   end)

   pending("inline comment inside parentheses", function()
      it("keeps a comment after an opening parenthesis", helpers.format([=[
         local x = ( --[[c]] 1 )
      ]=], [=[
         local x = (--[[c]] 1)
      ]=]))

      it("keeps a comment before a closing parenthesis", helpers.format([=[
         local x = ( 1 --[[c]] )
      ]=], [=[
         local x = (1 --[[c]])
      ]=]))
   end)

   pending("inline comment around labels and for-in", function()
      it("relocates a comment between :: and a label name", helpers.format([=[
         :: --[[c]] L ::
      ]=], [=[
         ::L:: --[[c]]
      ]=]))

      it("relocates a comment between a label name and ::", helpers.format([=[
         :: L --[[c]] ::
      ]=], [=[
         ::L:: --[[c]]
      ]=]))

      it("keeps a comment between a for-in variable and in", helpers.check([=[
         for x --[[c]] in p() do
         end
      ]=]))
   end)
end)
