## e2e / issue #393 residual item 2 — a DEAD top-level binding whose name merely BEGINS with a
## scanned prelude trigger word must not decide whether an unrelated program compiles.
##
## `cli::ambient_paths` picks a file's ambient prelude by scanning the source TEXT. Every bare-name
## trigger in that block checks the LEADING word boundary; the fallible-result-type trigger had no
## TRAILING one, so `Result_marker_unused` — a binding declared here, never read, and of no interest
## to anything below — matched it and pulled the whole base closure in. The two names this program
## actually uses, `assert` and `min`, live in that closure and have no trigger of their own, so on
## the parent compiler this file BUILDS and RUNS 42, and the very same file with line 21 deleted is
## refused. A never-read binding's spelling was the difference between a program and a diagnostic.
##
## With the trailing boundary in place the binding is inert and this file is refused, located on the
## first name it cannot resolve. That refusal is residual item 1 of the same issue surfacing
## honestly — injection is a text scan, and `assert`/`min` are reachable by no trigger — not a new
## limit introduced here. The measured cost of the tightening was zero: over `package.al` plus every
## tracked `src/`, `lib/` and `test/` source, 885 result-type and 757 option-type trigger hits
## already carried a trailing boundary and not one fired by prefix match alone.
##
## The companion `test/bare_option_result.al` is the other direction: a genuine bare mention, in
## every spelling a real use writes, must still pull the prelude. It keeps running 42.
Result_marker_unused := 0

main := fn() -> u64 {
  assert(1 == 1)
  return min(u64, 42, 77)
}
