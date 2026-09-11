## Control Flow §5.4 — an OR-pattern arm whose body holds a STRING LITERAL (#673). The alternatives
## are surface sugar: the parser expands `p | q => body` into one arm per alternative, all carrying
## the SAME body node, so every data walk reached that body twice and defined `.Lstr<m>_<n>` twice.
## `as` refused the object ("symbol `.Lstr14_1' is already defined") while `check` reported rc 0.
## The `.rodata` cell belongs to the literal NODE, not to the control-flow path that reaches it, so
## the walk visits the shared body once. `E.B` takes the group arm: prints `two` and returns 7.
E := enum { A, B, C }

main := fn() -> u64 {
  mut e : E = E.B
  match e {
    E::A => { print("one\n") }
    E::B | E::C => { print("two\n") }
  }
  7
}
