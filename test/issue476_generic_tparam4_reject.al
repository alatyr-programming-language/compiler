## Regression for #476 AT the threshold: a call to a generic fn with FOUR comptime type parameters is
## REFUSED instead of compiling cleanly to a wrong answer. Measured on parent 2abfe57, x86_64: this
## exact program built rc=0, linked, exited normally and answered **0** where 42 was due.
##
## Mechanism, read off the parent's own GAS. The monomorphization machinery carries three type
## arguments, so `emit_call_dispatch` erased three of the four leading ones and the fourth type NAME
## stayed in the runtime argument list. `emit_call_args` then evaluated `u64` as if it were a
## variable, read the unwritten frame slot it resolves to, and passed THAT as value argument 0:
##
##     movq -8(%rbp), %rax          <- an unwritten slot, not $42
##     movq %rax, %rdi
##     call arity4__pick4__u64__u64__u64   <- three tags for four type arguments
##
## while the instance's own prologue read its first value parameter from `%rsi`, one register past
## where the caller had put anything. The real `42` was never passed at all.
##
## The other three backends already refused the identical shape through `lower_layout::gen_call_ok`
## (measured on the same parent: aarch64 `ld` undefined reference to `arity4__pick4`, riscv64 SIGTRAP
## 133, wasm `wat2wasm` "undefined function variable"), so x86_64 was the only wrong backend of the
## four; this refusal makes them agree. The arity-3 CONTROL fixture beside this one stays green, so
## the fence is about the fourth type argument and not about generic calls.
pick4 := fn(T1 : type, T2 : type, T3 : type, T4 : type, v : T1) -> T1 {
  return v
}

main := fn() -> u64 {
  return pick4(u64, u64, u64, u64, 42)
}
