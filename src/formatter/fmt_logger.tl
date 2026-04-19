local fmt_logger = {}

local LEVEL_NUMBERS: {string: integer} = {nothing = 0, info = 1, debug = 2}

local current_level = "nothing"

function fmt_logger.set_level(level_name: string): boolean
    if not LEVEL_NUMBERS[level_name] then
        return false
    end
    current_level = level_name
    return true
end

local function should_log_for(level_name: string): boolean
    return LEVEL_NUMBERS[current_level] >= LEVEL_NUMBERS[level_name]
end

local function log_internal(msg: string, level: string, ...: string | number | boolean)
    if should_log_for(level) then
        io.stderr:write(string.format("[fmt:%s] %s\n", level, string.format(msg, ...)))
    end
end

function fmt_logger.info(msg: string, ...: string | number | boolean)
    log_internal(msg, "info", ...)
end

function fmt_logger.debug(msg: string, ...: string | number | boolean)
    log_internal(msg, "debug", ...)
end

return fmt_logger
