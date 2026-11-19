## e2e — #1772: a bare call `to_upper(x)` to this file's own `to_upper`, while `base::char` — pulled
## into the compilation by the qualified `base::char::to_char` — declares a `pub to_upper` of its own.
## Modules §5: the file's scope binds `to_upper` once, to its own declaration, and the library's is a
## different function (Functions §1.4: an overload set is one scope's). On x86_64 the front half does
## not rewrite the call, so the IR builder sees both declarations: it builds `lift` only since #1772
## (the parent refused it as `several functions of that name (an overload set)` and left it to the
## legacy emitter), and calls this file's `to_upper`, as the legacy emitter does. The twins' front half
## resolves the call before their builder runs, so on them this is a control.
## Exit 42 = `lift(40)` is this file's 40 + 2; otherwise 100 + the failed check (101 `to_char(55)`
## did not round-trip, so `base::char` did not take part as written; 102 `lift` answered other than
## 42 — the library's `to_upper` takes a `char` and answers one, and leaves 40 unchanged).
to_upper := fn(x : u64) -> u64 { x + 2 }
lift := fn(x : u64) -> u64 { to_upper(x) }
main := fn() -> u64 {
  c := base::char::to_char(55)
  if u32(c) != 55 { return 101 }
  x : u64 = 40
  h := lift(x)
  if h != 42 { return 102 }
  h
}
## expect: run 42
