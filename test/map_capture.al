## e2e (FN-6 §6.2 — a CAPTURING closure through the REAL stdlib `alloc::vec::map`). The headline
## functional pattern: `map` a `Vec(u64)` {1..6} with a closure `f := fn(x){ x * k }` that CAPTURES a
## local `k := 2` — the captured `k` must reach EVERY element (so the result is {2,4,6,8,10,12}, sum
## 42). `alloc::vec::map` is a QUALIFIED cross-module generic `map(T, U, a, s, f) -> Vec(U)`; the
## driver resolves the qualified callee (module-aware `d_find_fn_decl`), deep-CLONES it into a
## generic `__hoflam<fnpos>` carrying `k` as a trailing param, gives the clone `map`'s module identity
## (its body's bare `vec_in`/`push` still resolve in `alloc::vec`), threads `k` into the `f(v)` call in
## the loop (`f(v) -> f(v, k)`), and rewrites the one capturing call site to the clone. The clone stays
## generic → the lowerer monomorphizes it over T=u64,U=u64 with the `Vec(U)` sret path under the
## widened arity. If the capture did not reach every element the sum would differ → 42 proves it did.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  k := 2
  f := fn(x : u64) -> u64 { return x * k }
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  mut i : u64 = 1
  while i <= 6 {
    alloc::vec::push(u64, v, i).expect("push")
    i = i + 1
  }
  s := alloc::vec::as_slice(u64, ptr(v))
  mut m := alloc::vec::map(u64, u64, ptr(ar), s, f)
  ms := alloc::vec::as_slice(u64, ptr(m))
  mut sum : u64 = 0
  mut j : usize = 0
  while j < ms.len {
    sum = sum + ms[j]
    j = j + 1
  }
  u64(sum)
}
