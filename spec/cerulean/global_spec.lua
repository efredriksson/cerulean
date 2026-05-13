local helpers = require("spec.cerulean.helpers")

describe("formatter global declarations", function()

   describe("global type = interface", function()
      it("formats global type = interface", helpers.format([[
         global type Foo = interface
           x: integer
         end
      ]], [[
         global type Foo = interface
             x: integer
         end
      ]]))
   end)

   describe("global type = record", function()
      it("formats global type = record", helpers.format([[
         global type Foo = record
           x: integer
         end
      ]], [[
         global type Foo = record
             x: integer
         end
      ]]))
   end)

   describe("global type = enum", function()
      it("formats global type = enum", helpers.format([[
         global type Foo = enum
           "a"
           "b"
         end
      ]], [[
         global type Foo = enum
             "a"
             "b"
         end
      ]]))
   end)

   describe("global function", function()
      it("is fomratted with global keyword", helpers.format([[
         global function f ( )
         end
      ]], [[
         global function f()
         end
      ]]))
   end)

   describe("global interface (shorthand)", function()
      it("formats global interface shorthand", helpers.format([[
         global interface Foo
           x: integer
         end
      ]], [[
         global interface Foo
             x: integer
         end
      ]]))
   end)

   describe("global record (shorthand)", function()
      it("formats global record shorthand", helpers.format([[
         global record Foo
           x: integer
         end
      ]], [[
         global record Foo
             x: integer
         end
      ]]))
   end)

   describe("global enum (shorthand)", function()
      it("formats global enum shorthand", helpers.format([[
         global enum Foo
           "a"
           "b"
         end
      ]], [[
         global enum Foo
             "a"
             "b"
         end
      ]]))
   end)

   describe("global type forward declaration", function()
      it("preserves global type with no body", helpers.check([[
         global type Foo
      ]]))

      it("preserves global type forward decl among other statements", helpers.check([[
         global type Foo
         local x = 1
      ]]))
   end)

   describe("global variable declaration", function()
      it("formats global var with type only", helpers.format([[
         global x : integer
      ]], [[
         global x: integer
      ]]))

      it("formats global var with type and value", helpers.format([[
         global x : integer = 5
      ]], [[
         global x: integer = 5
      ]]))
   end)

   describe("overloaded methods in record body (known bug)", function()
      it("formats local record with overloaded methods", helpers.format([[
         local record Foo
           bar: function(self: Foo): string
           bar: function(self: Foo, x: integer): string
           baz: integer
         end
      ]], [[
         local record Foo
             bar: function(self: Foo): string
             bar: function(self: Foo, x: integer): string
             baz: integer
         end
      ]]))

      it("formats global record with overloaded methods", helpers.format([[
         global record Foo
           bar: function(self: Foo): string
           bar: function(self: Foo, x: integer): string
           baz: integer
         end
      ]], [[
         global record Foo
             bar: function(self: Foo): string
             bar: function(self: Foo, x: integer): string
             baz: integer
         end
      ]]))

      it("formats nested record with overloaded methods", helpers.format([[
         global record Outer
           x: integer
           record Inner
             fn: function(): string
             fn: function(x: integer): string
           end
         end
      ]], [[
         global record Outer
             x: integer
             record Inner
                 fn: function(): string
                 fn: function(x: integer): string
             end
         end
      ]]))
   end)

   describe("type = record inside interface body", function()
      it("preserves type X = record syntax (not bare record X)", helpers.check([[
         local interface I
             type Foo = record
                 x: integer
             end
         end
      ]]))

      it("preserves generic type X<T> = record syntax inside interface", helpers.check([[
         local interface I
             type Foo<T> = record
                 x: T
             end
         end
      ]]))
   end)

   describe("crash regressions", function()
      it("does not crash on parenthesized invalid type in type list", helpers.parse_error([[
         local f: function(): string, (,), number
      ]]))

      it("does not crash on keyword used as identifier after dot in interface is-list", helpers.parse_error([[
         global interface B is x.if end
      ]]))

      it("does not crash on keyword as argument name followed by optional marker", helpers.parse_error([[
         local f = function(or ?) end
      ]]))
   end)

   describe("blank line preservation in record bodies", function()
      it("preserves blank line between fields in record body", helpers.format([[
         global record Foo
           x: integer

           y: integer
         end
      ]], [[
         global record Foo
             x: integer

             y: integer
         end
      ]]))

      it("preserves blank line between nested records in record body", helpers.format([[
         global record Outer
           record Foo
             x: integer
           end

           record Bar
             y: integer
           end
         end
      ]], [[
         global record Outer
             record Foo
                 x: integer
             end

             record Bar
                 y: integer
             end
         end
      ]]))
   end)

   describe("optional parameters in function types", function()
      it("preserves optional parameter that is not the last parameter", helpers.check([[
         global o: function(a: string, b?: number, c: boolean)
      ]]))

      it("preserves first parameter being optional in a function type", helpers.check([[
         global o: function(?string, number, boolean)
      ]]))
   end)

end)
