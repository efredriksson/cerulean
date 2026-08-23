rockspec_format = "3.0"
package = "cerulean"
version = "dev-1"

source = {
   url = "git+https://github.com/efredriksson/cerulean",
   branch = "main",
}

description = {
   summary = "A formatter for the Teal programming language",
   detailed = [[
      Cerulean formats Teal source files with configurable indentation,
      line width, and require-statement sorting. It can be run as a CLI
      tool or integrated into editor workflows.
   ]],
   homepage = "https://efredriksson.github.io/cerulean",
   license = "MIT",
}

dependencies = {
   "lua >= 5.1",
   "luafilesystem",
   "tl",
}

build = {
   type = "builtin",
   modules = {
      ["cerulean"] = "dist/cerulean/init.lua",
      ["cerulean.ast"] = "dist/cerulean/ast.lua",
      ["cerulean.ast_traversal"] = "dist/cerulean/ast_traversal.lua",
      ["cerulean.blank_lines"] = "dist/cerulean/blank_lines.lua",
      ["cerulean.cli"] = "dist/cerulean/cli.lua",
      ["cerulean.daemon"] = "dist/cerulean/daemon.lua",
      ["cerulean.block_doc"] = "dist/cerulean/block_doc.lua",
      ["cerulean.comment_audit"] = "dist/cerulean/comment_audit.lua",
      ["cerulean.comment_slots"] = "dist/cerulean/comment_slots.lua",
      ["cerulean.construct_layout"] = "dist/cerulean/construct_layout.lua",
      ["cerulean.doc"] = "dist/cerulean/doc.lua",
      ["cerulean.expr_doc"] = "dist/cerulean/expr_doc.lua",
      ["cerulean.file_discovery"] = "dist/cerulean/file_discovery.lua",
      ["cerulean.fmt_logger"] = "dist/cerulean/fmt_logger.lua",
      ["cerulean.frozen_regions"] = "dist/cerulean/frozen_regions.lua",
      ["cerulean.function_doc"] = "dist/cerulean/function_doc.lua",
      ["cerulean.inline_stmt_doc"] = "dist/cerulean/inline_stmt_doc.lua",
      ["cerulean.options"] = "dist/cerulean/options.lua",
      ["cerulean.delimited_list_doc"] = "dist/cerulean/delimited_list_doc.lua",
      ["cerulean.parser"] = "dist/cerulean/parser.lua",
      ["cerulean.precedence"] = "dist/cerulean/precedence.lua",
      ["cerulean.render_context"] = "dist/cerulean/render_context.lua",
      ["cerulean.require_sort"] = "dist/cerulean/require_sort.lua",
      ["cerulean.rewriter"] = "dist/cerulean/rewriter.lua",
      ["cerulean.source"] = "dist/cerulean/source.lua",
      ["cerulean.stmt_doc"] = "dist/cerulean/stmt_doc.lua",
      ["cerulean.string_literal"] = "dist/cerulean/string_literal.lua",
      ["cerulean.table_doc"] = "dist/cerulean/table_doc.lua",
      ["cerulean.token_stream"] = "dist/cerulean/token_stream.lua",
      ["cerulean.trivia_doc"] = "dist/cerulean/trivia_doc.lua",
      ["cerulean.type_body_doc"] = "dist/cerulean/type_body_doc.lua",
      ["cerulean.type_doc"] = "dist/cerulean/type_doc.lua",
   },
   install = {
      bin = { ceru = "bin/ceru" },
   },
}
