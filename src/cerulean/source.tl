local record Text
    lines: {string}
end

local record Range
    first_line: integer
    last_line: integer
end

local record Region
    start_line: integer
    end_line: integer
end

local record Regions
    regions: {Region}
end

local source = {
    Text = Text,
    Range = Range,
    Region = Region,
    Regions = Regions,
}

function Text.new(input: string): Text
    local self: Text = setmetatable({}, {__index = Text})
    self.lines = {}
    for line_str in string.gmatch(input .. "\n", "(.-)\n") do
        table.insert(self.lines, line_str)
    end
    return self
end

function Range.new(first_line: integer, last_line: integer): Range
    local self: Range = setmetatable({}, {__index = Range})
    self.first_line = first_line
    self.last_line = last_line
    return self
end

function Region.new(start_line: integer, end_line: integer): Region
    local self: Region = setmetatable({}, {__index = Region})
    self.start_line = start_line
    self.end_line = end_line
    return self
end

function Region:includes_line(line_number: integer): boolean
    return line_number >= self.start_line and line_number <= self.end_line
end

function Region:includes_range(start_line: integer, end_line: integer): boolean
    return start_line <= self.end_line and self.start_line <= end_line
end

function Regions.new(regions: {Region}): Regions
    local self: Regions = setmetatable({}, {__index = Regions})
    self.regions = regions
    return self
end

function Regions:is_empty(): boolean
    return #self.regions == 0
end

function Regions:includes_line(line_number: integer): boolean
    for _, region in ipairs(self.regions) do
        if region:includes_line(line_number) then
            return true
        end
    end
    return false
end

function Regions:includes_range(start_line: integer, end_line: integer): boolean
    for _, region in ipairs(self.regions) do
        if region:includes_range(start_line, end_line) then
            return true
        end
    end
    return false
end

function source.overlaps(
    first_line: integer, last_line: integer, other_first: integer, other_last: integer
): boolean
    return first_line <= other_last and other_first <= last_line
end

function source.subtract(
    range: Range, remove_first: integer, remove_last: integer
): {Range}
    if not source.overlaps(
        range.first_line, range.last_line, remove_first, remove_last
    ) then
        return {range}
    end

    local result: {Range} = {}
    if remove_first > range.first_line then
        table.insert(result, Range.new(range.first_line, remove_first - 1))
    end
    if remove_last < range.last_line then
        table.insert(result, Range.new(remove_last + 1, range.last_line))
    end
    return result
end

function source.subtract_many(base: {Range}, removals: {Range}): {Range}
    local current = base
    for _, removal in ipairs(removals) do
        local updated: {Range} = {}
        for _, range in ipairs(current) do
            local survivors = source.subtract(
                range, removal.first_line, removal.last_line
            )
            for _, survivor in ipairs(survivors) do
                table.insert(updated, survivor)
            end
        end
        current = updated
    end
    return current
end

local function find_enclosing_region_end(
    block_regions: {Range}, line: integer, last_line: integer
): integer
    local innermost_end = last_line + 1
    for _, block in ipairs(block_regions) do
        if block.first_line <= line and block.last_line > line then
            if block.last_line < innermost_end then
                innermost_end = block.last_line
            end
        end
    end
    return innermost_end
end

-- True when an `fmt:on` closes this `fmt:off` before any further `fmt:off`
-- opens. An intervening `fmt:off` begins an unrelated region, so the current
-- one falls back to block scoping rather than swallowing it.
local function fmt_on_pairs_after(text: Text, after_line: integer): boolean
    for i = after_line + 1, #text.lines do
        if text.lines[i]:match("%-%-%s*fmt:%s*on") then
            return true
        end
        if text.lines[i]:match("%-%-%s*fmt:%s*off") then
            return false
        end
    end
    return false
end

function source.collect_fmt_off_regions(text: Text, block_regions: {Range}): Regions
    local regions: {Region} = {}
    local formatting_off = false
    local off_start = 0
    local region_end = 0
    local has_pairing_on = false

    for line_number, line_str in ipairs(text.lines) do
        if not formatting_off and line_str:match("%-%-%s*fmt:%s*off") then
            formatting_off = true
            off_start = line_number
            region_end = find_enclosing_region_end(
                block_regions, line_number, #text.lines
            )
            -- An explicit `fmt:on` overrides block scoping even when the
            -- directives straddle a block boundary, matching what the author
            -- wrote.
            has_pairing_on = fmt_on_pairs_after(text, line_number)
        end

        if formatting_off then
            if line_number > off_start and line_str:match("%-%-%s*fmt:%s*on") then
                table.insert(regions, Region.new(off_start, line_number))
                formatting_off = false
            elseif line_number >= region_end and not has_pairing_on then
                if off_start <= region_end - 1 then
                    table.insert(regions, Region.new(off_start, region_end - 1))
                end
                formatting_off = false
            end
        end
    end

    if formatting_off and off_start <= #text.lines then
        table.insert(regions, Region.new(off_start, #text.lines))
    end

    return Regions.new(regions)
end

return source
