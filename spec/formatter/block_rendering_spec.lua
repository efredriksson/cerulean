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

      it("reindents and normalises a compact numeric for range", helpers.format([[
         local function f()
           for i=1,2 do
             tick(i)
           end
         end
      ]], [[
         local function f()
             for i = 1, 2 do
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

      it("reindents a function body with a long single-arg assignment call without overflowing the line", helpers.format([[
         local function f()
           cache[item_name] = loader.fetch_resource(
             "prefix/" .. item_name .. "/long_resource_name.ext"
           )
         end
      ]], [[
         local function f()
             cache[item_name] = loader.fetch_resource(
                 "prefix/" .. item_name .. "/long_resource_name.ext"
             )
         end
      ]]))

      it("reindents a top-level if block where the condition call has one overlong arg", helpers.format([[
         if f_in_if(first_parameter_with_a_very_long_long_long_long_long_long_long_long_name) then
           print('ok')
         end
      ]], [[
         if f_in_if(
             first_parameter_with_a_very_long_long_long_long_long_long_long_long_name
         ) then
             print("ok")
         end
      ]]))

      it("reindents a top-level if block where the condition call has two long args fitting compactly", helpers.format([[
         if f_in_if(first_parameter_with_a_very_long_name, second_parameter_with_a_very_long_name) then
           print('ok')
         end
      ]], [[
         if f_in_if(
             first_parameter_with_a_very_long_name, second_parameter_with_a_very_long_name
         ) then
             print("ok")
         end
      ]]))

      it("reindents a top-level if block where the condition call has three long args each on its own line", helpers.format([[
         if f_in_if(first_parameter_with_a_very_long_name, second_parameter_with_a_very_long_name, third_parameter_with_a_very_long_name) then
           print('ok')
         end
      ]], [[
         if f_in_if(
             first_parameter_with_a_very_long_name,
             second_parameter_with_a_very_long_name,
             third_parameter_with_a_very_long_name
         ) then
             print("ok")
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

      it("reindents a block containing a const local declaration", helpers.format([[
         local function f()
           local x <const> = 1
           return x
         end
      ]], [[
         local function f()
             local x <const> = 1
             return x
         end
      ]]))

      it("reindents a block containing a total local declaration", helpers.format([[
         local function f()
           local y <total> = 1
           return y
         end
      ]], [[
         local function f()
             local y <total> = 1
             return y
         end
      ]]))

      it("reindents a block containing a mixed attributed multi-local declaration", helpers.format([[
         local function f()
           local first <const>, second <total> = compute_pair()
           return first, second
         end
      ]], [[
         local function f()
             local first <const>, second <total> = compute_pair()
             return first, second
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
         return interval_overlap(self.x, self.x + self.width, other.x, other.x + other.width)
             and interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
      ]]))

      it("reindents a top-level block while preserving a single blank line", helpers.format(
         "local ready = true\n\nif ready then\n  tick()\nend\nreturn ready\n",
         "local ready = true\n\nif ready then\n    tick()\nend\nreturn ready\n"
      ))
   end)
   describe("top-level locals", function()
      it("preserves an inline comment on a record field while reindenting", helpers.format([[
         local record Config
           value: integer -- used for some purpose
         end
      ]], [[
         local record Config
             value: integer -- used for some purpose
         end
      ]]))

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

   describe("op call statements", function()
      it("reindents a function body with a multiline op call statement", helpers.format([[
         local function f()
           lutro.graphics.rectangle(
             "line",
             self.x,
             self.y,
             self.width
           )
         end
      ]], [[
         local function f()
             lutro.graphics.rectangle("line", self.x, self.y, self.width)
         end
      ]]))

      it("reindents a function body with two multiline op call statements", helpers.format([[
         local function f()
           table.insert(
             self.items,
             new_item
           )
           table.insert(
             self.items,
             other_item
           )
         end
      ]], [[
         local function f()
             table.insert(self.items, new_item)
             table.insert(self.items, other_item)
         end
      ]]))

      it("reindents a top-level multiline op call statement", helpers.format([[
         lutro.graphics.rectangle(
           "line",
           self.x,
           self.y,
           self.width
         )
          return done
      ]], [[
         lutro.graphics.rectangle("line", self.x, self.y, self.width)
         return done
      ]]))

      it("formats a multi-statement anonymous function call argument", helpers.format([[
         local function f()
           walk_descendants(node, function(child)
             local x = 1
             process(x)
           end)
         end
      ]], [[
         local function f()
             walk_descendants(node, function(child) local x = 1 process(x) end)
         end
      ]]))

      it("formats and wraps functional call if argument table must wrap", helpers.format([[
         local function f()
           walk_descendants(node, {SomethingVeryLong1 = 1, SomethingVeryLong2 = 2, SomethingVeryLong3 = 3, SomethingVeryLong4 = 4})
         end
      ]], [[
         local function f()
             walk_descendants(
                 node,
                 {
                     SomethingVeryLong1 = 1,
                     SomethingVeryLong2 = 2,
                     SomethingVeryLong3 = 3,
                     SomethingVeryLong4 = 4,
                 }
             )
         end
      ]]))
   end)

   describe("record function body with multiline call and trailing content", function()
      it("reindents a record function body whose single return has a multiline call with trailing arithmetic on the closing line",
         helpers.format([[
            function Obj.compute(x: number): number
              return math.floor(
                x / STEP + 0.5
              ) * STEP
            end
         ]], [[
            function Obj.compute(x: number): number
                return math.floor(x / STEP + 0.5) * STEP
            end
         ]]))
      it("leaves a record function body stable when the return has a multiline call whose trailing content continues on the next line",
         helpers.check([[
            function Obj.overlap(other: Obj): boolean
                return intersects(self.x, self.x + self.width, other.x, other.x + other.width)
                    and intersects(self.y, self.y + self.height, other.y, other.y + other.height)
            end
         ]]))
   end)

   describe("record function body blocked by remaining cases", function()
      it("reindents a record function body whose return table has inline section comments",
         helpers.format([[
            function Obj.items(): {string}
              return {
                -- first section
                "a",
                "b",
              }
            end
         ]], [[
            function Obj.items(): {string}
                return {
                    -- first section
                    "a",
                    "b",
                }
            end
         ]]))
      it("reindents a record function body whose return has a multiline call continued with a binary op on the next line",
         helpers.format([[
            function Obj.overlap(other: Obj): boolean
              return intersects(
                self.x, other.x
              ) and
                intersects(self.y, other.y)
            end
         ]], [[
            function Obj.overlap(other: Obj): boolean
                return intersects(self.x, other.x) and intersects(self.y, other.y)
            end
         ]]))

      it("reindents a record function body containing a for loop whose body has an inline trailing comment separated by a blank line",
         helpers.format([[
            function Obj:update(dt: number)
              self.active = false -- reset each frame

              for _, item in ipairs(self.items) do
                self.active = true -- item found

                -- process it
                process(item, dt)
              end
            end
         ]], [[
            function Obj:update(dt: number)
                self.active = false -- reset each frame

                for _, item in ipairs(self.items) do
                    self.active = true -- item found

                    -- process it
                    process(item, dt)
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


   describe("enums", function ()
      it("gets indented", helpers.format([[
         local enum TestEnum
            "a"
            "b"
         end
      ]], [[
         local enum TestEnum
             "a"
             "b"
         end
      ]]))

      it("perserves if defined as type", helpers.format([[
         local type TestEnum = enum
            "a"
            "b"
         end
      ]], [[
         local type TestEnum = enum
             "a"
             "b"
         end
      ]]))

   end)

   describe("local function fallback gaps", function()
      it("reindents a local helper with inline if/else return", helpers.format([[
         local function normalize_value(n: integer, prefix: string): string
           if n < 10 then return prefix .. n else return tostring(n) end
         end
      ]], [[
         local function normalize_value(n: integer, prefix: string): string
             if n < 10 then
                 return prefix .. n
             else
                 return tostring(n)
             end
         end
      ]]))

      it("reindents a local for-loop helper with inline return in if", helpers.format([[
         local function find_match_index(values: {number}, target: number): integer
           for i, value in ipairs(values) do
             if value == target then return i end
           end
           return 1
         end
      ]], [[
         local function find_match_index(values: {number}, target: number): integer
             for i, value in ipairs(values) do
                 if value == target then
                     return i
                 end
             end
             return 1
         end
      ]]))

      it("reindents an empty local function declaration body", helpers.format([[
         local function no_op(_: Context) end
      ]], [[
         local function no_op(_: Context)
         end
      ]]))

      it("reindents a local helper with inline if/else boolean return", helpers.format([[
         local function has_content(name: string): boolean
           local handle = io.open(name, "r")
           if handle ~= nil then io.close(handle) return true else return false end
         end
      ]], [[
         local function has_content(name: string): boolean
             local handle = io.open(name, "r")
             if handle ~= nil then
                 io.close(handle)
                 return true
             else
                 return false
             end
         end
      ]]))

      it("reindents a nested local helper with inline return inside for-loop", helpers.format([[
         local function has_locked_item(items: {ItemState}): boolean
           for _, item in ipairs(items) do
             if item.state.locked then return true end
           end
           return false
         end
      ]], [[
         local function has_locked_item(items: {ItemState}): boolean
             for _, item in ipairs(items) do
                 if item.state.locked then
                     return true
                 end
             end
             return false
         end
      ]]))

      it("reindents an outer local function that contains an inline-return helper", helpers.format([[
         local function compute_status(items: {ItemState}): boolean
           local function has_locked_item(entries: {ItemState}): boolean
             for _, entry in ipairs(entries) do
               if entry.state.locked then return true end
             end
             return false
           end
           return has_locked_item(items)
         end
      ]], [[
         local function compute_status(items: {ItemState}): boolean
             local function has_locked_item(entries: {ItemState}): boolean
                 for _, entry in ipairs(entries) do
                     if entry.state.locked then
                         return true
                     end
                 end
                 return false
             end
             return has_locked_item(items)
         end
      ]]))
   end)

   describe("signature and return-expression regressions", function()
      it("preserves constrained generic type parameters on local function signatures", helpers.format([[
         local function map_local<K is Base, V>(left: Bucket<K>, right: Bucket<V>): {K: V}
           return {}
         end
      ]], [[
         local function map_local<K is Base, V>(left: Bucket<K>, right: Bucket<V>): {K: V}
             return {}
         end
      ]]))

      it("preserves constrained generic type parameters on global function signatures", helpers.format([[
         function map_global<K is Base, V>(left: Bucket<K>, right: Bucket<V>): {K: V}
           return {}
         end
      ]], [[
         function map_global<K is Base, V>(left: Bucket<K>, right: Bucket<V>): {K: V}
             return {}
         end
      ]]))

      it("preserves constrained generic type parameters on method signatures", helpers.format([[
         function Container:map_pairs<K is Base, V>(left: Bucket<K>, right: Bucket<V>): {K: V}
           return {}
         end
      ]], [[
         function Container:map_pairs<K is Base, V>(left: Bucket<K>, right: Bucket<V>): {K: V}
             return {}
         end
      ]]))

      it("preserves constrained generic type parameters on static function signatures", helpers.format([[
         function Container.map_pairs<K is Base, V>(left: Bucket<K>, right: Bucket<V>): {K: V}
           return {}
         end
      ]], [[
         function Container.map_pairs<K is Base, V>(left: Bucket<K>, right: Bucket<V>): {K: V}
             return {}
         end
      ]]))

      it("wraps long boolean return expressions instead of forcing a single line", helpers.format([[
         local function is_allowed(
           in_first_zone: boolean,
           in_second_zone: boolean,
           direction: string
         ): boolean
           return (in_first_zone and (direction == "left" or direction == "right")) or (in_second_zone and (direction == "up" or direction == "down"))
         end
      ]], [[
         local function is_allowed(
             in_first_zone: boolean, in_second_zone: boolean, direction: string
         ): boolean
             return (in_first_zone and (direction == "left" or direction == "right"))
                 or (in_second_zone and (direction == "up" or direction == "down"))
         end
      ]]))

      it("keeps short boolean return expressions on one line", helpers.format([[
         local function is_allowed(active: boolean, enabled: boolean): boolean
           return active and enabled
         end
      ]], [[
         local function is_allowed(active: boolean, enabled: boolean): boolean
             return active and enabled
         end
      ]]))

      it("preserves parentheses and precedence when wrapping top-level boolean returns", helpers.format([[
         local function is_allowed(
           in_first_zone: boolean,
           in_second_zone: boolean,
           direction: string,
           enabled: boolean
         ): boolean
           return ((in_first_zone and enabled) or (in_second_zone and enabled)) and (direction == "left" or direction == "right")
         end
      ]], [[
         local function is_allowed(
             in_first_zone: boolean, in_second_zone: boolean, direction: string, enabled: boolean
         ): boolean
             return ((in_first_zone and enabled) or (in_second_zone and enabled))
                 and (direction == "left" or direction == "right")
         end
      ]]))

      it("preserves constrained type parameters on local records", helpers.format([[
         local record Box<T is Base>
            value: T
         end
      ]], [[
         local record Box<T is Base>
             value: T
         end
      ]]))

      it("preserves constrained type parameters on local interfaces", helpers.format([[
         local interface Mapper<T is Base, U>
            map: function(self, value: T): U
         end
      ]], [[
         local interface Mapper<T is Base, U>
             map: function(self, value: T): U
         end
      ]]))

      it("preserves constrained type parameters on local type interface aliases", helpers.format([[
         local type Alias<T is Base> = interface
            value: T
         end
      ]], [[
         local type Alias<T is Base> = interface
             value: T
         end
      ]]))
   end)
end)
