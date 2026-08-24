## SYN-4: NEWLINE-as-separator. Struct-literal fields, call args, and block statements are all
## separated by a newline with NO comma/semicolon — the comma-free one-per-line style. The lean parser
## supports this for every practical program (bracketed sequences read to their closer with the comma
## OPTIONAL; statements are delimited by grammar). (30,5)+(1,2,3) → 30+5+1+2+3 = 41 +1 = 42.
Pt := struct { x : u64, y : u64 }
add3 := fn(a : u64, b : u64, c : u64) -> u64 {
  t := a + b
  u := t + c
  u
}
main := fn() -> u64 {
  p := Pt(x = 30
          y = 5)
  r := add3(1
            2
            3)
  p.x + p.y + r + 1
}
