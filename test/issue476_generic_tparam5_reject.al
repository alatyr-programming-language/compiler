## Regression for #476 one arity ABOVE the threshold: FIVE comptime type parameters is refused for the
## same reason four is, so the boundary is a floor and not a single special case. On the parent this
## also answered `0` on x86_64 while aarch64 refused at `ld`, riscv64 trapped (133) and `wat2wasm`
## refused the module -- the same asymmetry, one arity further out.
pick5 := fn(T1 : type, T2 : type, T3 : type, T4 : type, T5 : type, v : T1) -> T1 {
  return v
}

main := fn() -> u64 {
  return pick5(u64, u64, u64, u64, u64, 42)
}
