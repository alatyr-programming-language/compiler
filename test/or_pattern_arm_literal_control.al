## Control Flow §5.4 — the over-rejection control for #673. The SAME two bodies are written as two
## SEPARATE arms instead of one OR-pattern group, so their string literals are two DISTINCT nodes
## that must keep two DISTINCT `.Lstr` cells. Deduplicating by literal TEXT, or by the arm's position
## rather than by the body NODE, collapses them; the surviving reference to the dropped cell is then
## an undefined symbol at link time, which is how this fixture fails. `E.C` takes the third arm:
## prints `two` and returns 42.
E := enum { A, B, C }

main := fn() -> u64 {
  mut e : E = E.C
  match e {
    E::A => { print("one\n") }
    E::B => { print("two\n") }
    E::C => { print("two\n") }
  }
  42
}
