## FN-6 §6.2 — a CAPTURING closure passed as a VALUE to a NON-forwarding / loop higher-order fn.
## `twice(g, x){ g(x) + g(x) }` calls its callable param TWICE, so the forwarding-inline cannot help.
## §6.2: generic code taking a callable MONOMORPHIZES over the concrete closure type. The driver
## specializes `twice` to THIS closure — f's capture `c` is threaded as a trailing param of `twice`,
## injected into every `g(...)` call inside `twice` (`g(x) -> g(x, c)`), and appended at the call site
## (`twice(f, 20) -> twice(f, 20, c)`). `g` stays a code-pointer param called through its slot; f's
## lifted fn already takes `(n, c)`. So the captures travel VISIBLY, no dyn/box (I3).
## c := 1; twice(f, 20) = (20+1) + (20+1) = 42.
twice := fn(g : u64, x : u64) -> u64 { return g(x) + g(x) }
main := fn() -> u64 {
  c := 1
  f := fn(n : u64) -> u64 { return n + c }
  return twice(f, 20)
}
