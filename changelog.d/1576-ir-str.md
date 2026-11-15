- **The shared IR builds `str` values: literals, `.len`, `s[i]`, and `str` parameters, arguments and
  results (#1576).** A `str` is the two-word view of its bytes, a literal's bytes addressed read-only.
  `s[i]` now checks the code-point boundary as well as the range, so an index into the middle of a
  multi-byte character traps (Stdlib appendix §3.6; #1550) wherever the function is built from the IR;
  x86_64 answered the continuation byte before. On aarch64, riscv64 and wasm, whose legacy emitters
  build no `str` value at all and trapped on every one, a function that uses `str` literals and locals
  is now built from the IR and answers; a function with `str` in its signature, and a call to one,
  stays with the legacy emitter there (its convention is not measured), so it still traps. A `for`
  over a `str`, an `embed(path)` literal, a re-slice of a `str`, and a literal holding `\u{…}` or an
  escape Grammar §2.4 does not list (the parser still misreads those, #1676) are not built yet.
