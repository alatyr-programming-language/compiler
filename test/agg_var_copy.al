## e2e (aggregate-var COPY `x := <struct/enum var>`). Binding a fresh local from a struct/enum VAR was
## a 1-word SCALAR copy (dropping the other words); now it word-copies the whole aggregate. `q := p`
## copies the 3-word struct (q.x + q.y = 40 + 2 = 42). The enum arm (`aa := a` in a helper) is also
## covered by comptime_enum_eq's derive shape — here the struct path is the focused guard. A source
## LOCAL copies from its slots; a by-ref PARAM copies through its pointer (down-growing).
P := struct { x : u64, y : u64, z : u64 }
main := fn() -> u64 {
  p := P(x = 40, y = 2, z = 100)
  q := p
  return q.x + q.y
}
