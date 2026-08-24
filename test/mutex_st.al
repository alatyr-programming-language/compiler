## e2e-probe (std::sync — generic Mutex(T) mechanics, single-threaded): construct a Mutex(u64)
## guarding 40, lock it, bump the guarded value by 2 through the returned ptr(mut u64), unlock,
## then lock again and read it back = 42. Validates the generic type, the CAS fast path, the
## value-field offset, and the ptr(mut T) return with no contention.
main := fn() -> u64 {
  mut m := std::sync::new(u64, 40)
  p := std::sync::lock(u64, ptr(m))
  deref(p) = deref(p) + 2
  std::sync::unlock(u64, ptr(m))
  q := std::sync::lock(u64, ptr(m))
  v := deref(q)
  std::sync::unlock(u64, ptr(m))
  v
}
