## Proposal #4 / Memory §7 — bind a bytes view over a module-global str and
## index the bound view. The expected byte at index 2 is '*' = 42.
ALPHA := "()*+"

main := fn() -> u64 {
  d := bytes(ALPHA)
  mut i : usize = 2
  u64(d[i])
}
