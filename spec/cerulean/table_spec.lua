local helpers = require("spec.cerulean.helpers")

describe("formatter table constructor wrapping", function()

   it("wraps a long single-line table constructor to compact form when the inner line fits", helpers.format([[
      local items = {Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon}
   ]], [[
      local items = {
          Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon
      }
   ]]))

   it("joins an already-wrapped table constructor that fits on one line", helpers.format([[
      local items = {
          Alpha = Alpha,
          Beta = Beta
      }
   ]],[[
      local items = {Alpha = Alpha, Beta = Beta}
   ]]))

   it("does not change a short table constructor already on one line", helpers.check(
      "local items = {Alpha = Alpha, Beta = Beta}"
   ))

   it("does not change an already-wrapped table constructor that does not fit on one line", helpers.check([[
      local items = {
          Alpha = Alpha,
          Beta = Beta,
          Gamma = Gamma,
          Delta = Delta,
          Epsilon = Epsilon,
      }
   ]]))

   it("preserves indentation when wrapping a table constructor", helpers.format([[
      local items = {Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon}
   ]],[[
      local items = {
          Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon
      }
   ]]))

   it("wraps a long table constructor to one element per line when the compact broken form is still too wide", helpers.format([[
      local items = {first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha, second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta, third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma}
   ]], [[
      local items = {
          first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha,
          second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta,
          third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma,
      }
   ]]))

   it("does format a table whose entries have inline comments", helpers.format([[
      local z = {
         BELOW = -3, -- on ground
         LEVEL = 0 -- ground level
      }
   ]], [[
      local z = {
          BELOW = -3, -- on ground
          LEVEL = 0, -- ground level
      }
   ]]))

   it("does not join a multi-line table whose last entry has a trailing comma", helpers.check([[
      local t = {
          a = 1,
          b = 2,
      }
   ]]))

   it("joins a multi-line table whose last entry has no trailing comma", helpers.format([[
      local t = {
         a = 1,
         b = 2
      }
   ]],[[
      local t = {a = 1, b = 2}
   ]]))

   it("does not collapse a wrapped table after joining its multi-line call entry", helpers.format([[
      local t = {
         key = foo(
            arg_one,
            arg_two
         ),
      }
   ]],[[
      local t = {
          key = foo(arg_one, arg_two),
      }
   ]]))

   it("preserves source spelling for typed and anonymous-function table entries", helpers.format([[
      local items = {callback: function(ctx: Scene): ResultType = function(ctx: Scene): ResultType return ctx.result end, value = ((left_value + right_value))}
   ]], [[
      local items = {
          callback: function(ctx: Scene): ResultType = function(ctx: Scene): ResultType
              return ctx.result
          end,
          value = ((left_value + right_value)),
      }
   ]]))

   it("does not change a wrapped table whose entries include inline comments", helpers.format([[
      local x = {
         alpha, -- keep alpha grouped here
         beta
      }
   ]], [[
      local x = {
          alpha, -- keep alpha grouped here
          beta,
      }
   ]]))

   it("does collapse a wrapped table given '--' string litera (not comment)", helpers.format([[
      local x = {"--",
         beta}
   ]], [[
      local x = {"--", beta}
   ]]))

   it("wraps a return table constructor that is too long", helpers.format([[
      return {alpha_value, beta_value, gamma_value, delta_value, epsilon_value, zeta_value, eta_value}
   ]],[[
      return {
          alpha_value,
          beta_value,
          gamma_value,
          delta_value,
          epsilon_value,
          zeta_value,
          eta_value,
      }
   ]]))

   it("joins a wrapped return table that fits on one line", helpers.format([[
      return {
         alpha_value,
         beta_value
      }
   ]],[[
      return {alpha_value, beta_value}
   ]]))

   it("joins a wrapped table whose value is a call expression", helpers.format([[
      local t = {
         key = foo(a, b)
      }
   ]],[[
      local t = {key = foo(a, b)}
   ]]))

   it("keeps assert call wrapped in table entry inside return doc.concat (anonymized regression)", helpers.format([[
      local function build_entry_text(entry, render_value)
          local label_text = entry.key.conststr or entry.key.tk
          return doc.concat(
              {
                  doc.text(label_text .. ": " .. assert(
                          entry.meta.value_text,
                          "missing value text for table field"
                      ) .. " = "),
                  render_value(entry.value),
              }
          )
      end
   ]], [[
      local function build_entry_text(entry, render_value)
          local label_text = entry.key.conststr or entry.key.tk
          return doc.concat(
              {
                  doc.text(
                      label_text
                          .. ": "
                          .. assert(
                              entry.meta.value_text, "missing value text for table field"
                          ) .. " = "
                  ),
                  render_value(entry.value),
              }
          )
      end
   ]]))

   it("wraps long typed table field text assembly in table item docs (anonymized regression)", helpers.format([[
      local function build_typed_field(item, render_value)
          local name_text = item.key.conststr or item.key.tk
          return doc.concat(
              {
                  doc.text(name_text .. ": " .. assert(item.itemtype.source_text, "missing item type source text") .. " = "),
                  render_value(item.value),
              }
          )
      end
   ]], [[
      local function build_typed_field(item, render_value)
          local name_text = item.key.conststr or item.key.tk
          return doc.concat(
              {
                  doc.text(
                      name_text
                          .. ": "
                          .. assert(
                              item.itemtype.source_text, "missing item type source text"
                          ) .. " = "
                  ),
                  render_value(item.value),
              }
          )
      end
   ]]))

   it("table key with long string preserves space to avoid tokenizer ambiguity", helpers.check([==[
      return {[ [=[]=] ] = nil}
   ]==]))

   it("table key with level-0 long string preserves space to avoid tokenizer ambiguity", helpers.check([=[
      local t = {[ [[key]] ] = nil}
   ]=]))

   it("table key with expression starting with long string preserves space to avoid tokenizer ambiguity", helpers.check([=[
      local t = {[ [[x]] + {} ] = 1}
   ]=]))

   it("uses semicolon separator after cast to function type to avoid trailing comma being parsed as return type", helpers.format([[
      return { a = x as function(): number; b = 1 }
   ]], [[
      return {a = x as function(): number; b = 1}
   ]]))

   it("uses semicolon after is-cast to function type with single return", helpers.format([[
      return { a = x is nil | function(): string; b = 1 }
   ]], [[
      return {a = x is nil | function(): string; b = 1}
   ]]))

   it("uses semicolon after cast to function type with multiple returns without adding parens", helpers.format([[
      return { a = x as function(): number, string; b = 1 }
   ]], [[
      return {a = x as function(): number, string; b = 1}
   ]]))

   it("uses semicolon on trailing separator when wrapped multi-return cast is last item", helpers.format([[
      return {
         -- force wrap
         a = 1,
         b = x as function(): number, string
      }
   ]], [[
      return {
          -- force wrap
          a = 1,
          b = x as function(): number, string;
      }
   ]]))

   it("uses comma when cast function type has no return types", helpers.format([[
      return { a = x as function(); b = 1 }
   ]], [[
      return {a = x as function(), b = 1}
   ]]))

   it("uses comma when cast function type return is parenthesized", helpers.check([[
      return {a = x as (function(): number), b = 1}
   ]]))

   it("uses comma when cast function type has parenthesized return tuple", helpers.check([[
      return {a = x as function(): (number), b = 1}
   ]]))

   it("uses semicolon after cast to generic function type with single return", helpers.format([[
      return { a = x as function<T>(): T; b = 1 }
   ]], [[
      return {a = x as function<T>(): T; b = 1}
   ]]))

   it("uses semicolon when cast is nested as right operand of binary op", helpers.format([[
      return { a = false .. n is function(): number; b = 1 }
   ]], [[
      return {a = false .. n is function(): number; b = 1}
   ]]))

   it("uses comma when cast under unary prefix gets parenthesized by renderer", helpers.format([[
      return { a = not n is function(): number; b = 1 }
   ]], [[
      return {a = not (n is function(): number), b = 1}
   ]], {skip_ast_equivalence = true}))

   it("uses comma when binary op parenthesizes a unary as-cast right operand", helpers.format([[
      for CM in {a_long_name_here_xxxx, b_some_long_name ^ ~c_long_expr_name as function(): string...} do end
   ]], [[
      for CM in {
          a_long_name_here_xxxx,
          b_some_long_name ^ (~c_long_expr_name as function(): string...),
      } do
      end
   ]], {skip_ast_equivalence = true}))

   it("uses semicolon when as-cast under unary prefix is not parenthesized", helpers.format([[
      return { a = not x as function(): number; b = 1 }
   ]], [[
      return {a = not x as function(): number; b = 1}
   ]]))

   it("uses semicolon on trailing separator when wrapped unary as-cast is last item", helpers.format([[
      return {
         -- force wrap
         a = 1,
         b = not x as function(): number
      }
   ]], [[
      return {
          -- force wrap
          a = 1,
          b = not x as function(): number;
      }
   ]]))

   it("uses semicolon on trailing separator when wrapped cast is last item", helpers.format([[
      return {
         -- force wrap
         a = 1,
         b = x as function(): number
      }
   ]], [[
      return {
          -- force wrap
          a = 1,
          b = x as function(): number;
      }
   ]]))


   it("trailing semicolon on is-cast to vararg function type stays multiline", helpers.format([[
      local n, KA = { o is function ( ) : string ... , } , x
   ]], [[
      local n, KA =
          {
              o is function(): string...;
          },
          x
   ]]))

   it("does not add blank line after multiline string entry followed by another entry", helpers.check([=[local x = {
    "
",
    1,
}
]=]))

   it("wraps a table when a line comment sits between a value and its separator", helpers.format([[
      return {1 -- x
      ;2}
   ]], [[
      return {
          1, -- x
          2,
      }
   ]]))

   it("promotes own-line line comment before separator to leading on next item", helpers.format([[
      return {1
      -- x
      ,2}
   ]], [[
      return {
          1,
          -- x
          2,
      }
   ]]))

   it("relocates a block comment between value and separator to statement leading", helpers.format([=[
      return {1 --[[b]], 2}
   ]=], [=[
      --[[b]]
      return {1, 2}
   ]=]))

end)
