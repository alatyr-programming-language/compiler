## §4/§8: ONE-level TUPLE-element WRITE `t.N = v` (store dual of the tuple READ `t.N`). A flat scalar
## tuple LOCAL has element N written, then read back through the working read path. t.1 and t.2 are
## OVERWRITTEN (20→99, 30→12); t.0 (10) is the NEIGHBOUR that must survive untouched.
## 10 (t.0, intact) + 99 (t.1 written) + 12 (t.2 written) - 79 = 42. (No negative intermediate — the
## checked-subtraction underflow guard traps a transient negative, so the reads sum BEFORE subtracting.)
main := fn() -> u64 {
  mut t := (10, 20, 30)
  t.1 = 99
  t.2 = 12
  u64(t.0 + t.1 + t.2 - 79)
}
