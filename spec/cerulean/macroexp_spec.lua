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
end)
