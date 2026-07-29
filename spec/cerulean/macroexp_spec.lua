local helpers = require("spec.cerulean.helpers")

describe("formatter local macroexp", function()

   it("reindents body with wrong indentation", helpers.format([[
      local macroexp m(a: A): A
         return a
      end
   ]], [[
      local macroexp m(a: A): A
          return a
      end
   ]]))

   it("wraps a long signature to compact form", helpers.format([[
      local macroexp apply(func: function(x: LongTypeName): ResultType, value: LongTypeName): ResultType
          return func(value)
      end
   ]], [[
      local macroexp apply(
          func: function(x: LongTypeName): ResultType, value: LongTypeName
      ): ResultType
          return func(value)
      end
   ]]))

   it("joins a wrapped signature that fits on one line", helpers.format([[
      local macroexp m(
         param_one: TypeA,
         param_two: TypeB
      ): ReturnType
         return param_one
      end
   ]], [[
      local macroexp m(param_one: TypeA, param_two: TypeB): ReturnType
          return param_one
      end
   ]]))

   it("preserves a macroexp body on a record metamethod", helpers.format([[
      local record DoubleArray
        metamethod __len: function(self) = macroexp(self: DoubleArray)
          return self[0]
        end
      end
   ]], [[
      local record DoubleArray
          metamethod __len: function(self) = macroexp(self: DoubleArray)
              return self[0]
          end
      end
   ]]))

   it("wraps a long record field before its macroexp implementation", helpers.format([[
      local record IdAllocator
        generationOfWithSlot: function(id: integer, slot: integer): integer = macroexp(id: integer, slot: integer): integer
          return (id - slot) / 2^22
        end
      end
   ]], [[
      local record IdAllocator
          generationOfWithSlot: function(id: integer, slot: integer): integer
              = macroexp(id: integer, slot: integer): integer
                  return (id - slot) / 2 ^ 22
              end
      end
   ]]))
end)
