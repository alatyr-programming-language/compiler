## #1396 — an `if` operand of `==` whose value is a multi-word enum the comparison routing does not
## classify (its first branch is a local, not a constructor or a call). By Stdlib appendix §2.6 the
## comparison is true; the x86_64 lowering cannot route it to the structural `eq` yet, so it must stop
## with the `if`'s source line rather than compare word 0 against the `$0` a multi-word constructor
## materializes as (the parent builds it, and answers 11).

E := enum { U, A(u64), T(u8, u64) }

main := fn() -> u64 {
  c := true
  x := E.T(4, 5)
  w := E.U
  if not ((if c { x } else { w }) == E.T(4, 5)) { return 11 }
  42
}
## expect: reject "operand with a multi-word struct/enum value is not yet supported"
