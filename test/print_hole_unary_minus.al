## e2e (four-backend TEXT agreement) — a `{}` hole filled by a BARE UNARY-MINUS expression.
##
## Issue #486. The parser desugars unary minus to `Unchecked(Bin(17 /* - */, Num(0), x))` (`p_factor`,
## so the negation lowers as guard-free 2's-complement rather than tripping the checked `-` underflow
## guard). The x86_64 hole expansion in `lower::emit_variadic_print` tests a chain of shapes, and every
## one of them looked THROUGH that wrapper's outer kind: `expr_type_span` and `variadic_hole_type_span`
## give no span, it is not a `str`/float/scalar-`Var` hole, `expr_is_numlit` wants a bare `Num`, and
## `expr_is_arith_bin` wants an outer `Expr::Bin`. No arm matched, so the hole emitted ZERO bytes and
## rendered as the EMPTY string — `print("a=[{}]\n", -4)` printed `a=[]` — on a program that compiled
## cleanly and still exited 42. The exit code was never wrong, which is why no exit-code gate stage
## could see it (the #444 blindness) and why this fixture asserts the exact STDOUT on all four
## backends instead. The `0 - 4` spelling parses as a bare `Expr::Bin`, hit the arithmetic arm and was
## always correct, so two spellings of one value disagreed by 4 bytes of output.
##
## Specification basis, pinned revision `b4e7979`: Functions §7.1 routes every `{}` hole through the
## scalar rendering layer and gives a hole with no other type the default numeric type `i64`; Stdlib
## appendix §2 fixes that layer's integer form as "an integer in base-10 (a leading `-` for a negative
## two's-complement value, minimal digits, `0` for zero)". The empty string is not one of the permitted
## renderings, and emitting nothing while reporting success is the forbidden silent class (I11 / #464).
##
## After #457 the aarch64, riscv64 and wasm backends already rendered BOTH spellings correctly — they
## route this hole on `lower_layout::lit_arith_i64`, which peels the `unchecked` wrapper because
## `unchecked` is a VERIFICATION mode and never a type. x86_64 was therefore the divergent surface for
## this one spelling, and it now reads that same predicate. The assertion is one golden compared on all
## four backends (`run_x86_out` + `run_a64_out` + `run_rv64_out` + `run_wat_out` against
## `test/print_hole_unary_minus.out`), so "the four backends agree" is a fact about one set of bytes.
##
## `neg_min` is `i64::MIN`, which has NO positive counterpart: a renderer that negates before
## converting overflows exactly there, and read as unsigned its magnitude is 2^63. The three `ctl_`
## rows are the spellings that were ALREADY correct and must not move — the binary `0 - 4`, a bare
## positive literal, and `i64::MIN` written without the prefix.
main := fn() -> u64 {
  print("neg {}\n", -4)
  print("neg_min {}\n", -9223372036854775808)
  print("neg_zero {}\n", -0)
  print("neg_nested {}\n", - -4)
  print("unchecked_bin {}\n", unchecked (2 + 3))
  print("ctl_bin {}\n", 0 - 4)
  print("ctl_pos {}\n", 7)
  print("ctl_min_bin {}\n", 0 - 9223372036854775807 - 1)
  42
}
