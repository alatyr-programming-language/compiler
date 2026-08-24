## e2e (COMPTIME CONSTRAINT PREDICATES — CT §4.1/§4.2). Inside a monomorphized instance the concrete
## type of `T` is known, so a `comptime if T == <type>` folds by comparing T's name, and `and`/`or`/`not`
## compose comptime predicates. `f(u64,…)` → T == u64 true → 40; `g(u32,…)` → `not (T == u64) and
## verify.checked` = true and true → 2. 40 + 2 = 42. Confirms only the taken branch is emitted (the other
## branch's body is never lowered).
f := fn(T : type, x : T) -> u64 {
  comptime if T == u64 { return 40 } else { return 0 }
}
g := fn(T : type, x : T) -> u64 {
  comptime if not (T == u64) and verify.checked { return 2 } else { return 0 }
}
main := fn() -> u64 {
  a : u64 = 1
  b : u32 = 1
  return f(u64, a) + g(u32, b)
}
