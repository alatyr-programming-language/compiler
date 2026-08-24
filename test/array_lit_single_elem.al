## e2e — STRUCT-WITH-ARRAY-FIELD tier: a ONE-ELEMENT array literal as a struct-constructor field
## value (`words = [42]` for a `[u64; 1]` field, parser `wsize` 1). The `emit_struct_assign` field
## walk gated the array-literal store on `wsize > 1`, so a length-1 array field fell to the SCALAR
## path — a bare `ArrayLit` has no frame home and emitted `$0`, a SILENT zero (multi-element array
## fields, `wsize > 1`, were unaffected — see uint192.al). Exposed by TYP-10 (`uint(64)` is a
## one-word instance). Result: s.words[0] must be the stored 42, not 0.
S := struct { words : [u64; 1] }
main := fn() -> u64 {
  s := S(words = [42])
  s.words[0]
}
