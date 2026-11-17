pub E := enum { A, B(u64), C(u64, u64) }
pub mk := fn() -> E { E.C(40, 2) }
pub get := fn(q : ptr(E)) -> ptr(E) { q }
