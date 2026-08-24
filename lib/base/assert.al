## `assert(cond)` — a runtime check (Stdlib §4.2). When `cond` is false it
## `panic`s — a defined failure that v1 lowers to a deterministic trap (I11).
## Base tier (freestanding). In a `comptime` context a false `assert` reaches
## `panic` during comptime evaluation, which is a **compile error** (Stdlib §4.3)
## — the failure is statically proven and diagnosed at build time.
assert := fn(cond : bool) {
  if not cond { panic("assertion failed") }
}
