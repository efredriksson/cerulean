# Claude Code conventions for this repository

## Workflow

After making changes, run `make lint` to verify the Teal code is correct.

After `make lint` passes, go through each changed function and check it explicitly against every convention listed below. Only mark the task complete after this checklist pass.

## Teal style

**Functions must always return their declared type.**
Never use `local result: T` followed by conditional assignment. Extract a local function that returns `T` instead. This ensures the type is never in an uninitialized state.

```teal
-- Bad
local result: CheckedMovement
if condition then
    result = ...
else
    result = ...
end
return result

-- Good
local function compute(): CheckedMovement
    if condition then
        return ...
    else
        return ...
    end
end
return compute()
```

**Geometry operations belong as methods on the type, not computed inline.**
If you find yourself writing `vectors.new(b.x - a.x, b.y - a.y)` to express a displacement between two points, that should be a method like `a:vector_to(b)`.

**Construct groups complete at their declaration.**
Do not create a group and then append to it with `table.insert` afterwards. If a group needs more members, pass them all to the constructor.

```teal
-- Bad
local group = collision.new_group(soft_blocks, pressure_blocks)
for _, b in ipairs(hard_blocks) do table.insert(group, b) end

-- Good
local group = collision.new_group(soft_blocks, pressure_blocks, hard_blocks)
```

**Private methods use a leading underscore.**
Methods intended only for internal use are prefixed with `_`, e.g. `Bomb:_trigger_belt()`, `Battle:_handle_stun_cry()`.

**Use reverse iteration when removing elements in-place.**
Never remove elements during a forward `ipairs` loop. Always iterate backwards:

```teal
for i = #list, 1, -1 do
    if list[i]:is_complete() then
        table.remove(list, i)
    end
end
```

**Shared resources belong on the container, not the entity.**
If all entities of a type share a resource (e.g. an animation), hold it once on the container record and pass the reference into each entity at construction. Avoid duplicating heavy objects per instance.

**Use named local functions for predicates, not inline logic.**
Before passing a predicate to `itertools`, define it as a named local function just above the call site. This keeps the `filter`/`map`/`combine` call readable.

```teal
local function not_this_bomb(b: Kinematic): boolean
    return b ~= self
end
local nearby = itertools.filter(close_bombs, not_this_bomb)
```

**Prefer `itertools` over manual loops for filtering and transforming collections.**
Use `itertools.filter`, `itertools.map`, and `itertools.combine` instead of writing accumulator loops by hand.

**Place logic where the responsibility naturally belongs, not where it is convenient.**
Before adding code to a function, ask which function *owns* the concern being addressed. A function that collects data should not also randomise it; a function that assigns items should own the randomness that makes assignment fair.

**Do not introduce abbreviations or single-letter names that do not already exist in the codebase.**
Use full, descriptive names for variables, functions, and parameters. Only use short names if that convention already exists in the repo.

**Use named local functions for sort comparators, not inline functions.**
Before passing a comparator to `table.sort`, define it as a named local function just above the call site, the same as for `itertools` predicates.

```teal
local function distance_to_corner(first: QuadrantCell, second: QuadrantCell): boolean
    if first.distance ~= second.distance then return first.distance < second.distance end
    return first.i < second.i
end
table.sort(cells, distance_to_corner)
```

**Every new `record` type must have a `.new()` constructor.**
Do not construct records ad-hoc by setting fields inline at the call site. Define a `RecordName.new(...)` function that initialises all fields and returns the fully constructed value. Always use `setmetatable({}, { __index = RecordName })` as the base, even for records with no methods, to keep construction consistent.

**Avoid the ternary idiom for non-trivial conditions.**
`x and a or b` is acceptable only for genuinely simple one-liners. For anything with logic or multiple parts, use `if/elseif/end`.

**Prefer structure over comments.**
Before writing a comment, ask whether the same clarity can be achieved by extracting a well-named function, choosing a more descriptive variable name, or modelling the code after what it actually represents. A name like `split_preserving_trailing_newline` communicates intent without a comment; a type named `Rewrite` tells you more than `FormatResult` ever could. Comments are a last resort, not a first instinct.

**When a comment is necessary, explain why — concretely.**
The code already says what is happening. A comment should explain why this logic exists and give the concrete scenario it handles. Avoid abstract labels; be explicit over implicit.

**Never use `as` casts or `any` to work around type errors.**
Do not cast with `as` or widen to `any` to make the type checker accept code. The only exception is repeating a cast pattern that already exists in the codebase for the same reason. Any new use requires explicit permission from the user — and it should be assumed permission will not be granted unless the circumstances are extraordinary.
