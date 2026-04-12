local helpers = require("spec.formatter.helpers")

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

end)
