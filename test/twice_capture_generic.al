## FN-6 §6.2 — a CAPTURING closure passed as a VALUE to a GENERIC non-forwarding HOF. The generic
## `twice(T, g, x){ g(x) + g(x) }` calls its callable param TWICE, so the forwarding-inline can't
## help; §6.2 says generic code taking a callable MONOMORPHIZES over the concrete closure type. The
## driver specializes `twice` to THIS closure — f's capture `c` is threaded as a trailing param of
## `twice` (`g(x) -> g(x, c)`), appended at the call site (`twice(u64, f, 20) -> twice(u64, f, 20,
## c)`), and the specialized `twice` STAYS GENERIC so the lowerer monomorphizes it over T=u64. `g`
## stays a code-pointer param; f's lifted fn already takes `(n, c)`. c := 1; twice = (20+1)+(20+1)=42.
twice := fn(T : type, g : T, x : T) -> T { return g(x) + g(x) }
main := fn() -> u64 {
  c := 1
  f := fn(n : u64) -> u64 { return n + c }
  u64(twice(u64, f, 20))
}
