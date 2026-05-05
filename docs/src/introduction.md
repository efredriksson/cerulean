# Introduction

> *"The shore gives way to the sea.*
> *And the sea, my friends,*
> *Does not dream of you."*
>
> — Steven Erikson, **Reaper's Gale**

Cerulean is an opinionated code formatter for the [Teal](https://teal-language.org/) programming language.

It enforces a consistent style automatically, so you can stop arguing about formatting and focus on the code. Pass a file or directory to `ceru` and it rewrites your sources in place.

## A first example

Before formatting:

```teal
local renderer=require('renderer')
local entities=require("entities")
local physics  =  require("physics")

local function update(  world :World,dt:number ) :boolean
  for _,e in ipairs(world.entities) do
    if e.active==true and e.physics~=nil then physics.step(e,dt) end
  end
  if world.frame_count>MAX_FRAMES then return false
  else return true end
end
```

After formatting:

```teal
local entities = require("entities")
local physics = require("physics")
local renderer = require("renderer")

local function update(world: World, dt: number): boolean
    for _, e in ipairs(world.entities) do
        if e.active == true and e.physics ~= nil then
            physics.step(e, dt)
        end
    end
    if world.frame_count > MAX_FRAMES then
        return false
    else
        return true
    end
end
```

In CI, run with `--check` to reject unformatted code.

Cerulean works with Lua 5.1 and above, including LuaJIT.
