## e2e — issue #1416 control: a `brand` over a STRUCT keeps its fields (Types §5.4: a brand changes identity,
## never representation). `get` reads two fields of a struct-brand parameter; it is compiled though not
## called. This is the legal side the scalar-brand refusal must leave alone, and it compiles on the parent.
P := struct { a : u64, b : u64 }
Q := brand(P)
get := fn(q : Q) -> u64 {
  q.a + q.b
}
main := fn() -> u64 {
  21
}
## expect: run 21
