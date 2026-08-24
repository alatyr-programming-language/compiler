## FN-6 — a CAPTURING closure that escapes as a VALUE but NOT into a specializable HOF argument is
## still unsupported → reject fail-loud, NOT a silent miscompile. Here `f` is STORED in another local
## (`g := f`), so there is no HOF call to monomorphize over the concrete closure type; calling through
## the stored value would need the type-erased `dyn` fat value (§6.3, out of scope). (A capturing
## closure passed as a VALUE ARGUMENT to a non-forwarding/loop HOF — `twice(f, 20)` — IS supported now:
## see twice_capture. A forwarding HOF `app(g, x){g(x)}` is inlined: see lambda_capture_via_apply.)
main := fn() -> u64 {
  c := 1
  f := fn(n : u64) -> u64 { return n + c }
  g := f
  return g(20) + c
}
