- **The shared IR builds `deref(q)` read whole when `q`'s declaration spells no type (#1786).** The
  builder now takes the pointee type from the one sema recorded for the `deref` node. That covers a local
  bound by inference (`q := get(p)`, `q := ptr(s)`), a match payload binding (`Some(q)` of an
  `Option(ptr(S))`, a payload of a program's generic enum instance), and a struct field (`deref(h.p)`,
  `deref(hp.p)`). Until now each of these was refused, so on x86_64 the function took the legacy path.
  That path answered a wrong value for `deref(hp.p)` through a `ptr(H)` (1 for 42 in
  `test/ir38_deref_field_ptr.al`); the default x86_64 path and wasm now answer 42 (#1799 keeps the
  legacy half). A type that another module writes is used only once it is proven to name the same
  declaration in this module; otherwise the read is still refused, under its own cause.
