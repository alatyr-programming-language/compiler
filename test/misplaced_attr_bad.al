## §8 a layout attribute placed AFTER the `:` (`v : @offset(0) u32`) instead of the canonical PREFIX
## surface (`@offset(0) v : u32`). Formerly the type-parse captured the `@` as the type head and silently
## DROPPED the attribute (a wrong-layout miscompile); now the parser fails LOUD. This program MUST NOT
## compile — the e2e harness asserts a build rejection (build_reject).
Bad := @packed struct { v : @offset(0) u32, tail : u8 }

main := fn() -> u64 {
  b := Bad(v = 1, tail = 2)
  return u64(b.tail)
}
