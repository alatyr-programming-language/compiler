## Regression for #476 in STATEMENT position: the refusal has to sit at BOTH of the two places
## `src/lower.al` emits a generic call, not only the value-position one. Here the four-type-parameter
## call is a statement whose result is discarded, which reaches the other emission site; on the parent
## it lowered the same shifted argument list and the program still exited 42 by luck, so a fixture
## that only checked the returned value would have declared this site healthy.
##
## A non-leading type parameter is used on purpose as well: the fourth `: type` sits after a value
## parameter, so this also covers the arrangement `lower_layout::gen_call_ok` treats separately.
p4 := fn(T1 : type, a : T1, T2 : type, T3 : type, T4 : type) -> T1 {
  return a
}

main := fn() -> u64 {
  p4(u64, 7, u64, u64, u64)
  return 42
}
