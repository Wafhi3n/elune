--
-- Secret value tests (Forever fork). See docs/specs/secret-values.md: S1 to S9 below refer to the
-- behaviors listed there. Only comparison and table-key use are measured in the game client; the
-- other refusals are choices documented in the spec.
--

-- luacheck: globals debug.newsecret debug.issecret

local newsecret, issecret = debug.newsecret, debug.issecret

local KEY_ERROR = "attempted to index a table that cannot be indexed with secret keys"
local COMPARE_ERROR = "attempt to compare a secret value"

-- Runs f and checks that it throws an error containing `text` (plain match).
local function throws(f, text)
    local ok, err = pcall(f)
    assert(not ok, "expected an error: " .. text)
    assert(string.find(tostring(err), text, 1, true), "unexpected error: " .. tostring(err))
end

-- A plain copy of a value's text, for checks that must not compare the secret itself.
local function plain(v)
    return string.format("%s", v)
end

case("debug.newsecret: marks strings, numbers and booleans", function()
    assert(issecret(newsecret("Bob")))
    assert(issecret(newsecret(42)))
    assert(issecret(newsecret(false)))
    assert(issecret(newsecret(newsecret("Bob"))))
    assert(plain(newsecret("Bob")) == "Bob")
    assert(plain(newsecret(42)) == "42")
end)

case("debug.newsecret: refuses nil, tables and functions", function()
    throws(function() return newsecret(nil) end, "bad argument #1 to 'newsecret'")
    throws(function() return newsecret({}) end, "bad argument #1 to 'newsecret'")
    throws(function() return newsecret(print) end, "bad argument #1 to 'newsecret'")
    throws(function() return newsecret() end, "bad argument #1 to 'newsecret'")
end)

case("debug.issecret: false for plain values, never throws", function()
    assert(issecret("Bob") == false)
    assert(issecret(nil) == false)
    assert(issecret({}) == false)
    assert(issecret(print) == false)
    assert(issecret() == false)
end)

case("S1: reading a table with a secret key throws", function()
    local s = newsecret("Bob")
    local t = { Bob = 1 }
    throws(function() return t[s] end, KEY_ERROR)
    throws(function() return t.x[s] end, "attempt to index field 'x'")
end)

case("S1: the secret key throws before __index runs", function()
    local s = newsecret("Bob")
    local called = false
    local t = setmetatable({}, { __index = function() called = true end })
    throws(function() return t[s] end, KEY_ERROR)
    assert(not called, "__index ran with a secret key")
end)

case("S2: writing a table with a secret key throws, nothing is stored", function()
    local s = newsecret("Bob")
    local called = false
    local t = {}
    local p = setmetatable({}, { __newindex = function() called = true end })
    throws(function() t[s] = 1 end, KEY_ERROR)
    throws(function() p[s] = 1 end, KEY_ERROR)
    assert(next(t) == nil, "a secret key was stored")
    assert(not called, "__newindex ran with a secret key")
end)

case("S3: rawget, rawset and next with a secret key throw", function()
    local s = newsecret("Bob")
    local t = { Bob = 1 }
    throws(function() return rawget(t, s) end, KEY_ERROR)
    throws(function() rawset(t, s, 2) end, KEY_ERROR)
    throws(function() return next(t, s) end, KEY_ERROR)
    assert(rawget(t, "Bob") == 1)
end)

case("S4: equality with a secret throws, on either side", function()
    local s = newsecret("Bob")
    throws(function() return s == "Bob" end, COMPARE_ERROR)
    throws(function() return s ~= "" end, COMPARE_ERROR)
    throws(function() return "Bob" == s end, COMPARE_ERROR)
    throws(function() return s == s end, COMPARE_ERROR)
    throws(function() return newsecret(1) == 1 end, COMPARE_ERROR)
end)

case("S5: comparing a secret with nil throws", function()
    local s = newsecret("Bob")
    throws(function() return s == nil end, COMPARE_ERROR)
    throws(function() return nil ~= s end, COMPARE_ERROR)
end)

case("S6: ordering a secret throws, table.sort included", function()
    local s = newsecret("b")
    local n = newsecret(2)
    throws(function() return s < "c" end, COMPARE_ERROR)
    throws(function() return s <= "c" end, COMPARE_ERROR)
    throws(function() return "a" > s end, COMPARE_ERROR)
    throws(function() return n >= 1 end, COMPARE_ERROR)
    throws(function() table.sort({ "c", s, "a" }) end, COMPARE_ERROR)
end)

case("S7: a secret stored as a table value stays secret", function()
    local s = newsecret("Bob")
    local t = {}
    t.name = s
    t[1] = s
    assert(issecret(t.name) and issecret(t[1]) and issecret(rawget(t, "name")))
    assert(plain(t.name) == "Bob")
end)

case("S8: type returns the plain type", function()
    assert(type(newsecret("Bob")) == "string")
    assert(type(newsecret(1)) == "number")
    assert(type(newsecret(true)) == "boolean")
end)

case("S9: operations nobody measured behave as on the plain value", function()
    local s = newsecret("Bob")
    local reached = false
    if s then reached = true end
    assert(reached)
    assert(#s == 3)
    assert(plain(s .. "!") == "Bob!")
    assert(rawequal(s, "Bob"))
    assert(plain(newsecret(2) + 1) == "3")
    -- A new value is plain; the same value handed back keeps the mark.
    assert(not issecret(s .. "x") and not issecret(s:upper()) and not issecret(newsecret(2) + 1))
    assert(issecret(tostring(s)) and issecret(s .. ""))
end)

case("Copies keep the mark: locals, upvalues, globals, arguments, returns", function()
    local s = newsecret("Bob")
    local copy = s
    assert(issecret(copy))
    local function upvalue() return s end
    assert(issecret(upvalue()))
    _G.SECRET_TEST_GLOBAL = s
    assert(issecret(_G.SECRET_TEST_GLOBAL))
    _G.SECRET_TEST_GLOBAL = nil
    local function identity(v) return v end
    assert(issecret(identity(s)))
end)

case("Copies keep the mark: varargs, select, unpack, pcall, coroutines", function()
    local s = newsecret("Bob")
    local function pack(...) return ... end
    assert(issecret((pack(1, s))) == false and issecret(select(2, pack(1, s))))
    assert(issecret(select(2, unpack({ 1, s }))))
    local ok, v = pcall(function() return s end)
    assert(ok and issecret(v))
    local co = coroutine.create(function(a)
        local b = coroutine.yield(a)
        return b
    end)
    local _, first = coroutine.resume(co, s)
    assert(issecret(first))
    local _, second = coroutine.resume(co, s)
    assert(issecret(second))
end)

case("Plain values are untouched by a secret of the same text", function()
    local s = newsecret("Bob")
    local t = { Bob = 1 }
    assert(t.Bob == 1 and t["Bob"] == 1)
    assert("Bob" == "Bob")
    assert(issecret("Bob") == false)
    assert(issecret(s))
    t.Bob = 2
    assert(rawget(t, "Bob") == 2)
end)

case("Errors from secrets are ordinary errors: pcall catches them with a position", function()
    local s = newsecret("Bob")
    local ok, err = pcall(function() return ({})[s] end)
    assert(not ok)
    assert(string.find(err, ":%d+: "), "no position in: " .. tostring(err))
end)
