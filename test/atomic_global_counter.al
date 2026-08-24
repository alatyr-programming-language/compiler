## e2e — the canonical SHARED ATOMIC COUNTER: a mutable module global + atomics compose. `ptr(CTR)`
## takes the address of the `.data` global (`leaq LABEL(%rip)`), and `atomic::fetch_add` on it updates
## the SAME cell from a separate function. Two bumps (30 + 12) accumulate to 42 (single-threaded here,
## but the codegen is the real atomic RMW). Exercises address-of-a-mutable-global through `ptr(...)`.
mut CTR := 0
bump := fn(n : u64) {
  p := ptr(CTR)
  atomic::fetch_add(p, n, Ordering.seq_cst)
}
main := fn() -> u64 {
  bump(30)
  bump(12)
  p := ptr(CTR)
  atomic::load(p, Ordering.acquire)
}
