## e2e (issue #523) — a LOCATED diagnostic whose offending expression is a node the `defer` DESUGAR
## built. `defer <expr>` becomes the marker call `__defer(<expr>)`, and `parser::synth_ident_span`
## gives that callee a span which is NOT a source offset: it is the AST-arena address of the written
## name, rebased modularly to `base_abs - src`, so `(src + s)` recovers the NAME while `s` itself sits
## outside the source buffer (here below it, so `s` is a near-`usize`-max value).
##
## The marker is the ROOT expression of this statement, so the Types §9.4 definite-assignment refusal
## below reports the marker's own span. Measured on the parent (71ea8df): the span encode `s * 4` in
## `sema::unbound_err` overflowed and trapped — SIGILL, rc=132, and NOT ONE BYTE of stderr, so the
## user got no diagnostic at all. `build_reject` alone would have called that a pass, which is why the
## e2e row asserts rc=1, a non-empty stderr, and the exact located text on all four surfaces.
##
## `ast::span_is_synthetic` now classifies the marker's span as having no source position, and the
## attribution falls back to the desugar's own ARGUMENT — the cleanup the programmer wrote, which is on
## the line of the `defer` keyword. `issue523_defer_real_span.al` is this file with the `defer ` removed
## and the same header length, so the two must name the SAME line: one through a synthesized span, one
## through a real one.
g := fn(x : u64) -> u64 { return x }
main := fn() -> u64 {
  mut u : u64
  defer g(u)
  u = 1
  return 0
}
