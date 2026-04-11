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

   it("does not wrap a short assert call with a string message", helpers.check([[
         local ok = assert(#sel < #all, "too many")
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

   it("preserves variadic arguments for anonymous function", helpers.format([[
      local result = function(ctx: A, ...:  boolean) end
   ]], [[
      local result = function(ctx: A, ...: boolean) end
   ]]))

   it("formats anonymous function arguments with a local declaration body", helpers.format([[
      local result = process.deep_call(function() local current_value: ResultType = compute_result() end, trailing_argument_with_a_very_long_name)
   ]], [[
      local result = process.deep_call(
          function() local current_value: ResultType = compute_result() end,
          trailing_argument_with_a_very_long_name
      )
   ]]))

   it("formats anonymous function arguments with an assignment body", helpers.format([[
      local result = process.deep_call(function() current_value = compute_result() end, trailing_argument_with_a_very_long_name)
   ]], [[
      local result = process.deep_call(
          function() current_value = compute_result() end,
          trailing_argument_with_a_very_long_name
      )
   ]]))

   it("formats an empty anonymous function to multi-line", helpers.format([[
      local on_load = maybe_handler or function()   end
   ]], [[
      local on_load = maybe_handler or function() end
   ]]))

   it("wraps a long single-statement anonymous function argument instead of keeping an overlong one-liner", helpers.format([[
      table.sort(render_rows_collection, function(a: RenderableListEntry, b: RenderableListEntry): boolean return a.vertical_offset_position < b.vertical_offset_position end)
   ]], [[
      table.sort(
          render_rows_collection,
          function(a: RenderableListEntry, b: RenderableListEntry): boolean
              return a.vertical_offset_position < b.vertical_offset_position
          end
      )
   ]]))

   it("keeps the right call compact when it still fits after a wrapped left call", helpers.format([[
      return interval_overlap(
          self.x,
          self.x + self.width,
          other.x,
          other.x + other.width
      ) and
          interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
   ]], [[
      return interval_overlap(self.x, self.x + self.width, other.x, other.x + other.width)
          and interval_overlap(self.y, self.y + self.height, other.y, other.y + other.height)
   ]]))

   it("joins a wrapped call containing nested call and table arguments when they are already compact", helpers.format([[
      local x = f(g(1, 2),
         {alpha = 1, beta = 2})
   ]],[[
      local x = f(g(1, 2), {alpha = 1, beta = 2})
   ]]))

   it("reindents a wrapped call whose arguments include inline comments", helpers.format([[
      local x = f(
         alpha, -- keep alpha grouped here
         beta
      )
   ]], [[
      local x = f(
          alpha, -- keep alpha grouped here
          beta
      )
   ]]))

   it("collapses an assignment call with a short inline comment on its closing line", helpers.format([[
      local function f()
         result = math.min(
            result,
            factor * 2
         ) -- clamp result
         other_call()
      end
   ]], [[
      local function f()
          result = math.min(result, factor * 2) -- clamp result
          other_call()
      end
   ]]))

   it("does not change an assignment call with a long trailing inline comment on its closing line", helpers.format([[
      local function f()
         result = math.min(
            result,
            factor * 2
         ) -- clamp result with a very long and elaborate description on what it does
         other_call()
      end
   ]], [[
      local function f()
          result = math.min(
              result, factor * 2
          ) -- clamp result with a very long and elaborate description on what it does
          other_call()
      end
   ]]))

   it("do collapse a wrapped call still when a string literal contains comment text", helpers.format([[
      local x = f("--",
         beta)
   ]], [[
      local x = f("--", beta)
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

   it("breaks a long and-condition at the boolean operator", helpers.format([[
      if input_device.is_pressed(unit.id, keymap.ACTIONS.R) and unit.handler_state_is_ready_to_apply == "ready" then
      end
   ]], [[
      if input_device.is_pressed(unit.id, keymap.ACTIONS.R)
          and unit.handler_state_is_ready_to_apply == "ready" then
      end
   ]]))

   it("breaks when a long right-side and-condition call would overflow", helpers.format([[
      if unit.handler_state_is_ready_to_apply == "ready" and inputdeviceinput.is_pressed(unit.id, keymap.ACTIONS.R) then
      end
   ]], [[
      if unit.handler_state_is_ready_to_apply == "ready"
          and inputdeviceinput.is_pressed(unit.id, keymap.ACTIONS.R) then
      end
   ]]))

   it("breaks parenthesized boolean conditions at operators when the if head is too long", helpers.format([[
      if (input_events.was_released(actor.id, keymap.ACTIONS.B) and actor:can_update()) or actor:must_update() then
      end
   ]], [[
      if (input_events.was_released(actor.id, keymap.ACTIONS.B) and actor:can_update())
          or actor:must_update() then
      end
   ]]))

   it("breaks an overlong if condition inside a function body at the boolean operator", helpers.format([[
      local function f()
          if input_device.is_pressed(unit.id, keymap.ACTIONS.R) and unit.processing_state_identifier == "ready_to_apply" then
          end
      end
   ]], [[
      local function f()
          if input_device.is_pressed(unit.id, keymap.ACTIONS.R)
              and unit.processing_state_identifier == "ready_to_apply" then
          end
      end
   ]]))

   it("wraps a leading call in a long return expression while preserving arithmetic semantics", helpers.format([[
      function layout.snap_to_x(x: number): number
        return math.floor((x - ACTIVE_ZONE.x) / layout.STEP_SIZE + 0.5) * layout.STEP_SIZE + ACTIVE_ZONE.x
      end
   ]], [[
      function layout.snap_to_x(x: number): number
          return math.floor(
              (x - ACTIVE_ZONE.x) / layout.STEP_SIZE + 0.5
          ) * layout.STEP_SIZE + ACTIVE_ZONE.x
      end
   ]]))

   it("wraps both long calls in a boolean return expression to stay within width", helpers.format([[
      function Rectangle:overlap(other: Rectangle): boolean
         return interval_overlap(self.x, self.x + self.width, other.x, other.x + other.width) and interval_overlap(
            self.y, self.y + self.height, other.y, other.y + other.height
         )
      end
   ]], [[
      function Rectangle:overlap(other: Rectangle): boolean
          return interval_overlap(self.x, self.x + self.width, other.x, other.x + other.width)
              and interval_overlap(
              self.y, self.y + self.height, other.y, other.y + other.height
          )
      end
   ]]))

   it("keeps unary-not calls compact when breaking at the operator is enough", helpers.format([[
      if test1() then
         if test2() then
            if test3() then
               if not layout.area():contains(item:get_box()) and not item.target:get_slot() then
               end
            end
         end
      end
   ]], [[
      if test1() then
          if test2() then
              if test3() then
                  if not layout.area():contains(item:get_box())
                      and not item.target:get_slot() then
                  end
              end
          end
      end
   ]]))

   it("keeps return boolean chains readable when both call terms wrap", helpers.format([[
      function Rectangle:is_contained_by(other: Rectangle): boolean
         return interval_contained(
            other.x, other.x + other.width, self.x, self.x + self.width
         ) and interval_contained(
            other.y, other.y + other.height, self.y, self.y + self.height
         )
      end
   ]], [[
      function Rectangle:is_contained_by(other: Rectangle): boolean
          return interval_contained(
              other.x, other.x + other.width, self.x, self.x + self.width
          ) and interval_contained(
              other.y, other.y + other.height, self.y, self.y + self.height
          )
      end
   ]]))

   it("keeps a short left call compact and wraps the overflowing unary-not call in nested boolean conditions", helpers.format([[
      if test1() then
         if test2() then
            if test3() then
               if new_bounds_box:overlap(near_block) and not bounds_box:overlap(near_block) then
                   return near_block
               end
            end
         end
      end
   ]], [[
      if test1() then
          if test2() then
              if test3() then
                  if new_bounds_box:overlap(near_block)
                      and not bounds_box:overlap(near_block) then
                      return near_block
                  end
              end
          end
      end
   ]]))

   it("wrap long function signatures with single argument", helpers.format([[
      function my_module.selection_of_stuff_long_name(on_by_default: boolean): StuffSelection<boolean>
      end
   ]], [[
      function my_module.selection_of_stuff_long_name(
          on_by_default: boolean
      ): StuffSelection<boolean>
      end
   ]]))

   it("generics types in functions", helpers.format([[
      function f<T>(var: T): that
         local x: {boolean:  T} = {[true] = var}
         return x[true]
      end
   ]], [[
      function f<T>(var: T): that
          local x: {boolean: T} = {[true] = var}
          return x[true]
      end
   ]]))

   it("union types in variables", helpers.format([[
      local x: string |  number = 5
   ]], [[
      local x: string | number = 5
   ]]))

   it("table tuple types for variables", helpers.format([[
      local type Color = {number , number,  number}
   ]], [[
      local type Color = {number, number, number}
   ]]))
   
end)
