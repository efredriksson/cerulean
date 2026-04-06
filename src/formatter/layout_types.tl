local record StatementLayout
    preserve_blank_line_after: boolean
    render_mode: string
    verbatim_lines: {string} | nil
    body_layout: BlockLayout
    if_block_layouts: {BlockLayout}
end

local record BlockLayout
    statements: {StatementLayout}
end

local layout_types = {
    BlockLayout = BlockLayout,
    StatementLayout = StatementLayout,
}

function StatementLayout.new(): StatementLayout
    local self: StatementLayout = setmetatable({}, {__index = StatementLayout})
    self.preserve_blank_line_after = false
    self.render_mode = "format"
    self.verbatim_lines = nil
    self.body_layout = nil
    self.if_block_layouts = {}
    return self
end

function BlockLayout.new(statements: {StatementLayout}): BlockLayout
    local self: BlockLayout = setmetatable({}, {__index = BlockLayout})
    self.statements = statements
    return self
end

return layout_types
