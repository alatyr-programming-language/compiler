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
  x := 5
  print("v=[{}]\n", -x)
  42
}
