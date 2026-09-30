## #683 — an AGGREGATE ARRAY ELEMENT passed as a call argument must be passed BY REFERENCE on the emit
## twins too (Functions §1.4 / Types §6.4; the x86_64 half is `agg_arr_elem_arg`). aarch64 and riscv64
## sent the element through the scalar path, which loads its FIRST WORD (at a one-word stride), and the
## callee dereferenced that value as the struct pointer: `take(ps[0])` died with SIGSEGV (139) where
## x86_64 and wasm answer. The by-ref `[P; 2]` PARAM and `Slice(P)` shapes of `agg_arr_elem_arg` are
## still unlowered there (a located trap), so this fixture keeps to the local-array shapes that now run.
P := struct { x : u64, y : u64 }
Q := struct { x : u64 }
take := fn(p : P) -> u64 { p.x + p.y }
takeq := fn(q : Q) -> u64 { q.x }
second := fn(k : u64, p : P) -> u64 { k + p.x + p.y }
main := fn() -> u64 {
  ps : [P; 2] = [P(x = 1, y = 2), P(x = 3, y = 4)]
  mut acc : u64 = 0
  acc = acc + take(ps[0])          ## constant index, multi-word element  -> 3
  mut i := 1
  acc = acc + take(ps[i])          ## runtime index                       -> 7
  qs : [Q; 2] = [Q(x = 5), Q(x = 2)]
  acc = acc + takeq(qs[1])         ## ONE-word struct element             -> 2
  acc = acc + second(23, ps[1])    ## NON-FIRST argument position         -> 30
  return acc
}
