## e2e — a FLOAT LITERAL that lives only in a function's TRAILING RETURN EXPRESSION must still get its
## rodata cell. The register backends load a float literal from `.Lflt<span-start>` (`adrp`/`la` +
## `.double`), but the rodata walk ran over `Decl.body_stmts` ONLY. A function whose whole body IS an
## expression has an EMPTY `body_stmts` and carries its expression in `Decl.value`, so its literals
## got no cell while the code still referenced the label — `ld` rejected the program on an undefined
## `.Lflt…`. That is exactly the shape of `std::math::abs`, which is why every `math_*` test was
## unlinkable on aarch64 and riscv64.
##
## `scale` below is that shape (a bare trailing expression), `pick` is the trailing-`if` shape, and
## `both` mixes a body statement with a trailing-expression literal so the two walks are exercised
## together. Also locks the boolean `not` over a float comparison — the second blocker on the same
## path, which fell through the backends' arith fallthrough to `brk #0` / `ebreak`.

scale := fn(x : f64) -> f64 { x * 2.5 }

pick := fn(x : f64) -> f64 { if x < 0.0 { 0.0 - x } else { x } }

both := fn(x : f64) -> f64 {
  y := x + 1.5
  y - 0.5
}

main := fn() -> u64 {
  eps := 0.0000001
  mut r := 0

  if pick(0.0 - 4.0) - 4.0 < eps { r = r + 1 }        ## trailing-`if` literal reached  -> +1
  if scale(4.0) - 10.0 < eps { r = r + 2 }            ## bare trailing-expr literal     -> +2
  if both(1.0) - 2.0 < eps { r = r + 4 }              ## stmt + trailing-expr literals  -> +4
  if not (0.0 < (0.0 - 1.0)) { r = r + 8 }            ## `not` over a float compare     -> +8
  if not (0.0 < 1.0) { r = r + 64 }                   ## `not` of a TRUE compare        -> +0

  r = r + 16                                          ## 1 + 2 + 4 + 8 + 16 = 31
  return r
}
