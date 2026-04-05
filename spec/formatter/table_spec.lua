local helpers = require("spec.formatter.helpers")

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
          callback: function(ctx: Scene): ResultType = function(ctx: Scene): ResultType return ctx.result end,
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

end)
