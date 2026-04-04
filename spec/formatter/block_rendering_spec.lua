local helpers = require("spec.formatter.helpers")

describe("formatter structural block rendering", function()

   describe("function bodies", function()
      it("reindents a clean local function body with wrong space indentation", helpers.format([[
         local function f()
           local x =  1
         end
      ]], [[
         local function f()
             local x = 1
         end
      ]]))

      it("reindents clean if elseif else blocks with wrong space indentation", helpers.format([[
         local function f(flag: boolean)
           if flag then
             log("yes" )
           elseif not flag then
             log("maybe")
           else
             log("no")
           end
         end
      ]], [[
         local function f(flag: boolean)
             if flag then
                 log("yes")
             elseif not flag then
                 log("maybe")
             else
                 log("no")
             end
         end
      ]]))

      it("reindents a clean while block with wrong space indentation", helpers.format([[
         local function f( )
           while ready() do
             tick()
           end
         end
      ]], [[
         local function f()
             while ready() do
                 tick()
             end
         end
      ]]))

      it("reindents a clean do block with wrong space indentation", helpers.format([[
         local function f()
           do
                     tick()
           end
         end
      ]], [[
         local function f()
             do
                 tick()
             end
         end
      ]]))

      it("reindents a clean repeat block with wrong space indentation", helpers.format([[
         local function f()
           repeat
             tick()
           until done()
         end
      ]], [[
         local function f()
             repeat
                 tick()
             until done()
         end
      ]]))

      it("reindents a clean numeric for block with wrong space indentation", helpers.format([[
         local function f()
           for i = 1,    3 do
             tick(i)
           end
         end
      ]], [[
         local function f()
             for i = 1, 3 do
                 tick(i)
             end
         end
      ]]))

      it("reindents a clean generic for block with wrong space indentation", helpers.format([[
         local function f(items: {string})
           for _, item in ipairs(items) do
             log(item)
           end
         end
      ]], [[
         local function f(items: {string})
             for _, item in ipairs(items) do
                 log(item)
             end
         end
      ]]))

      it("reindents clean assignment return and expression statements", helpers.format([[
         local function f()
           local x = 1
           x = x + 1
           log(x)
           return x
         end
      ]], [[
         local function f()
             local x = 1
             x = x + 1
             log(x)
             return x
         end
      ]]))

      it("reindents nested clean blocks transitively", helpers.format([[
         local function f(items: {string})
           for _, item in ipairs(items) do
             if active(item) then
               log(item)
             end
           end
         end
      ]], [[
         local function f(items: {string})
             for _, item in ipairs(items) do
                 if active(item) then
                     log(item)
                 end
             end
         end
      ]]))

      it("reindents a colon method definition with a clean block body", helpers.format([[
         function Obj:method(flag: boolean)
           if flag then
             log(self)
           end
         end
      ]], [[
         function Obj:method(flag: boolean)
             if flag then
                 log(self)
             end
         end
      ]]))

      it("reindents a dotted record function with nested clean blocks", helpers.format([[
         function Obj.build(items: {string})
           for _, item in ipairs(items) do
             if active(item) then
               log(item)
             end
           end
         end
      ]], [[
         function Obj.build(items: {string})
             for _, item in ipairs(items) do
                 if active(item) then
                     log(item)
                 end
             end
         end
      ]]))

      it("reindents a function body with a local type and multiline if condition", helpers.format([[
         local function f(ready: boolean, active: boolean)
           local type Result = string | number
           if ready
               and active
           then
             return
           end
         end
      ]], [[
         local function f(ready: boolean, active: boolean)
             local type Result = string | number
             if ready and active then
                 return
             end
         end
      ]]))

      it("reindents a function body with break in a multiline while condition", helpers.format([[
         local function f()
           while ready()
               and active()
           do
             break
           end
         end
      ]], [[
         local function f()
             while ready() and active() do
                 break
             end
         end
      ]]))

      it("reindents a function body with a typed local and multiline if condition", helpers.format([[
         local function f()
           local current: ResultType = compute_result()
           if ready()
               and active()
           then
             log(current)
           end
         end
      ]], [[
         local function f()
             local current: ResultType = compute_result()
             if ready() and active() then
                 log(current)
             end
         end
      ]]))

      it("reindents a function body with a richer return expression under a multiline while condition", helpers.format([[
         local function f()
           while ready()
               and active()
           do
             return left_value + right_value * compute_result()
           end
         end
      ]], [[
         local function f()
             while ready() and active() do
                 return left_value + right_value * compute_result()
             end
         end
      ]]))

      it("reindents a clean function body while preserving a single blank line", helpers.format(
         "local function f()\n  local x = 1\n\n  return x\nend\n",
         "local function f()\n    local x = 1\n\n    return x\nend\n"
      ))

      it("reindents a function body with a multiline local call rhs", helpers.format([[
         local function setup()
           local selected = foo.new_selection(
             some_settings.long_field_name,
             minimum_value_long,
             maximum_value_long
           )
           return selected
         end
      ]], [[
         local function setup()
             local selected = foo.new_selection(
                 some_settings.long_field_name, minimum_value_long, maximum_value_long
             )
             return selected
         end
      ]]))

      it("reindents a function body with a multiline return call with a table arg", helpers.format([[
         local function setup()
           return foo.new(
             {first_option_name = first_option_value, second_option_name = second_option_value, third_option_name = third_option_value},
             done_callback
           )
         end
      ]], [[
         local function setup()
             return foo.new(
                 {
                     first_option_name = first_option_value,
                     second_option_name = second_option_value,
                     third_option_name = third_option_value,
                 },
                 done_callback
             )
         end
      ]]))
   end)

   describe("blocks that are not rendered structurally", function()
      it("keeps wrong space indentation when a comment blocks structural rendering", helpers.check([[
         local function f()
           local x = 1 -- keep this comment
           return x
         end
      ]]))

      it("keeps wrong space indentation when blank line gaps block structural rendering", helpers.format([[
         local function f()
           local x = 1


           return x
         end
      ]], [[
         local function f()
             local x = 1

             return x
         end
      ]]))

      it("keeps wrong space indentation for an unsupported const declaration", helpers.check([[
         local function f()
           local x <const> = 1
           return x
         end
      ]]))
   end)

   describe("top-level blocks", function()
      it("reindents a clean top-level if block", helpers.format([[
         if ready then
           tick()
         end
      ]], [[
         if ready then
             tick()
         end
      ]]))

      it("reindents a clean top-level mixed local if return block", helpers.format([[
         local ready = true
         if ready then
           tick()
         end
         return ready and done()
      ]], [[
         local ready = true
         if ready then
             tick()
         end
         return ready and done()
      ]]))

      it("reindents a top-level function definition with nested clean blocks", helpers.format([[
         local function build(items: {string})
           for _, item in ipairs(items) do
             if active(item) then
               log(item)
             end
           end
         end
         return build
      ]], [[
         local function build(items: {string})
             for _, item in ipairs(items) do
                 if active(item) then
                     log(item)
                 end
             end
         end
         return build
      ]]))

      it("reindents a top-level block with a multiline local call rhs", helpers.format([[
         local selected = foo.new_selection(
             some_settings.long_field_name,
             minimum_value_long,
             maximum_value_long
         )
         if enabled then
           log(selected)
         end
         return selected
      ]], [[
         local selected = foo.new_selection(
             some_settings.long_field_name, minimum_value_long, maximum_value_long
         )
         if enabled then
             log(selected)
         end
         return selected
      ]]))

      it("reindents a top-level block with a multiline local table rhs", helpers.format([[
         local items = {
             first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha,
             second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta,
             third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma
         }
         if ready then
           log(items)
         end
         return items
      ]], [[
         local items = {
             first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha,
             second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta,
             third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma,
         }
         if ready then
             log(items)
         end
         return items
      ]]))

      it("reindents a top-level block with a multiline return expression", helpers.format([[
         local ready = true
         if ready then
           tick()
         end
         return interval_overlap(
             self.x,
             self.x + self.width,
             other.x,
             other.x + other.width
         ) and
             interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
      ]], [[
         local ready = true
         if ready then
             tick()
         end
         return interval_overlap(
            self.x, self.x + self.width, other.x, other.x + other.width
         ) and interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
      ]]))

      it("reindents a top-level block while preserving a single blank line", helpers.format(
         "local ready = true\n\nif ready then\n  tick()\nend\nreturn ready\n",
         "local ready = true\n\nif ready then\n    tick()\nend\nreturn ready\n"
      ))
   end)
   describe("top-level locals", function()
      it("indents in local record", helpers.format([[
         local record MyRecord
           data: string
         end
      ]], [[
         local record MyRecord
             data: string
         end
      ]]))

      it("reindents a local record while preserving its interfaces", helpers.format([[
         local record S
           test: function()
         end

         local record B is S
           prev: S
           next: S
         end
      ]], [[
         local record S
             test: function()
         end

         local record B is S
             prev: S
             next: S
         end
      ]]))

      it("preserves a local record with interfaces and type parameters", helpers.check([[
         local record A
             label: string
         end

         local record AImpl<T> is A
             label: string
         end
      ]]))

      it("preserves a local record with metamethod declarations", helpers.check([[
         local record Point
             x: number
             y: number
             metamethod __tostring: function(Point): string
         end
      ]]))

      it("reindents an interface while preserving its interfaces and where clause", helpers.format([[
         local interface Base
           kind: string
         end

         local interface A is Base where self.kind == "a"
           name: string
         end
      ]], [[
         local interface Base
             kind: string
         end

         local interface A is Base where self.kind == "a"
             name: string
         end
      ]]))

      it("reindents a local type interface while preserving its declaration spelling", helpers.format([[
         local type A = interface
           draw: function(self)
         end
      ]], [[
         local type A = interface
             draw: function(self)
         end
      ]]))

      it("reindents a generic local record while preserving its type parameter", helpers.format([[
         local record Box<T>
           value: T
         end
      ]], [[
         local record Box<T>
             value: T
         end
      ]]))

      it("reindents a generic local record with multiple type parameters", helpers.format([[
         local record Pair<A, B>
           first: A
           second: B
         end
      ]], [[
         local record Pair<A, B>
             first: A
             second: B
         end
      ]]))

      it("reindents a generic local record with an interface", helpers.format([[
         local record Container<T> is Iterable
           items: {T}
         end
      ]], [[
         local record Container<T> is Iterable
             items: {T}
         end
      ]]))

      it("reindents a generic local interface while preserving its type parameter", helpers.format([[
         local interface Mapper<T, U>
           map: function(self, T): U
         end
      ]], [[
         local interface Mapper<T, U>
             map: function(self, T): U
         end
      ]]))
   end)

   describe("local require type aliases", function()
      it("reindents a function body with a local require type alias", helpers.format([[
         local function f()
           local type Entity = require("entity")
           local x = 1
           return x
         end
      ]], [[
         local function f()
             local type Entity = require("entity")
             local x = 1
             return x
         end
      ]]))

      it("reindents a function body with multiple local require type aliases", helpers.format([[
         local function f()
           local type Entity = require("entity")
           local type Point = require("points")
           return Entity.new()
         end
      ]], [[
         local function f()
             local type Entity = require("entity")
             local type Point = require("points")
             return Entity.new()
         end
      ]]))

      it("reindents a function body with a local require type alias and nested if block", helpers.format([[
         local function f(active: boolean)
           local type Entity = require("entity")
           if active then
             return Entity.new()
           end
         end
      ]], [[
         local function f(active: boolean)
             local type Entity = require("entity")
             if active then
                 return Entity.new()
             end
         end
      ]]))
   end)

   describe("generic functions", function()
      it("preserves type parameters on a local function", helpers.check([[
         local function identity<T>(value: T): T
             return value
         end
      ]]))

      it("reindents a generic record function body while preserving its type parameter", helpers.format([[
         function M.get<T>(n: integer): T
           return store[n]
         end
      ]], [[
         function M.get<T>(n: integer): T
             return store[n]
         end
      ]]))
   end)
end)
