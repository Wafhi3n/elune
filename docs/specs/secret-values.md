# Secret values

> Status: implemented on 2026-10-13; criteria 1 to 5 met (see the end of each criterion) · Fork
> decided on 2026-10-12 by the maintainer (Wafhi3n); the behavior emulates only what was measured
> in the game client, and is opt-in.

## The problem

Since the Midnight UI layer (WoW: Forever 1.60.1, and modern retail), the client hands addons
**secret values**: a unit name read in a dungeon, the text and sender of a chat line during a boss
fight, an aura's data in combat. Addon (tainted) code that compares one, or uses it as a table key,
throws, often far from where the value was read. A real case, seen in a dungeon on 2026-09-20:
`UnitName(unit)` read from the mouseover tooltip, then `roster[name]` three calls later →
`attempted to index a table that cannot be indexed with secret keys`.

Headless addon tests run on elune, which has no secrets. A pure-Lua fake cannot stand in for one,
measured under elune 3.1 on 2026-10-12: a `newproxy` userdata whose metamethods all throw still
passes `s == ""`, `s ~= ""`, `t[s] = 1` and `t[s]` **without error** (Lua 5.1 never calls `__eq`
across types, and accepts any userdata as a key). Those are exactly the two failures seen in game.
Only the VM can reproduce them, so today such a bug is caught by a player, never by a test.

## What we want

A test can make a secret, hand it to the addon code under test, and see that code fail the way it
would in game when it compares the secret or uses it as a table key, and pass when it checks
`issecretvalue` first.

- `debug.newsecret(v)` returns `v` marked secret. `v` must be a string, a number or a boolean.
- `debug.issecret(v)` returns `true` for a secret, `false` for anything else. It never throws.
- A secret keeps its mark wherever it is copied: locals, upvalues, globals, table **values**,
  arguments, return values, varargs, `select`, `unpack`, `pcall` results, coroutine transfers.
- Two operations on a secret throw (measured, see the table below): **comparison** and **use as a
  table key**.

Tests install the client's name themselves, for example `issecretvalue = debug.issecret`, and tell
the fork apart from upstream with `debug.newsecret ~= nil`, never by parsing the version string.

## What we DON'T do

- **No new global, nothing changes by default.** Without a call to `debug.newsecret`, no secret
  exists and the fork behaves exactly like upstream elune. Addon code tests for the *presence* of
  `issecretvalue`; a builtin global would silently change which path existing tests take.
- **No emulation of what nobody measured.** Truthiness (`if s then`), `rawequal`, arithmetic,
  concatenation, `#`, `tostring`, string methods and any C function behave as they would on the
  plain value. A result keeps the mark only when the operation hands back the very same value
  (`tostring` of a string, `s .. ""`, `select`); a new value is plain, so `s .. "x"` or `s:upper()`
  "un-secrets" it. A test must not rely on those paths, either way. A wrong guess would give green
  tests on code that crashes in game, which is worse than no emulation.
- **No secret tables** (`issecrettable`), no `hasanysecretvalues`, no `scrubsecretvalues`, no
  `canaccesssecrets`: client APIs not measured yet. Tests can write them in Lua on top of
  `debug.issecret` where they need them.
- **No taint condition.** The client refuses *tainted* code only; Blizzard's secure code may use a
  secret. Headless tests run untainted, so here every caller is refused. A taint-aware mode can come
  later, if a test ever needs secure code to handle a secret.
- **Not the client's error text for comparisons.** Nobody recorded it. The index error reuses the
  measured text.

## Behaviors

