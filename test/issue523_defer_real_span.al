## e2e (issue #523) — the REAL-SPAN half of the location predicate, and the control for
## `issue523_defer_synth_span.al`. That file is this one with a `defer ` in front of the cleanup call,
## which routes the statement through the parse-time desugar and therefore through a synthesized
## callee span; here the very same call stands on its own, so its callee span is an ordinary lexer
## token span, well inside the source buffer.
##
## Both files must be refused at the SAME line: `ast::span_is_synthetic` has to classify the
## synthesized span as having no source position (so that diagnostic re-attributes to the surface
## construct on that line) and this one as having one (so it is reported directly). A predicate that
## answered "synthetic" for everything would still stop the trap while silently unlocating every
## diagnostic in the compiler, and this control is what rules that out.
##
## The headers of the two files are deliberately the same number of lines so the expected line number
## is literally the same number, and the e2e row asserts it for both. Kept as its own fixture rather
## than folded into the other one because a program is refused once: one diagnostic, one measurement.
##
## The refusal itself is the ordinary Types §9.4 definite-assignment rule and predates this issue.
g := fn(x : u64) -> u64 { return x }
main := fn() -> u64 {
  mut u : u64
  g(u)
  u = 1
  return 0
}
