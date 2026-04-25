# Formatting Directives

Wrap regions you want left untouched in formatter directives:

```teal
-- fmt: off
local hand_formatted = {1,    2,   3,
                        100,  200, 300}
-- fmt: on
```

Everything between `-- fmt: off` and `-- fmt: on` is passed through verbatim. The directives themselves are preserved in the output.

## Scoped usage

The directives respect the structure of the code — you can place them inside a function or any other block to leave just that block unformatted while the rest of the file is formatted normally:

```teal
local function formatted()
    return 1 + 2
end

local function hand_crafted()
    -- fmt: off
    local matrix = {
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
    }
    return matrix
end

local function also_formatted()
    return 3 + 4
end
```
