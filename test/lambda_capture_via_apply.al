## FN-6 escaping closures (a slice of dyn) — a CAPTURING closure passed to a PURE FORWARDING higher-order
## fn `app(g, x){ return g(x) }` works: the lift inlines the forwarding call `app(f, 40)` to a DIRECT
## call `f(40)` (f no longer escapes as a value), and the existing capture pass injects f's captures →
## `f(40, c)`. `c := 2; app(f, 40)` = 42. (General non-forwarding HOFs — map/filter/twice — still need
## env/dyn and reject fail-loud.)
app := fn(g : u64, x : u64) -> u64 { return g(x) }
main := fn() -> u64 {
  c := 2
  f := fn(n : u64) -> u64 { return n + c }
  return app(f, 40)
}
