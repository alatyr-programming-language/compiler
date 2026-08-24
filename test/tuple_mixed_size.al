## CLAYOUT S2 — a mixed tuple uses standard product padding. The u8 component
## makes the tuple 16 bytes: u64 at offset 0, u8 at offset 8, tail padding to 8.
main := fn() -> u64 {
  sz := size((u64, u8))
  al := align((u64, u8))
  if sz == 16 and al == 8 { 42 } else { 1 }
}
