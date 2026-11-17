- A program that declares its own function named like a built-in the compiler recognised by spelling
  (`size`, `align`, `len`, `str_at`, `str_eq`, `byte_at`, `bytes`, `panic`, `forget`, `expect`, `sub`,
  `shl`, `shr`, `rotl`, `rotr`) now has its calls reach that function on every path (#1434). On the
  x86_64 path a function takes when the shared IR does not build it, such a call crashed the compiler
  (exit 139) or was silently replaced by the built-in (`align(10)` answered a type's alignment, and
  `forget()` dropped the call). Grammar §2.3 makes built-ins prelude identifiers, not keywords. An
  undeclared call keeps its built-in meaning unchanged. A declared `bitcast` is still parsed as the
  reinterpret (#1718). A call whose arguments the declared function does not accept, such as a `str`
  passed to `len := fn(x : u64)`, is refused with `type mismatch` at the argument (#1719). The
  specification has not yet decided whether such a declaration replaces the built-in or adds to it
  (spec#166).
