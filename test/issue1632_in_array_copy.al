## e2e — #1632: an `in` array parameter is passed by reference to a COPY, and an `in out` one is the
## caller's place. Functions §4.1: "`in`, large aggregate → by reference to a copy (so the callee cannot
## mutate the caller's value)"; "`out` / `in out` → by reference to the caller's place". Memory §5.7
## imposes no mutable-XOR-shared discipline, so passing one array to both parameters is well-formed, and
## its meaning is the by-value one: the `in` parameter keeps the value it had at the call.
##
## Before #1632 the AST folded `in`, `out` and `in out` into one array mode, so the caller passed its
## own array's address to all of them. MEASURED on the parent (`774ba852`, native x86_64): x86_64
## answered 1 (the `in` parameter saw the callee's write through the `in out` one); aarch64 and riscv64
## 133 and wasm 134 (the shared IR refused the element write through any array parameter, and the
## legacy emitters' stub trapped).
##
## Every function here is built from the shared IR on every target. A caller the IR cannot build still
## passes its array's address with no copy (the legacy emitters' missing `in` aggregate copy, #1637).
## Each check below answers its own number when it fails; all passing answers 42.
## expect: run 42
mix := fn(xs : [u64; 3], in out ys : [u64; 3]) -> u64 {
  ys[0] = 100
  ys[2] = 7
  xs[0] + xs[1] + xs[2]
}
## An `in` parameter handed on to an `in` parameter is copied again; the `in out` one stays the place.
pass := fn(xs : [u64; 3], in out ys : [u64; 3]) -> u64 { mix(xs, ys) }
fill := fn(out zs : [u64; 3]) {
  zs[0] = 5
  zs[1] = 6
  zs[2] = 7
}
main := fn() -> u8 {
  mut a : [u64; 3] = [2, 20, 10]
  if mix(a, a) != 32 { return 1 }
  if a[0] != 100 or a[1] != 20 or a[2] != 7 { return 2 }
  mut b : [u64; 3] = [1, 2, 3]
  if pass(b, b) != 6 { return 3 }
  if b[0] != 100 or b[1] != 2 or b[2] != 7 { return 4 }
  mut c : [u64; 3] = [0, 0, 0]
  if mix([3, 4, 5], c) != 12 { return 5 }
  if c[0] != 100 or c[2] != 7 { return 6 }
  fill(c)
  if c[0] + c[1] + c[2] != 18 { return 7 }
  42
}
