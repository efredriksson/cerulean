local tl = require("tl")

local toolchain = {}

-- Probing beats comparing tl.version(): the prerelease string moves on its own
-- and never says whether macro syntax landed or was reverted.
function toolchain.supports_macros()
    local probe = "local macro probe!(value: Expression)\nreturn `value`\nend\n"
    local _, lex_errors = tl.lex(probe, "toolchain_probe.tl")
    return #lex_errors == 0
end

return toolchain
