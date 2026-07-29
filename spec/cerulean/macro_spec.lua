local helpers = require("spec.cerulean.helpers")
local tl = require("tl")

local _, macro_lex_errors = tl.lex(
   "local macro identity!(value: Expression)\n"
      .. "return `value`\n"
      .. "end\n",
   "macro_support.tl"
)
local macro_it = #macro_lex_errors == 0 and it or pending

describe("local macros", function()

   macro_it("formats macro declarations and invocations", helpers.format([[
      local macro bitsToWords!( nExpr : Expression )
         return `rshift($nExpr + 31, 5)`
      end

      local words=bitsToWords!( capacity )
   ]], [[
      local macro bitsToWords!(nExpr: Expression)
          return `rshift($nExpr + 31, 5)`
      end

      local words = bitsToWords!(capacity)
   ]]))

   macro_it("preserves statement macro quotes", helpers.check([[
      local macro markDirty!(archExpr: Expression)
          return ```
              if $archExpr.dirty then
                  $archExpr.queued = true
              end
          ```
      end

      markDirty!(archetype)
   ]]))

end)
