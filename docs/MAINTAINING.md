# Maintaining the Forever fork

This fork follows two sources: upstream elune (rare changes) and what the WoW client does with
secret values (measured in game, one fact at a time). The rules below keep the fork honest: it
emulates only what was seen in the client, and out of the box it behaves exactly like upstream.

## Branches, versions, releases

- `main` mirrors upstream (`Meorawr/elune`). Never commit to it.
- `forever` carries the fork's work. Every change lands there through CI.
- `lua -v` prints `Elune <upstream version><ELUNE_VERSION_SUFFIX>`, e.g. `Elune 3.2-forever.1`.
  Bump the suffix (`CMakeLists.txt`) for every release, and tag `v<upstream version>-forever.<n>`.
- A tag makes CI draft a GitHub release with Windows, Linux and macOS archives; publishing the draft
  is a separate step. CI artifacts of ordinary pushes expire after 90 days; a release does not.

## Building

Windows, from a Visual Studio developer prompt (or after `vcvars64.bat`), which puts MSVC, CMake and
Ninja on the PATH:

```sh
cmake --preset windows
cmake --build --preset windows
cmake --build --preset windows --target install
cd build/windows/bin/Release && luatest.exe
```

Linux and macOS: the same with `--preset linux` / `--preset macos`. The configure step downloads
acutest. The installed tree (`build/<preset>/install`) holds `bin/lua`, `bin/luac` and the shared
library, the files a consumer copies.

## Syncing with upstream

```sh
git fetch upstream
git push origin upstream/main:main      # main stays a mirror
git switch forever && git merge main    # then build, luatest, push
```

Upstream changes taint behavior; our suite (`luatest`) and any downstream workspace's own tests must
give the same results before and after the merge.

## Adding or changing a secret-value behavior

Secret values live in `docs/specs/secret-values.md`. Each behavior there is **measured** (a dated
observation in the game client, with its source) or **chosen** (a decision, with its reason).

1. **Start from a measurement.** A crash in game that tests missed, a probe run on the client, a
   change in Blizzard's generated API docs. A doc change is not a measurement: measure before
   emulating.
2. **Update the spec table**: the new row, or a *chosen* row that becomes *measured*. Changes go both
   ways: if the client turns out to allow something the fork refuses (S2, S3, S5, S6 are choices),
   relax it, with a test. Without that path, strictness piles up unchecked.
3. **Write the test first** in `tests/luatest_secrets.lua` and see it fail.
4. **Change the VM.** The entry points:
   - `liblua/lobject.h`: the `secret` mark in `TValuefields`, `ttissecret`;
   - `liblua/lmanip.h`: every value constructor clears the mark, every copy carries it;
   - `liblua/lvm.c`: comparisons (`OP_EQ`, `luaV_lessthan`, `lessequal`) and table keys
     (`luaV_gettable`, `luaV_settable`, table branch only);
   - `liblua/lapi.c`: `lua_equal`, `lua_rawget`, `lua_rawset`, `lua_setsecret`, `lua_issecret`;
   - `liblua/ltable.c`: `luaH_next`;
   - `liblua/ldebug.c`: the error texts; `liblua/ldblib.c`: `debug.newsecret`, `debug.issecret`.
5. **CI green on the three platforms**, then a release (above).

Invariants, whatever the change: opt-in only (no new global; nothing differs until a test calls
`debug.newsecret`); nothing unmeasured is emulated; userdata is left alone; a test that needs
secrets detects the fork with `debug.newsecret ~= nil` and skips without it.
