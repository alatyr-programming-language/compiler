## Issue #1753 / Functions §1.4 (FN-7), Modules §2 (MOD-3), §3, §5 — `w.get()` in the package root,
## where the root declares `get(u64)` and its child module `m` declares `get(W)`. UFCS is the call
## `get(w)`, resolved in the caller's scope: the root's scope holds its own `get(u64)` and not `m`'s,
## which a path (`w.m::get()`) would reach. No `get` the root can name accepts a `W` (the prelude's
## `get`s take an Arena, Option, Vec, Map or HashMap receiver), so the call is ill-formed whether a
## module declaration joins or shadows a prelude name. Here `m` sorts before `main` and the root's
## `get` precedes `main`. PARENT (#1755 head e43bebee; main ce0f92e7 alike), native x86_64: check 0,
## then x86_64 IR and legacy 129 on every run, aarch64 and riscv64 trap 133, wasm traps 134 — the
## root's `get(u64)` bound to a `W`. Expected: check and build rc 1, located at the call, line 5 of
## `main`.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      kind = Kind.executable,
      output = "issue1753-method-recv-reject",
    ),
  ],
)
## expect: reject "type mismatch" "at line 5"
