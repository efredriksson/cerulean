-- Long-running formatter daemon. Invoked as `ceru daemon` by editor
-- integrations and kept alive across the editor session.
local options = require("cerulean.options")
local rewriter = require("cerulean.rewriter")

local help = [[
Reads framed format requests via stdin, writes framed responses to stdout.

Every frame is line-framed with an explicit body length in bytes, even when
the body is empty:
   <KIND>\n<byte-len>\n<body-bytes>
Requests:
   FORMAT\n<n>\n<source-bytes>   format Teal source
   PING\n0\n                     liveness probe
   QUIT\n0\n                     clean shutdown (no reply)
Responses:
   OK\n<n>\n<output-bytes>       formatted output
   ERR\n<n>\n<message-bytes>     parse error or bad request
   PONG\n0\n                     reply to PING
Blank lines between frames are ignored.]]

local interface DaemonIO
    read_line: function(self): string
    read_bytes: function(self, integer): string
    write: function(self, string)
    write_err: function(self, string)
end

local daemon = {DaemonIO = DaemonIO, help = help}

local function read_exact_bytes(
    daemon_io: DaemonIO, byte_count: integer
): (string, string)
    local parts: {string} = {}
    local remaining = byte_count
    while remaining > 0 do
        local chunk = daemon_io:read_bytes(remaining)
        if not chunk or #chunk == 0 then
            return nil, "short read on body"
        end
        parts[#parts + 1] = chunk
        remaining = remaining - #chunk
    end
    return table.concat(parts), nil
end

local function send_frame(daemon_io: DaemonIO, kind: string, payload: string)
    daemon_io:write(kind .. "\n" .. tostring(#payload) .. "\n" .. payload)
end

local function read_frame(daemon_io: DaemonIO): (string, string, string)
    local kind = daemon_io:read_line()
    while kind == "" do
        kind = daemon_io:read_line()
    end
    if not kind then
        return nil, nil, nil
    end
    local length_line = daemon_io:read_line()
    if not length_line then
        return nil, nil, "missing length header"
    end
    local byte_count = math.tointeger(tonumber(length_line))
    if not byte_count or byte_count < 0 then
        return nil, nil, "bad length header: " .. length_line
    end
    local body, read_err = read_exact_bytes(daemon_io, byte_count)
    if read_err then
        return nil, nil, read_err
    end
    return kind, body, nil
end

local function load_options(): options.FormatterOptions
    local config_opts, _ = options.from_config_file()
    return config_opts or options.default()
end

local function handle_format_request(daemon_io: DaemonIO, source: string)
    local rewrite = rewriter.rewrite(source, "buffer.tl", load_options())
    if #rewrite.parse_errors > 0 then
        local first = rewrite.parse_errors[1]
        local error_msg = string.format(
            "%d:%d: %s", first.y or 0, first.x or 0, first.msg or "parse error"
        )
        send_frame(daemon_io, "ERR", error_msg)
        return
    end
    send_frame(daemon_io, "OK", rewrite.output)
end

function daemon.run(daemon_io: DaemonIO)
    daemon_io:write_err("cerulean-daemon: ready\n")

    while true do
        local kind, body, err = read_frame(daemon_io)
        if err then
            send_frame(daemon_io, "ERR", err)
        elseif not kind then
            break
        elseif kind == "FORMAT" then
            handle_format_request(daemon_io, body)
        elseif kind == "PING" then
            send_frame(daemon_io, "PONG", "")
        elseif kind == "QUIT" then
            break
        else
            send_frame(daemon_io, "ERR", "unknown command: " .. kind)
        end
    end
end

return daemon
