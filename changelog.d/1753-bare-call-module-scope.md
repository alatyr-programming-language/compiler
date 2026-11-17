- **An unqualified call, a method call `w.get()` included, is now checked against the function the
  caller's own module names (#1753).** With `get(u64)` in the package root and `get(W)` in its module
  `m`, the root's `w.get()` passed sema's check as if the two formed one overload set, and every backend
  ran the root's `get(u64)` on the `W`: x86_64 answered a value read off the struct's address, which
  moved with the program around it, or crashed; the other backends trapped. A module's scope holds its own
  declarations and its ancestors', not a child's (Modules §3, §5), and `w.get()` is the call `get(w)`
  (MOD-3), so no `get` the root can name accepts a `W`. Such a call is now refused with `type mismatch`
  at the call, in either module order (Functions §1.4). The specification's spelling for `m`'s
  function is the qualified `w.m::get()`, which the compiler does not accept yet (#1366).
