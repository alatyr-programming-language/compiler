## e2e (Types §9.4 / Memory §3.5 — the `str` FIELD **value** paths). `str_field_struct` locks the
## LITERAL-initialized, LEADING (`fwo == 0`) str field; this locks the corners it left open, each of
## which was a SILENT MISCOMPILE (a normal exit with a wrong answer, never a diagnostic) — plus one
## bare compiler SIGILL:
##   1. a str field at a NON-ZERO word offset (`G { n : u64, name : str, … }`) — the read applied the
##      field's word offset with the WRONG SIGN (`base + fwo` instead of `base - fwo`; a struct local's
##      slots DESCEND as the word index rises), so `a.name.len` returned a neighbouring field's word.
##   2. a str field initialized from a NON-LITERAL value (a str `Var`, a `str` PARAM, a range-slice
##      VIEW) — the literal-only store emitted NOTHING, so both words stayed 0 and `.len` read 0.
##   3. a struct carrying a str field RETURNED BY VALUE — the per-field return-register delivery pushed
##      a non-literal str field as ONE word, so the caller read a garbage/zero length.
##   4. `c := a.name` — the str FIELD bound to a LOCAL was sized as a scalar and copied word 0 only, so
##      `c.len` read an uninitialized slot. Through a BY-REFERENCE struct param (`byref` below) the
##      same binding made the COMPILER trap: a bare `ud2` SIGILL (exit 132) with no diagnostic, because
##      the copy read the POINTER slot as if it were the struct's own frame words.
##   5. `str_eq(a.name, …)` — the str field used as a str VALUE matched no `emit_str_pair` arm and fell
##      to its `_` default (`pushq $0` twice) = an EMPTY string, so every comparison was false.
## Every reader mixes the str's `.len`/content with the scalar fields on BOTH sides of it, so a dropped
## word, a wrong-sign offset or a truncated return all change the answer.
## Values: (3 + 1 + 2) + (2 + 1 + 2) + 3 + (3 + 4) + 8 + (3 + 1 + 2) = 6 + 5 + 3 + 7 + 8 + 6 = 35.
## NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
G := struct { n : u64, name : str, m : u64 }

## a str field fed from a str PARAM, in a struct RETURNED BY VALUE (3 words: n, {ptr,len}, m)
mk := fn(s : str) -> G {
  return G(n = 1, name = s, m = 2)
}

## the str field of a BY-REFERENCE struct param bound to a local (was a compiler SIGILL)
byref := fn(g : G) -> u64 {
  c := g.name
  return c.len + g.n + g.m
}

main := fn() -> u64 {
  x := "abc"
  a := G(n = 1, name = x, m = 2)          ## str field from a VAR
  r := mk("hi")                           ## str field from a PARAM, delivered through the return regs
  c := a.name                             ## the str FIELD bound to a str LOCAL (2-word extract)
  s := "wxyz"
  b := G(n = 4, name = s[1..4], m = 0)    ## str field from a range-slice VIEW ("xyz")
  mut eq := 0
  if str_eq(a.name, "abc") { eq = 8 }     ## the str field as a str VALUE (was always "")
  if str_eq(a.name, "abd") { eq = eq + 1 }
  return (a.name.len + a.n + a.m) + (r.name.len + r.n + r.m) + c.len + (b.name.len + b.n) + eq + byref(a)
}
