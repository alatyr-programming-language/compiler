## The two-word VIEW (`{ptr, len}`) as a DISCARDED call's argument — the shape the statement-position
## defect was first blamed on. It always worked and must keep working: the fault was the callee's
## NAME resolution, not the argument's representation. Locks the argument setup of a discarded call
## against the value-position one (`n := sink(v)` below emits the same setup).
mut CNT : u64 = 0
sink := fn(b : Slice(u8)) -> u64 { CNT = CNT + b.len return 1 }
main := fn() -> u64 {
  s : str = "abcd\n"
  v := bytes(s)
  sink(v)                 ## a `Slice(u8)` LOCAL, statement position
  mut i : u64 = 0
  while i < 2 {
    sink(v)               ## inside a `while` body
    i = i + 1
  }
  if i == 2 {
    sink(v)               ## inside an `if` branch
  }
  n := sink(v)            ## value position
  return CNT + 17
}
