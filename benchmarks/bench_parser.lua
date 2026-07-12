-- Run from the repo root:
--     lune run benchmarks/bench_parser.lua

local csv = require("../csv")

local function make_simple(rows)
    local out = { "id,name,email,role\n" }

    for i = 1, rows do
        out[#out + 1] =
            tostring(i) ..
            ",User " .. tostring(i) ..
            ",user" .. tostring(i) .. "@example.com,Member\n"
    end

    return table.concat(out)
end

local function make_quoted(rows)
    local out = { "id,note,amount\n" }

    for i = 1, rows do
        out[#out + 1] =
            tostring(i) ..
            ',"hello, ""quoted"" value ' .. tostring(i) .. '",42\n'
    end

    return table.concat(out)
end

local function make_multiline(rows)
    local out = { "id,note\n" }

    for i = 1, rows do
        out[#out + 1] =
            tostring(i) ..
            ',"line one\nline two ' .. tostring(i) .. '"\n'
    end

    return table.concat(out)
end

local function memory_kb()
    local ok, amount = pcall(function()
        return collectgarbage("count")
    end)

    if ok then
        return amount
    end

    return 0
end

local function run_case(name, text, parameters)
    local start_mem = memory_kb()
    local started = os.clock()
    local count = 0
    local file = csv.openstring(text, parameters)

    for _ in file:lines() do
        count = count + 1
    end

    file:close()

    local elapsed = os.clock() - started
    local end_mem = memory_kb()
    local rows_per_second = count / math.max(elapsed, 0.000001)

    print(
        string.format(
            "%-28s rows=%7d time=%.4fs rows/s=%10.0f mem_delta=%8.1fKB",
            name,
            count,
            elapsed,
            rows_per_second,
            end_mem - start_mem
        )
    )
end

local ROWS = 50000

local cases = {
    { "simple", make_simple(ROWS) },
    { "quoted", make_quoted(ROWS) },
    { "embedded newlines", make_multiline(math.floor(ROWS / 5)) },
}

for _, case in ipairs(cases) do
    run_case(case[1] .. " / normal", case[2], {
        header = true,
        strict = true,
    })

    run_case(case[1] .. " / reuse_record", case[2], {
        header = true,
        strict = true,
        reuse_record = true,
    })

    run_case(case[1] .. " / select", case[2], {
        header = true,
        strict = true,
        select = { "id" },
    })
end
