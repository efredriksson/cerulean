local record LineRange
    first_line: integer
    last_line: integer
end

local ranges = {LineRange = LineRange}

function LineRange.new(first_line: integer, last_line: integer): LineRange
    local self: LineRange = setmetatable({}, {__index = LineRange})
    self.first_line = first_line
    self.last_line = last_line
    return self
end

function ranges.new(first_line: integer, last_line: integer): LineRange
    return LineRange.new(first_line, last_line)
end

function ranges.overlaps(
    first_line: integer, last_line: integer, other_first: integer, other_last: integer
): boolean
    return first_line <= other_last and other_first <= last_line
end

function ranges.subtract(
    range: LineRange, remove_first: integer, remove_last: integer
): {LineRange}
    if not ranges.overlaps(
        range.first_line, range.last_line, remove_first, remove_last
    ) then
        return {range}
    end

    local result: {LineRange} = {}
    if remove_first > range.first_line then
        table.insert(result, LineRange.new(range.first_line, remove_first - 1))
    end
    if remove_last < range.last_line then
        table.insert(result, LineRange.new(remove_last + 1, range.last_line))
    end
    return result
end

function ranges.subtract_many(base: {LineRange}, removals: {LineRange}): {LineRange}
    local current = base
    for _, removal in ipairs(removals) do
        local updated: {LineRange} = {}
        for _, range in ipairs(current) do
            local survivors = ranges.subtract(
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

return ranges
