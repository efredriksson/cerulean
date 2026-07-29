require("tl").loader()

local assert = require("luassert")
local options = require("cerulean.options")
local rewriter = require("cerulean.rewriter")
local tl = require("tl")

local function compile_teal(source, filename)
   local has_teal, teal = pcall(require, "teal")
   if has_teal and teal.compiler then
      local compiler = teal.compiler({gen_target = "5.1"})
      local input, input_error = compiler:input(source, filename)
      assert.is_nil(input_error)
      local lua_source, _, errors = input:gen()
      assert.same({}, errors.syntax_errors)
      assert.same({}, errors.type_errors)
      return lua_source
   end

   local result = tl.process_string(source, false, nil, filename)
   assert.same({}, result.syntax_errors)
   assert.same({}, result.type_errors)
   return tl.pretty_print_ast(result.ast, "5.1")
end

local function command_succeeded(ok, exit_kind, exit_code)
   if ok == true then
      return true
   end
   return ok == 0 or (exit_kind == "exit" and exit_code == 0)
end

local function bytecode_listing(lua_source)
   local base = os.tmpname()
   local source_path = base .. ".lua"
   local bytecode_path = base .. ".luac"

   local source_file = assert(io.open(source_path, "w"))
   source_file:write(lua_source)
   source_file:close()

   local ok, exit_kind, exit_code = os.execute(
      string.format("luac -s -o %q %q", bytecode_path, source_path)
   )
   assert.is_true(command_succeeded(ok, exit_kind, exit_code))

   local pipe = assert(io.popen(
      string.format("luac -l -l -p %q", bytecode_path), "r"
   ))
   local listing = pipe:read("*a")
   pipe:close()

   os.remove(base)
   os.remove(source_path)
   os.remove(bytecode_path)

   local normalized = listing
      :gsub("0x%x+", "ADDR")
      :gsub("<%?:%d+,%d+>", "<LINES>")
   return normalized
end

describe("semantic equivalence", function()

   it("preserves Teal types and generated Lua bytecode", function()
      local source = [[
local record Box<T>
 value:T
 map:function<U>(self:Box<T>, transform:function(T):U):U
end
function Box:map<U>( transform : function(T): U ): U
 return transform(self.value)
end
return Box
]]

      local opts = options.default()
      opts.sort_requires = false
      local rewrite = rewriter.rewrite(source, "box.tl", opts)

      assert.same({}, rewrite.parse_errors)
      assert.same("reformatted", rewrite.status)

      local before_lua = compile_teal(source, "before.tl")
      local after_lua = compile_teal(rewrite.output, "after.tl")
      assert.same(bytecode_listing(before_lua), bytecode_listing(after_lua))
   end)

end)
