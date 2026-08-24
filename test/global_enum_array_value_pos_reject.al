## e2e (build_reject) — an ENUM-element ARRAY GLOBAL element used in a VALUE position (here a call
## ARGUMENT) must FAIL LOUD, never compile. The element is `1 + max-payload` words; the generic global
## array read emits ONE indexed word load at `LABEL + i*8`, i.e. a word from the MIDDLE of the element
## passed off as the whole enum — a silent wrong-discriminant / garbage-payload read. The supported
## shapes claim the Index before `emit_gas` ever sees it (`e := GE[i]`, `match GE[i]`).
E := enum { N, A(u64) }
mut GE := [E.A(1), E.N]
f := fn(e : E) -> u64 { match e { E::N => { 0 } E::A(n) => { n } } }
main := fn() -> u64 { f(GE[0]) }
