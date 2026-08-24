## e2e — §2 operator overloading where the operator RETURNS the user type (the natural arithmetic
## shape `T + T -> T`), and the results CHAIN. `@inline +` over `Num` builds a new `Num`; `(a + b) + c`
## routes both adds through it — the inner result feeds the outer operator's operand. Each routed Bin
## delivers its 1-word aggregate via the struct-return convention, and `r := (a + b) + c` is sized as
## `Num` (operator-return-type inference) so `r.v` reads the field. 20 + 15 + 7 -> 42.
Num := struct { v : u64 }
@inline + := fn(a : Num, b : Num) -> Num { Num(v = a.v + b.v) }
main := fn() -> u64 {
  a := Num(v = 20)
  b := Num(v = 15)
  c := Num(v = 7)
  r := (a + b) + c
  r.v
}
