local helpers = require("spec.formatter.helpers")

describe("formatter magic trailing comma", function()

    it("block formatter reindents a local decl containing a magic trailing comma table", helpers.format([[
        local function f()
          local x = {
            alpha,
            beta,
          }
        end
    ]], [[
        local function f()
            local x = {
                alpha,
                beta,
            }
        end
    ]]))

    it("block formatter keeps a single-item trailing comma table expanded", helpers.format([[
        local function f()
          local x = {
            alpha,
          }
        end
    ]], [[
        local function f()
            local x = {
                alpha,
            }
        end
    ]]))

    it("block formatter reindents a return with a magic trailing comma table", helpers.format([[
        local function f()
          return {
            alpha,
            beta,
          }
        end
    ]], [[
        local function f()
            return {
                alpha,
                beta,
            }
        end
    ]]))

    it("block formatter does not collapse a magic trailing comma table that fits on one line", helpers.check([[
        local function f()
            local x = {
                alpha,
            }
        end
    ]]))

end)
