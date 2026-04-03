local helpers = require("spec.formatter.helpers")

describe("formatter signature wrapping", function()

   it("wraps a long single-line signature to compact form", helpers.format([[
      function f(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType): ReturnValue
      end
   ]],[[
      function f(
          param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType
      ): ReturnValue
      end
   ]]))

   it("joins an already-wrapped signature that fits on one line", helpers.format([[
      function f(
         param_one: TypeA,
         param_two: TypeB
      ): ReturnType
      end
   ]],[[
      function f(param_one: TypeA, param_two: TypeB): ReturnType
      end
   ]]))

   it("does not change a short signature that is already on one line", helpers.check([[
      function f(x: integer, y: integer): integer
      end
   ]]))

   it("preserves indentation when wrapping a method signature", helpers.format([[
      function Obj:method(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType)
      end
   ]],[[
      function Obj:method(
          param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType
      )
      end
   ]]))

   it("splits a signature one parameter per line when the compact broken form is still too wide", helpers.format([[
      function f(first_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameAlpha, second_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameBeta, third_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameGamma): ReturnType
      end
   ]],[[
      function f(
          first_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameAlpha,
          second_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameBeta,
          third_parameter_with_a_very_long_name: ExtremelyVerboseTypeNameGamma
      ): ReturnType
      end
   ]]))

   it("preserves optional and vararg parameters when wrapping a signature", helpers.format([[
      function f(required: RequiredType, optional_param?: OptionalTypeName, ...: VariadicTypeName): ReturnType
      end
   ]],[[
      function f(
          required: RequiredType, optional_param?: OptionalTypeName, ...: VariadicTypeName
      ): ReturnType
      end
   ]]))

   it("preserves source spelling for parenthesized and function parameter types", helpers.format([[
      function f(left: (Alpha | Beta), callback: function(ctx: Scene, enabled: boolean): ResultType, right: ExtremelyVerboseTypeName)
      end
   ]],[[
      function f(
          left: (Alpha | Beta),
          callback: function(ctx: Scene, enabled: boolean): ResultType,
          right: ExtremelyVerboseTypeName
      )
      end
   ]]))

   it("wraps a long anonymous function signature", helpers.format([[
      local callback = function(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType): ReturnValue
      end
   ]],[[
      local callback = function(
          param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType
      ): ReturnValue
      end
   ]]))

   it("joins a wrapped anonymous function signature that fits on one line", helpers.format([[
      local callback = function(
         param_one: TypeA,
         param_two: TypeB
      ): ReturnType
      end
   ]],[[
      local callback = function(param_one: TypeA, param_two: TypeB): ReturnType
      end
   ]]))

   it("does not treat a commented-out function line as a signature", helpers.check([[
      -- local function foo(param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherLongType)
   ]]))

   it("collapses a wrapped signature to a single args line when it fits", helpers.format([[
      local function interval_overlap(
          xmin1: number,
          xmax1: number,
          xmin2: number,
          xmax2: number
      ): boolean
      end
   ]], [[
      local function interval_overlap(
          xmin1: number, xmax1: number, xmin2: number, xmax2: number
      ): boolean
      end
   ]]))

end)
