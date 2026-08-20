# The Cerulean Code Style

> *"Sometimes the prize is not worth the costs. The means by which we achieve victory are as important as the victory itself."*
>
> — Brandon Sanderson, **The Way of Kings**

Cerulean enforces one style. There are no knobs for bracket placement, operator spacing, or line-breaking heuristics. The rules below describe exactly what that style is.

---

## Line length

The default target line length is **88 characters**. When a construct exceeds this width, Cerulean wraps it; when a wrapped construct fits on one line, Cerulean joins it back. Change the target with `--line-length` or `max_line_width` in `tlconfig.lua`.

---

## Supported Teal constructs

Cerulean understands all Teal constructs. Each construct is parsed structurally and laid out by the formatter, not passed through as text.

Leading, trailing, dangling, and inline-block comments are preserved through every wrapping decision. `-- fmt: off` / `-- fmt: on` regions are respected, and `require` sorting honours `-- fmt: off`.

What Cerulean leaves alone: long-string literals (`[[...]]`) and any region inside `-- fmt: off` are passed through verbatim.

---

## Three levels of wrapping

For tables, function calls, and function signatures, Cerulean tries three layouts in order and picks the first that fits within the line limit. If a wrapped construct fits a shorter layout, Cerulean joins it back.

**Level 1: single line.** Everything on one line:

```teal
local items = {Alpha = Alpha, Beta = Beta}
```

**Level 2: compact broken.** Opening delimiter stays on the first line, items share one inner line, closing delimiter on its own line:

```teal
local items = {
    Alpha = Alpha, Beta = Beta, Gamma = Gamma, Delta = Delta, Epsilon = Epsilon
}
```

**Level 3: one per line.** Each item on its own line, with a trailing comma added:

```teal
local items = {
    first_parameter_with_a_very_long_name = ExtremelyVerboseValueAlpha,
    second_parameter_with_a_very_long_name = ExtremelyVerboseValueBeta,
    third_parameter_with_a_very_long_name = ExtremelyVerboseValueGamma,
}
```

**Calls and signatures wrap the same way.** A long call goes through these three levels:

```teal
foo.new_number(
    "long_label_here",
    110,
    nbr_lightning_bombs_selected,
    settings.set_spawn_of_lightning_bombs
)
```

Long signatures wrap the same way. The return type stays attached to the closing parenthesis:

```teal
function f(
    param_one: LongTypeName, param_two: AnotherLongType, param_three: YetAnotherType
): ReturnValue
end
```

**Assignments wrap through the same levels**, using the `=` where a bracket would be. Level 2 puts the values below the `=`, level 3 gives one per line:

```teal
local x_min, y_min =
    math.ceil(hitbox.x / block_size), math.ceil(hitbox.y / block_size_y)

local x_max, y_max =
    math.ceil((hitbox.x + hitbox.width) / block_size),
    math.ceil((hitbox.y + hitbox.height) / block_size)
```

A `return` has no `=` to break at, so it skips level 2 and keeps its first value on the keyword line:

```teal
return archetype.columns[TransformComponent],
    archetype.columns[VelocityComponent],
    count
```

An assignment with a single value keeps the `=` on the line and wraps inside the value.

---

## `if`, `while`, and `until` header breaking

When a condition is too long to fit on one line, Cerulean breaks it around the keyword rather than wrapping the condition inline. The condition moves to an indented block between the keyword and `then` or `do`:

```teal
-- before
if input_device.is_pressed(unit.id, keymap.ACTIONS.R) and unit.handler_state_is_ready_to_apply == "ready" then
end

-- after
if
    input_device.is_pressed(unit.id, keymap.ACTIONS.R)
    and unit.handler_state_is_ready_to_apply == "ready"
then
end
```

`while`/`do` and `repeat`/`until` follow the same shape: keyword alone on the opening line, condition indented beneath, closing keyword (`do` or `until`) flush left.

---

## Binary operator breaking

Long expressions break at binary operators. The operator moves to the start of the continuation line:

```teal
-- before
table.insert(parts, indentation .. self.name .. ": " .. string.format("%.1f", self.elapsed * 1000) .. "ms")

-- after
table.insert(
    parts,
    indentation
        .. self.name
        .. ": "
        .. string.format("%.1f", self.elapsed * 1000)
        .. "ms"
)
```

---

## Type casts

A long `as` or `is` cast breaks before the operator, indenting the type under the expression:

```teal
-- before
local transforms = current_archetype.columns[builtins.TransformComponent] as {string: integer}

-- after
local transforms = current_archetype.columns[builtins.TransformComponent]
    as {string: integer}
```

Breaking there has to earn its place. When the type still does not fit the wrapped line, the operator stays put and the type gives instead:

```teal
local update = systems.registry[component_name] as function(
    entity: Entity, delta_time: number, world_state: WorldState, options: Options
): boolean
```

---

## String quote normalisation

Single-quoted strings are converted to double quotes. If the string already contains a literal double-quote character, the original quoting is preserved.

```teal
-- before
local greeting = 'hello'
local message  = 'say "hello"'

-- after
local greeting = "hello"
local message  = 'say "hello"'   -- unchanged: contains a double quote
```

Long-string literals (`[[...]]`) are never modified.

---

## Require sorting

Top-level `require` statements at the start of a file are sorted alphabetically by module path and consolidated into a single block with no blank lines between them. Requires that appear after any non-require statement are left alone.

```teal
-- before
local b = require("b")
local a = require("a")

local d = require("d")
local c = require("c")

-- after
local a = require("a")
local b = require("b")
local c = require("c")
local d = require("d")
```

Pass `--no-sort-requires` or set `sort_requires = false` in `tlconfig.lua` to opt out.

---

## Indentation and spacing

- Indentation is **4 spaces** by default (configurable via `--indent` / `indent_width`). Tabs are converted to the configured space width.
- Cerulean inserts exactly **one space** after commas, around binary operators, and around `=` in assignments and table constructors.
- Consecutive blank lines are collapsed to **at most one**.
- Trailing whitespace is removed from every line.

---

## Inline `if`/`else` expansion

Single-line `if`/`else` bodies are expanded to the standard multi-line block form:

```teal
-- before
if n < 10 then return prefix .. n else return tostring(n) end

-- after
if n < 10 then
    return prefix .. n
else
    return tostring(n)
end
```

---

## Teal type system

Cerulean normalises spacing throughout type annotations:

```teal
-- before
local f: function < T > ( value : T ) : T |   string

-- after
local f: function<T>(value: T): T | string
```

---

## Trailing commas

A trailing comma on the last item of a multi-line collection is a signal to Cerulean: **never collapse this to one line**, even if it would fit.

Without a trailing comma, a short table gets joined:

```teal
-- before
local t = {
    a = 1,
    b = 2
}

-- after
local t = {a = 1, b = 2}
```

Add a trailing comma and the table stays expanded no matter how short it is:

```teal
-- before (trailing comma present)
local t = {
    a = 1,
    b = 2,
}

-- after (unchanged)
local t = {
    a = 1,
    b = 2,
}
```

This lets you communicate "keep this expanded" without any comment directive.
