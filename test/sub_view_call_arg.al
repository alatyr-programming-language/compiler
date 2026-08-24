## e2e (Types §7 / Stdlib §3.6 — a view VALUE with no frame home). `sub(s, start, len)` and the
## range sub-view `s[lo..hi]` produce the two-word {ptr, len} pair as an EXPRESSION; passing one
## straight to a call needs the pair materialized into a temp whose ADDRESS is handed over. Before
## the fix `emit_arg` had no arm for it: the pair was left on the machine stack and the callee got
## the LENGTH word as its by-reference block pointer — `io::print(sub(s, 0, 4))` SIGSEGV'd (exit
## 139), in statement AND value position. A `[str; N]` element and a str field of an array-of-struct
## element were the same silent family (they printed nothing).
##
## CONTENT is checked with `str_eq` against literals of DIFFERENT lengths (5/3/2/8), and one probe
## compares a sub-view against a same-length WRONG string, so neither a wrong length nor a wrong
## base pointer can pass. The last line is the POSITIVE CONTROL — a plain `str` LOCAL argument. 42.
K := struct { key : str, n : u64 }

eqs := fn(s : str, want : str) -> u64 {
  if str_eq(s, want) { return 1 }
  0
}

main := fn() -> u64 {
  s : str = "AliceBob"
  xs : [str; 2] = ["Alice", "Bo"]
  ks : [K; 2] = [K(key = "Carolyn", n = 1), K(key = "Bo", n = 2)]
  mut k : u64 = 0
  k += eqs(sub(s, 0, 5), "Alice")      ## a `sub(…)` view straight into a call
  k += eqs(sub(s, 5, 3), "Bob")        ## a non-zero start offset
  k += eqs(sub(s, 0, 5), "Alicf")      ## must be 0 — same LENGTH, different content
  k += eqs(s[0..5], "Alice")           ## a range sub-view
  k += eqs(xs[1], "Bo")                ## a `[str; N]` element
  k += eqs(ks[0].key, "Carolyn")       ## a str field of an array-of-struct element
  k += eqs(s, "AliceBob")              ## POSITIVE CONTROL — a plain `str` local
  if k == 6 { return 42 }
  k
}
