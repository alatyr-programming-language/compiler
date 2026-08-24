## e2e (COMPTIME enum-VARIANTS unroll). `match v { comptime for var in typeinfo(T).variants {
## T.(var)(p) => body } }` is UNROLLED into one real match arm per variant of the scrutinee's enum
## (in a mono instance), each binding the variant payload `p`. This is `base/derive`'s enum dispatch
## (D90 comptime variant match). Here `payload(E, E.A(42))` matches the `A` arm, binds `p = 42`, and
## returns it — proving the variant unroll + per-variant payload binding.
E := enum { A(u64), B(u64) }
payload := fn(T : type, v : T) -> u64 {
  comptime if (match typeinfo(T) { Enum(_) => true; _ => false }) {
    match v {
      comptime for var in typeinfo(T).variants {
        T.(var)(p) => { return p }
      }
    }
    return 0
  } else {
    return u64(v)
  }
}
main := fn() -> u64 {
  payload(E, E.A(42))
}
