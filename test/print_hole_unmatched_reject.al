## e2e (x86_64 located reject) — the NON-VACUITY test for the `{}`-hole expansion's terminal arm.
##
## Issue #486 / class #464. `lower::emit_variadic_print` renders each `{}` hole by walking a chain of
## shape arms. The chain used to END with the last arm, so an argument no arm recognised contributed
## ZERO bytes: the hole rendered as the empty string while the statement, the enclosing call and the
## process exit code all reported success. That is the forbidden silent class (I11), and it is exactly
## what every gate stage that reads an exit code is blind to. The chain now ends in a LOCATED refusal.
##
## `-x` over an un-annotated local is the cheapest argument that still reaches it. The parser desugars
## unary minus to `Unchecked(Bin(17, Num(0), Var(x)))`, and none of the chain's shape tests accepts
## that node: there is no type span to read, it is not a `str`/float/scalar-`Var` hole, `expr_is_numlit`
## needs a bare `Num`, `expr_is_arith_bin` needs an outer `Expr::Bin`, and `lit_arith_i64` needs every
## leaf to be an integer LITERAL — `x` is a name, so its static type is not written anywhere the
## expansion reads. Rendering it would require the type layer, so per AGENTS.md ("a trap is acceptable;
## a wrong value is not — if correctness cannot be completed, leave a located reject") it is refused
## with the offending source line, rather than printed as nothing.
##
## This row is what keeps the terminal arm from being vacuous: with the arm removed this program
## compiles, runs, exits 42 and prints `[]`. Measured on the parent, and measured again with the arm
## made to fail on entry: the compiler's own `src/` + `lib/` self-emit, all tracked `test/*.al` and the
## remaining tracked `.al` files never reach it, so the arm changes no emitted byte anywhere else.
##
## RESIDUAL, tracked separately (#489): the three non-x86 backends do not refuse this program — they
## render `-x` as the unsigned 64-bit magnitude `18446744073709551611`, and a negated float as its
## bit pattern read as an integer. Those are wrong values on a clean compile, a different defect from
## the empty rendering this file pins, and neither is changed here. When the hole expansion can resolve
## a negated NAME's type, this fixture is replaced by a rendering assertion — it pins today's refusal,
## not a permanent language rule.
main := fn() -> u64 {
  y : f64 = 1.5
  print("v=[{}]\n", -y)
  42
}

## MOVED at #1049, and the reason is the point. This file used to write `-x` over an un-annotated INT
## local. The desugar no longer wraps the negation in `Expr::Unchecked`, so the chain now SEES the
## `Bin`, and `print_one_int` renders it exactly: `print("{}", -x)` answers `v=[-5]`, measured. That is
## no longer a refusal to pin, and this file's own closing paragraph said what to do when the expansion
## can resolve a negated name — write a rendering assertion instead. `test/print_hole_neg_name_render.al`
## is that assertion. What still reaches the terminal arm is a negation over a FLOAT: the chain finds a
## float hole by the argument's NAME, and a `Bin` has none, so without a refusal it prints the `f64` bit
## pattern as an integer (`-4613937818241073152`, measured) — a silent wrong value, the forbidden outcome.
## `lower::hole_arith_float_operand` refuses it, loudly and located, until #489 gives the expansion a
## type for negated expressions. The non-vacuity of the terminal arm is preserved, on a harder shape.
