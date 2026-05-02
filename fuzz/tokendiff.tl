#!/usr/bin/env -S tl run

local lexer = require("teal.lexer")

local type TokenEntry = record
   kind: string
   text: string
end

local type DiffOp = record
   op: string
   entry: TokenEntry
end

local function tokenize(content: string, filename: string): {TokenEntry}
   local tokens, errs = lexer.lex(content, filename)
   if errs and #errs > 0 then
      io.stderr:write("lex error in " .. filename .. ": " .. errs[1].msg .. "\n")
   end
   local result: {TokenEntry} = {}
   for _, tok in ipairs(tokens) do
      if tok.comments then
         for _, c in ipairs(tok.comments) do
            table.insert(result, {kind = "comment", text = c.text})
         end
      end
      table.insert(result, {kind = "token", text = tok.tk})
   end
   return result
end

local function read_cmd(cmd: string): string
   local f = io.popen(cmd)
   if not f then return "" end
   local out = f:read("*a")
   f:close()
   return out
end

local function get_staged_files(): {string}
   local out = read_cmd("git diff --cached --name-only --diff-filter=ACMR")
   local files: {string} = {}
   for line in out:gmatch("[^\n]+") do
      if line:match("%.tl$") then
         table.insert(files, line)
      end
   end
   return files
end

local function get_old_content(filepath: string): string
   local result = read_cmd("git show HEAD:" .. filepath .. " 2>/dev/null")
   return result
end

local function get_new_content(filepath: string): string
   return read_cmd("git show :" .. filepath)
end

local function myers_diff(old: {TokenEntry}, new: {TokenEntry}): {DiffOp}
   local n = #old
   local m = #new
   if n == 0 and m == 0 then return {} end

   local v: {integer: integer} = {[1] = 0}
   -- trace[d+1] = copy of v saved at start of round d (before round d edits)
   local trace: {{integer: integer}} = {}

   local d_found = 0
   local found = false

   for d = 0, n + m do
      local snap: {integer: integer} = {}
      for k, xv in pairs(v) do snap[k] = xv end
      table.insert(trace, snap)

      for k = -d, d, 2 do
         local x: integer
         if k == -d or (k ~= d and (v[k-1] or 0) < (v[k+1] or 0)) then
            x = v[k+1] or 0
         else
            x = (v[k-1] or 0) + 1
         end
         local y = x - k
         while x < n and y < m
            and old[x+1].kind == new[y+1].kind
            and old[x+1].text == new[y+1].text
         do
            x = x + 1
            y = y + 1
         end
         v[k] = x
         if x >= n and y >= m then
            d_found = d
            found = true
            break
         end
      end
      if found then break end
   end

   -- backtrack: build ops in reverse, then flip
   local rev: {DiffOp} = {}
   local x = n
   local y = m

   for d = d_found, 0, -1 do
      local snap = trace[d + 1]  -- V state before round d
      local k = x - y
      local prev_k: integer
      if k == -d or (k ~= d and (snap[k-1] or 0) < (snap[k+1] or 0)) then
         prev_k = k + 1  -- came from insertion (diagonal k+1 -> k)
      else
         prev_k = k - 1  -- came from deletion (diagonal k-1 -> k)
      end
      local prev_x = snap[prev_k] or 0
      local prev_y = prev_x - prev_k
      local after_x = prev_x + (prev_k == k - 1 and 1 or 0)
      local after_y = prev_y + (prev_k == k + 1 and 1 or 0)

      -- snake in reverse
      while x > after_x and y > after_y do
         x = x - 1
         y = y - 1
         table.insert(rev, {op = "=", entry = old[x + 1]})
      end

      -- edit
      if d > 0 then
         if prev_k == k - 1 then
            x = x - 1
            table.insert(rev, {op = "-", entry = old[x + 1]})
         else
            y = y - 1
            table.insert(rev, {op = "+", entry = new[y + 1]})
         end
      end
   end

   local ops: {DiffOp} = {}
   for i = #rev, 1, -1 do
      table.insert(ops, rev[i])
   end
   return ops
end

local type IgnoreRule = record
   extra: string
   next: string
end

local ignore_rules: {IgnoreRule} = {
   {extra = ",", next = "}"},
}

local function apply_ignore_rules(ops: {DiffOp}): {DiffOp}
   local result: {DiffOp} = {}
   for i, op in ipairs(ops) do
      if op.op == "+" then
         local next_text: string = nil
         if ops[i + 1] and ops[i + 1].op == "=" then
            next_text = ops[i + 1].entry.text
         end
         local ignore = false
         for _, rule in ipairs(ignore_rules) do
            if op.entry.text == rule.extra and next_text == rule.next then
               ignore = true
               break
            end
         end
         if not ignore then
            table.insert(result, op)
         end
      else
         table.insert(result, op)
      end
   end
   return result
end

local function diff_files(filepath: string)
   local old_content = get_old_content(filepath)
   local new_content = get_new_content(filepath)
   local old_tokens = tokenize(old_content, filepath .. ":old")
   local new_tokens = tokenize(new_content, filepath .. ":new")

   local ops = apply_ignore_rules(myers_diff(old_tokens, new_tokens))

   local changed: {integer: boolean} = {}
   for i, op in ipairs(ops) do
      if op.op ~= "=" then changed[i] = true end
   end

   local has_diff = next(changed) ~= nil
   if not has_diff then return end

   print("\n=== " .. filepath .. " ===")
   local context = 2
   local last_printed = -(context + 1)

   for i, op in ipairs(ops) do
      local near = false
      for c = i - context, i + context do
         if changed[c] then near = true; break end
      end
      if near then
         if i - last_printed > context + 1 and last_printed >= 0 then
            print("  ...")
         end
         local prefix = op.op == "=" and " " or op.op
         print(string.format("  %s [%s] %q", prefix, op.entry.kind, op.entry.text))
         last_printed = i
      end
   end
end

local files = get_staged_files()
if #files == 0 then
   print("No staged .tl files.")
   os.exit(0)
end

for _, filepath in ipairs(files) do
   diff_files(filepath)
end