| # | Operation | Fork | Source |
|---|---|---|---|
| S1 | `t[s]`, read | throws `attempted to index a table that cannot be indexed with secret keys` | measured in game, 2026-09-20 (dungeon, `roster[name]`) |
| S2 | `t[s] = v`, write | throws, same text | chosen: same table lookup as S1; Questie's crash on a secret `CHAT_MSG_SKILL` arg1 used as a key |
| S3 | `rawget(t, s)`, `rawset(t, s, v)`, `next(t, s)` | throw, same text | chosen: same lookup, no metamethod involved |
| S4 | `s == x`, `s ~= x` | throws `attempt to compare a secret value` | measured in game, 2026-09-20 (`n ~= ""` included) |
| S5 | `s == nil` | throws, as S4 | chosen: one opcode for every equality; the rule that holds in game is "test the secret before ANY comparison" |
| S6 | `<`, `<=`, `>`, `>=`, `table.sort` with a secret | throw, as S4 | chosen: "comparison" as measured; same rule |
| S7 | `t[k] = s`, secret as a **value** | allowed, the stored value stays secret | measured: a secret ends up stored (a secret written into SavedVariables, 2026-09-20) |
| S8 | `debug.issecret`, `type(s)` | allowed; `type` returns the plain type | `issecretvalue` is the client's own test; `type` chosen (unmeasured) |
| S9 | everything else | behaves as the plain value; a new result is plain, the same value handed back stays secret | not emulated, see above |

Measured facts come from the WoW: Forever field notes of the `wow-addon-dev` plugin
(`skills/wow-forever-api/references/secret-values-and-lockdowns.md`,
github.com/Wafhi3n/wow-addon-workspace). A behavior moves from "chosen" to "measured" only with a
dated observation in the client.

## Edge cases

- `debug.newsecret(nil)`, a table, a function: error (`bad argument #1 to 'newsecret'`).
- `debug.newsecret(s)` on a secret: returns it, still secret.
- A secret string and the same plain string share one interned string: the mark lives on the
  **value**, so `"Bob"` stays plain everywhere else.
- Indexing a **table** with a secret key throws before its `__index` / `__newindex` runs, and before
  the key is inserted. A userdata whose `__index` / `__newindex` is a function receives the secret
  key without error: nothing about userdata was measured, so nothing is refused there.
- Errors are ordinary Lua errors: `pcall` catches them, the message carries the usual position.

## Acceptance criteria

1. [test] S1 to S8, one case each, in elune's own suite (`tests/luatest_secrets.lua`), including the
   negative cases (a plain value still compares and indexes). → `luatest` (17 cases, pass)
2. [test] Copying keeps the mark: local, upvalue, global, table value, argument, return, vararg,
   `select`, `unpack`, `pcall`, coroutine. → same file (pass)
3. [test] Without `debug.newsecret`, nothing changes: upstream's suites (`luatest_scriptcases`,
   coroutine, profiling) pass unchanged. → `luatest` (pass)
4. [check] Windows, Linux and macOS builds pass CI. → GitHub Actions run 38444699312 (2026-10-13,
   commit d680217): all three green.
5. [agent] In the WoW addon workspace (`Wafhi3n/wow-addon-tooling`, branch `feat/elune-forever`,
   commit e977801), its full headless suite gives the same counts with this fork as with upstream
   elune 3.1 (109 files, 3248 checks, 0 failures on 2026-10-13); then one addon test injects a real
   secret name and checks that the addon's guard tests the secret before any comparison (3253
   checks). Swapping the guard's order makes that test fail (3 failures), and under upstream elune
   the secret part skips. Observed by the implementing session, not yet by the maintainer.

## Contract

- `debug.newsecret(v) -> v'` (string, number or boolean), `debug.issecret(v) -> boolean`.
- C API: `lua_setsecret(L, idx)` marks the value at `idx`; `lua_issecret(L, idx)` tests it.
- Error texts: S1-S3 `attempted to index a table that cannot be indexed with secret keys`;
  S4-S6 `attempt to compare a secret value`.
- `lua -v` reports `Elune <version>-forever.<n>`.

## Links

- Upstream: https://github.com/Meorawr/elune
- `README.md` (what this fork is), `CHANGELOG.md`.
