-- SPIKE. Formatting the code *inside* a macro quote instead of copying the token
-- through verbatim. Unmerged on purpose: this file is the evidence for whether the
-- feature is worth its cost.
--
-- Read it top to bottom. The three describes are the verdict:
--   "formats the quoted code"  cases the spike improves
--   "leaves the quote alone"   cases where nothing gets better, by design
--   "composes with what shipped"
--                              statement arguments landed on main after this
--                              branch was cut; these hold the two together
--
-- Run against the pinned dev Teal, otherwise every case reports pending.
local helpers = require("spec.cerulean.helpers")
local toolchain = require("spec.cerulean.toolchain")

local macro_it = toolchain.supports_macros() and it or pending

describe("SPIKE macro quotes: formats the quoted code", function()

   macro_it("reindents and respaces a statement quote", helpers.format([[
      local macro markDirty!(archExpr: Expression)
          return ```
        if $archExpr.dirty then
        $archExpr.queued=true
            end
          ```
      end
   ]], [[
      local macro markDirty!(archExpr: Expression)
          return ```
              if $archExpr.dirty then
                  $archExpr.queued = true
              end
          ```
      end
   ]]))

   macro_it("respaces an expression quote", helpers.format([[
      local macro f!(n: Expression)
          return `rshift($n+31,5)`
      end
   ]], [[
      local macro f!(n: Expression)
          return `rshift($n + 31, 5)`
      end
   ]]))

   -- This is the case that motivated the spike. Before it, the closing delimiter
   -- and the body kept their original columns while the call around them moved.
   macro_it("indents a quote nested in a wrapping call", helpers.format([[
      local macro f!(x: Expression)
          local out = emit(alpha_value, ```
              y = 1
          ```, beta_value, gamma_value, delta)
          return out
      end
   ]], [[
      local macro f!(x: Expression)
          local out = emit(
              alpha_value,
              ```
                  y = 1
              ```,
              beta_value,
              gamma_value,
              delta
          )
          return out
      end
   ]]))

   -- Teal's own expander hoists every splice to the front of the block; cerulean
   -- parses the line where it stands, so formatting cannot reorder the source.
   macro_it("keeps a splice line in its original position", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
        x=1
              $a
          y   =   2
          ```
      end
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              x = 1
              $a
              y = 2
          ```
      end
   ]]))

   -- Teal's import_types! example: macro vars in declaration and type positions.
   macro_it("formats macro vars in declaration and type positions", helpers.format([[
      local macro import_types!(v: Expression, m: Expression, b: Expression): Statement
          return ```
        local $v=require($m)
          local type $b=$v.$b
          ```
      end
   ]], [[
      local macro import_types!(v: Expression, m: Expression, b: Expression): Statement
          return ```
              local $v = require($m)
              local type $b = $v.$b
          ```
      end
   ]]))

   macro_it("formats an assignment through a macro var", helpers.format([[
      local macro f!(a: Expression)
          return ```
        $a.dirty=true
          ```
      end
   ]], [[
      local macro f!(a: Expression)
          return ```
              $a.dirty = true
          ```
      end
   ]]))

   macro_it("leaves an already-canonical quote untouched", helpers.check([[
      local macro markDirty!(archExpr: Expression)
          return ```
              if $archExpr.dirty then
                  $archExpr.queued = true
              end
          ```
      end
   ]]))

end)

describe("SPIKE macro quotes: leaves the quote alone", function()

   -- No comment inside a quote can ever be checked: the safety net counts comments
   -- in the outer file, and the whole quote is one token there. Rather than risk
   -- dropping one silently, a quote holding a comment is copied through as written.
   -- So no file that comments its macro bodies gets any benefit from this spike.
   macro_it("copies a quote containing a comment", helpers.check([[
      local macro f!(x: Expression)
          return ```
        -- keep me
           y=$x
          ```
      end
   ]]))

   macro_it("copies a quote whose contents do not parse", helpers.check([[
      local macro f!()
          return ```
        if then else
          ```
      end
   ]]))

   -- A long string inside a quote is left exactly where it was, so the result is
   -- half formatted and half not. Correct, and it looks like a mistake.
   macro_it("formats around a long string but cannot move it", helpers.format([[
      local macro f!()
          return ```
        local s=[==[
      line
      ]==]
          ```
      end
   ]], [[
      local macro f!()
          return ```
              local s = [==[
      line
      ]==]
          ```
      end
   ]]))

   -- Debatable. A deliberate one-liner becomes three lines because the layout
   -- rule is uniform. Matches how the rest of cerulean treats collections, but
   -- someone who wrote ```x = 1``` on purpose will not thank us.
   macro_it("expands a single-line quote to a block", helpers.format([[
      local macro bar!()
          return ```x = 1```
      end
   ]], [[
      local macro bar!()
          return ```
              x = 1
          ```
      end
   ]]))

end)

describe("SPIKE macro quotes: composes with what shipped", function()

   -- This was a pending case on the original spike branch: the committed macro
   -- support could not read a statement argument at all. Main fixed that, so the
   -- two now have to work in the same file.
   macro_it("formats a quote body and a statement argument together", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
        $a
          ```
      end

      wrap!(if c then y=1 end)
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      wrap!(
          if c then
              y = 1
          end
      )
   ]]))

   -- The quote body is re-lexed and re-parsed on its own, so it only reads an
   -- invocation's arguments correctly if it inherits the file's macro
   -- declarations. Parsing the quote from a fork of the enclosing state is what
   -- makes `wrap!` below resolve; a fresh parse leaves the whole quote verbatim.
   macro_it("reads a statement argument written inside a quote", helpers.format([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      local macro outer!()
          return ```
        wrap!(z=1)
          ```
      end
   ]], [[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      local macro outer!()
          return ```
              wrap!(z = 1)
          ```
      end
   ]]))

   macro_it("passes a macro var as a statement argument", helpers.check([[
      local macro wrap!(a: Statement)
          return ```
              $a
          ```
      end

      local macro outer!(b: Statement)
          return ```
              wrap!($b)
          ```
      end
   ]]))

end)
