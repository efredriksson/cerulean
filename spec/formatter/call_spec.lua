local helpers = require("spec.formatter.helpers")

describe("formatter function call wrapping", function()

   it("wraps a long function call to compact form", helpers.format([[
      local x = foo.new_selection(some_settings.long_field_name, minimum_value_long, maximum_value_long)
   ]], [[
      local x = foo.new_selection(
          some_settings.long_field_name, minimum_value_long, maximum_value_long
      )
   ]]))

   it("joins an already-wrapped call that fits on one line", helpers.format([[
         local x = foo.new_selection(
             field_a,
             field_b
         )
      ]], [[
         local x = foo.new_selection(field_a, field_b)
      ]]
   ))

   it("does not change a short call", helpers.check([[
         local x = foo.new_selection(field_a, field_b)
   ]]))

   it("re-wraps an already-wrapped call whose args line is too long", helpers.format([[
      foo.new_number(
         "long_label_here", 110, nbr_lightning_bombs_selected, settings.set_spawn_of_lightning_bombs
      )
   ]],[[
      foo.new_number(
          "long_label_here",
          110,
          nbr_lightning_bombs_selected,
          settings.set_spawn_of_lightning_bombs
      )
   ]]))

   it("wrap the inner function and do not touch outer function", helpers.format([[
      table.insert(
          parts,
          indentation .. self.name .. ": " .. string.format("%.1f", self.elapsed * 1000) .. "ms"
      )
   ]], [[
      table.insert(
          parts,
          indentation .. self.name .. ": " .. string.format(
              "%.1f", self.elapsed * 1000
          ) .. "ms"
      )
   ]]))

   it("wrap the second inner function as it is the one to reduce line lenght", helpers.format([[
      table.insert(
          self.trophy_positions,
          points.new(get_x_pos(i, #names) - self.trophy.width / 2, (screen.HEIGHT - self.trophy.height) / 2)
      )
   ]], [[
      table.insert(
          self.trophy_positions,
          points.new(
              get_x_pos(i, #names) - self.trophy.width / 2,
              (screen.HEIGHT - self.trophy.height) / 2
          )
      )
   ]]))

   it("wraps a call with trailing content to compact broken form when it fits", helpers.format([[
      local formatted = string.format("%.1f", elapsed_milliseconds_long_value, maximum_precision) .. "ms"
   ]], [[
      local formatted = string.format(
          "%.1f", elapsed_milliseconds_long_value, maximum_precision
      ) .. "ms"
   ]]))

   it("preserves source spelling for parenthesized and complex call arguments", helpers.format([[
      local result = process.deep_call(((left_value + right_value)), function(ctx: Scene, enabled: boolean): ResultType return ctx.result end, trailing_argument_with_a_very_long_name)
   ]], [[
      local result = process.deep_call(
          ((left_value + right_value)),
          function(ctx: Scene, enabled: boolean): ResultType return ctx.result end,
          trailing_argument_with_a_very_long_name
      )
   ]]))

   it("preserves anonymous function arguments with a local declaration body", helpers.format([[
      local result = process.deep_call(function() local current_value: ResultType = compute_result() end, trailing_argument_with_a_very_long_name)
   ]], [[
      local result = process.deep_call(
          function() local current_value: ResultType = compute_result() end,
          trailing_argument_with_a_very_long_name
      )
   ]]))

   it("preserves anonymous function arguments with an assignment body", helpers.format([[
      local result = process.deep_call(function() current_value = compute_result() end, trailing_argument_with_a_very_long_name)
   ]], [[
      local result = process.deep_call(
          function() current_value = compute_result() end,
          trailing_argument_with_a_very_long_name
      )
   ]]))

   it("does not collapse an expanded call whose closing paren has trailing content", helpers.check([[
      return interval_overlap(
          self.x,
          self.x + self.width,
          other.x,
          other.x + other.width
      ) and
          interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
   ]]))

   it("joins a wrapped call containing nested call and table arguments when they are already compact", helpers.format([[
      local x = f(g(1, 2),
         {alpha = 1, beta = 2})
   ]],[[
      local x = f(g(1, 2), {alpha = 1, beta = 2})
   ]]))

   it("does not change a wrapped call whose arguments include inline comments", helpers.check([[
      local x = f(
         alpha, -- keep alpha grouped here
         beta
      )
   ]]))

   it("does not collapse a wrapped call when a string literal contains comment text", helpers.check([[
      local x = f("--",
         beta)
   ]]))

   it("wraps a long call whose argument is a string containing a closing paren", helpers.format([[
      local x = my_func("closing)paren", argument_two_long, argument_three_long, argument_four_and_five_long_long)
   ]],[[
      local x = my_func(
          "closing)paren",
          argument_two_long,
          argument_three_long,
          argument_four_and_five_long_long
      )
   ]]))

   it("collapses a call where arguments fit on their own line", helpers.format([[
      local x = my_func("closing)paren", argument_two, argument_three, argument_four_and_five_long)
   ]],[[
      local x = my_func(
          "closing)paren", argument_two, argument_three, argument_four_and_five_long
      )
   ]]))

   it("correctly joins a call inside a function whose signature was compacted", helpers.format([[
      function some_module.new(
          menu_choices: {string},
          go_back: function(),
          on_load: function()
      ): string
          baz(
              arg1,
              arg2
          )
      end
   ]],[[
      function some_module.new(
          menu_choices: {string}, go_back: function(), on_load: function()
      ): string
          baz(arg1, arg2)
      end
   ]]))

   it("does not wrap a short multi-arg call used as an if condition", helpers.check([[
      local function f()
          if check({a, b}, x) then
              y = 1
          end
      end
   ]]))

   it("does not wrap a short multi-arg call with table arg used as an if condition in a for loop", helpers.check([[
      local function f()
          for from_color, to_color in pairs(color_mapping) do
              if color_equal({r, g, b}, from_color) then
                  x = y
              end
          end
      end
   ]]))

end)
