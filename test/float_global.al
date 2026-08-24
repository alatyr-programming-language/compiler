## e2e — a FLOAT-valued mutable global (`mut F := 40.0`). Its .data cell is a `.double` (IEEE-754 bits,
## not a .quad int); is_float_expr/value_is_float recognize the global Var so reads + arithmetic take
## the float (xmm) path, and the write stores the result bits back. F = 40.0 + 2.0 = 42.0; u64(F) = 42.
mut F := 40.0
main := fn() -> u64 {
  F = F + 2.0
  u64(F)
}
