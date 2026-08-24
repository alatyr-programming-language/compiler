## Proposal #4 / Memory §7 — initialize a module global from bytes(str), then
## index it. The expected byte at index 2 is '*' = 42.
ALPHA := bytes("()*+")

main := fn() -> u64 {
  mut i : usize = 2
  u64(ALPHA[i])
}
