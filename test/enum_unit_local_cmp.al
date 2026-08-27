## e2e (Types §6.2 / Comptime §5.5 / Stdlib §2.6) — a payload-less enum is exactly its discriminant.
## Direct == and != between concrete local values must compare that complete one-word value. On parent
## 9bc329b, x86_64 returns 42 while AArch64 and RV64 trap at their aggregate-comparison guards. The
## payload-bearing enum control remains in test/agg_cmp_not_address.al and must stay fail-loud.
E := enum { A, B }

main := fn() -> u64 {
  a := E.A
  b := E.A
  c := E.B
  if a != b { return 1 }
  if a == c { return 2 }
  if not (a != c) { return 3 }
  if not (b == a) { return 4 }
  42
}
