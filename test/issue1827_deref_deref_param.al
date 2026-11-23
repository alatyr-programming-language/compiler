## e2e / issue #1827 — the issue's own program, verbatim: `deref(deref(p)).b` with `p : ptr(ptr(Node))`.
##
## NON-VACUOUS: on the Stage1 of `a5fc9766` and the 0.6.0 seed (omen, x86_64) it answered 0, the field
## read lowered as the constant `movq $0, %rax`. At `dc9e18e2` it answers 42 on the default x86_64 path
## and on aarch64, riscv64 and wasm.
Node := struct { a : u64, b : u64 }
rd := fn(p : ptr(ptr(Node))) -> u64 { deref(deref(p)).b }
main := fn() -> u64 {
  mut u : Node = Node(a = 1, b = 42)
  mut pu : ptr(Node) = ptr(u)
  rd(ptr(pu))
}
## expect: run 42
