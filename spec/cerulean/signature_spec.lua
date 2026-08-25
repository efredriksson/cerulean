local helpers = require("spec.cerulean.helpers")

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

   it("breaks the parameter list, not an empty function-type return annotation", helpers.format([[
      function str.split_find(s: string, del: string, no_patt: boolean): function(): integer, integer
      end
   ]],[[
      function str.split_find(
          s: string, del: string, no_patt: boolean
      ): function(): integer, integer
      end
   ]]))

   it("breaks the parameter list before a function-type return annotation with arguments", helpers.format([[
      function make_iterator(source_list: {string}, prefix: string): function(index: integer): string, boolean
      end
   ]],[[
      function make_iterator(
          source_list: {string}, prefix: string
      ): function(index: integer): string, boolean
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

   it("splits the parameters and keeps the return tuple on the closing line when both are too wide", helpers.format([[
      function f(first_parameter_with_long_name: ExtremelyVerboseTypeNameAlpha, second_parameter_with_long_name: ExtremelyVerboseTypeNameBeta): FirstVerboseReturnTypeName, SecondVerboseReturnTypeName, ThirdVerboseReturnTypeName
      end
   ]],[[
      function f(
          first_parameter_with_long_name: ExtremelyVerboseTypeNameAlpha,
          second_parameter_with_long_name: ExtremelyVerboseTypeNameBeta
      ): FirstVerboseReturnTypeName, SecondVerboseReturnTypeName, ThirdVerboseReturnTypeName
      end
   ]]))

   it("breaks the return tuple rather than overflow the closing line", helpers.format([[
      function f(alpha_parameter: ExtremelyVerboseTypeNameAlpha, beta_parameter: ExtremelyVerboseTypeNameBeta): FirstVerboseReturnTypeName, SecondVerboseReturnTypeName, ThirdVerboseReturnTypeName, FourthVerboseReturnTypeName
      end
   ]],[[
      function f(
          alpha_parameter: ExtremelyVerboseTypeNameAlpha,
          beta_parameter: ExtremelyVerboseTypeNameBeta
      ): FirstVerboseReturnTypeName,
          SecondVerboseReturnTypeName,
          ThirdVerboseReturnTypeName,
          FourthVerboseReturnTypeName
      end
   ]]))

   it("breaks a function type's return tuple when its closing line is too wide", helpers.format([[
      local record graphics
         make_thing: function(first_parameter_with_long_name: ExtremelyVerboseTypeNameAlpha, second_parameter_with_long_name: ExtremelyVerboseTypeNameBeta): FirstVerboseReturnTypeName, SecondVerboseReturnTypeName, ThirdVerboseReturnTypeName
      end
   ]],[[
      local record graphics
          make_thing: function(
              first_parameter_with_long_name: ExtremelyVerboseTypeNameAlpha,
              second_parameter_with_long_name: ExtremelyVerboseTypeNameBeta
          ): FirstVerboseReturnTypeName,
              SecondVerboseReturnTypeName,
              ThirdVerboseReturnTypeName
      end
   ]]))

   it("keeps an empty function-type parameter list flat and breaks its return tuple", helpers.format([[
      local f: function(): FirstVerboseReturnTypeName, SecondVerboseReturnTypeName, ThirdVerboseReturnTypeName, FourthVerboseReturnTypeName
   ]],[[
      local f: function(): FirstVerboseReturnTypeName,
          SecondVerboseReturnTypeName,
          ThirdVerboseReturnTypeName,
          FourthVerboseReturnTypeName
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

   it("wraps a long record function signature to compact form", helpers.format([[
      function SelectionRecordFactory.new(entity_identifier: integer, entry_descriptor: EntryDescriptor): SelectionRecordFactory
      end
   ]], [[
      function SelectionRecordFactory.new(
          entity_identifier: integer, entry_descriptor: EntryDescriptor
      ): SelectionRecordFactory
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
      local callback = function(param_one: TypeA, param_two: TypeB): ReturnType end
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

   it("wraps function type to multiple lines to fit it", helpers.format([[
      local record graphics
         draw: function(drawable: Drawable, quad: Quad, x: number, y: number, r?: number, sx?: number, sy?: number, ox?: number, oy?: number, kx?: number, ky?: number)
      end
   ]], [[
      local record graphics
          draw: function(
              drawable: Drawable,
              quad: Quad,
              x: number,
              y: number,
              r?: number,
              sx?: number,
              sy?: number,
              ox?: number,
              oy?: number,
              kx?: number,
              ky?: number
          )
      end
   ]]))

   it("wraps multiple function types without adding empty lines", helpers.format([[
      local record graphics
         draw: function(drawable: Drawable, quad: Quad, x: number, y: number, r?: number, sx?: number, sy?: number, ox?: number, oy?: number, kx?: number, ky?: number)
         draw_fast: function(drawable: Drawable, quad: Quad, x: number, y: number, r?: number, sx?: number, sy?: number, ox?: number, oy?: number, kx?: number, ky?: number)
      end
   ]], [[
      local record graphics
          draw: function(
              drawable: Drawable,
              quad: Quad,
              x: number,
              y: number,
              r?: number,
              sx?: number,
              sy?: number,
              ox?: number,
              oy?: number,
              kx?: number,
              ky?: number
          )
          draw_fast: function(
              drawable: Drawable,
              quad: Quad,
              x: number,
              y: number,
              r?: number,
              sx?: number,
              sy?: number,
              ox?: number,
              oy?: number,
              kx?: number,
              ky?: number
          )
      end
   ]]))

   -- Dropping an explicit `(): (value)` down to `: (value)` reparses with the
   -- value fused onto the key's own return type, changing which side of the
   -- map type gets to stay flat on the next pass.
   it("preserves an explicit empty return type on a map key's function type", helpers.format([[
      local x : { function < E > ( function ( ) | boolean | E . L ) : ( ) : ( function ( h : nil , Z : number ) : string ) }
   ]], [[
      local x: {function<E>(function() | boolean | E.L): (): (function(
          h: nil, Z: number
      ): string)}
   ]]))

   describe("generic function type annotations", function()

      it("normalises spacing around type parameters in a function type annotation", helpers.format([[
         local f: function < T > ( value : T ) : T
      ]], [[
         local f: function<T>(value: T): T
      ]]))

      it("renders multiple type parameters separated by commas", helpers.check([[
         local f: function<K, V>(key: K, value: V): boolean
      ]]))

      it("renders type parameters with constraints", helpers.check([[
         local f: function<K is Base, V>(key: K): V
      ]]))

      it("does not copy outer type parameters onto callback arguments", helpers.check([[
         local f: function<U>(transform: function(T): U): U
      ]]))

      it("renders generic function type definition", helpers.format([[
         local type B = function<i   >(): return_type
      ]], [[
         local type B = function<i>(): return_type
      ]]))

      it("normalises spacing in generic type parameters of an anonymous function expression", helpers.format([[
         local a = function<A,  B>(a: A, b: B): {string} end
      ]], [[
         local a = function<A, B>(a: A, b: B): {string} end
      ]]))

      it("comments in anonymous function blocks", helpers.format([[
         local a = function(a: A)
            -- Good to have
         end
      ]], [[
         local a = function(a: A)
             -- Good to have
         end
      ]]))

      it("do not add any if types are missing for function type", helpers.format([[
         local  a:  function
      ]], [[
         local a: function
      ]]))

      it("do not add space for optional type only argument in function type", helpers.format([[
         local  a:  function(  ?  string): string
      ]], [[
         local a: function(?string): string
      ]]))
   end)

   describe("table.Type<T> qualified generic type names", function()

      it("parses table.Foo<K> as a parameter type in a generic function", helpers.check([[
         function f<K>(x: table.Wrapper<K>): K
         end
      ]]))

      it("parses table.Foo<K> in a type alias inside a record", helpers.check([[
         local record M
             type Alias<K> = table.Wrapper<K>
         end
         return M
      ]]))

      it("parses table.Foo<K> in an is expression", helpers.check([[
         local function f<K>(x: any)
             if x is table.Wrapper<K> then
             end
         end
      ]]))

      it("parses table.Foo<T> as a return type", helpers.check([[
         local function f(...: string): table.Result<string>
         end
      ]]))

   end)

   describe("comments in parameter lists", function()

      it("preserves a same-line trailing comment after the last parameter", helpers.format([[
         function f(a -- note
         ) end
      ]], [[
         function f(
             a -- note
         )
         end
      ]]))

      it("preserves an own-line comment after a parameter", helpers.format([[
         function f(a
            -- note
         ) end
      ]], [[
         function f(
             a
             -- note
         )
         end
      ]]))

      it("keeps a comment on the opener line when a parameter follows", helpers.format([[
         function f( -- note
            a
         ) end
      ]], [[
         function f( -- note
             a
         )
         end
      ]]))

      it("keeps a comment on the opener line of an empty parameter list", helpers.check([[
         function f( -- note
         )
         end
      ]]))

      it("preserves a trailing comment after the last parameter of an anonymous function", helpers.format([[
         local f = function(a, b -- note
         ) end
      ]], [[
         local f = function(
             a,
             b -- note
         )
         end
      ]]))

      it("preserves an own-line comment before ) in a call argument list", helpers.format([[
         f(a
            -- note
         )
      ]], [[
         f(
             a
             -- note
         )
      ]]))

      -- Function types share the definition's parameter renderer, so a trailing
      -- comment on the last argument wraps the same way the definition above does.
      it("preserves a same-line trailing comment after the last function-type parameter", helpers.format([[
         local f: function(a: integer -- note
         )
      ]], [[
         local f: function(
             a: integer -- note
         )
      ]]))

      it("formats a function-type parameter list identically to a definition's", helpers.check([[
         local f: function(a: integer, b: string)
      ]]))

      -- A block comment after a parameter's type once duplicated (the list loop
      -- and the type both emitted the trailing slot); the type now renders
      -- leading-only, so it survives once -- definitions and function types alike.
      it("preserves a block comment after the last parameter's type", helpers.format([=[
         local function f(p: integer --[[t]])
         end
      ]=], [=[
         local function f(
             p: integer --[[t]]
         )
         end
      ]=]))

      -- A trailing comment after the comma, following another trailing
      -- comment on the parameter itself, used to over-indent on the first
      -- pass and only settle to the single stable indent on a second pass.
      it("indents a comment after a comma the same as one after a parameter", helpers.format([[
         local f: function(a: integer -- note
         , -- note
         b: integer)
      ]], [[
         local f: function(
             a: integer, -- note
             -- note
             b: integer
         )
      ]]))

   end)
end)
