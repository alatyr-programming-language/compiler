## e2e — x86_64 SHIFT + BITWISE instruction intrinsics (spec 130-grammar §OP-2: bit shifts/rotations
## are OPERATIONS in call/UFCS form, NOT glyph operators — there is no `<<`/`>>` glyph). Each mutates
## its first arg (a scalar local lvalue) in place, like the arithmetic intrinsics. `shlq`/`shrq` are
## logical shifts, `sarq` is arithmetic (sign-preserving); the count rides `%cl`. `andq`/`orq`/`xorq`
## are the register bitwise ops. Additive — `src/` names none of these, so the fixpoint is unaffected.
main := fn() -> u64 {
  mut x : u64 = 1
  x86_64.shlq(x, 3)                       ## 1 << 3 = 8
  mut y : u64 = 255
  x86_64.shrq(y, 4)                       ## 255 >> 4 = 15 (logical)
  mut z : i64 = 0 - 16
  x86_64.sarq(z, 2)                       ## -16 >> 2 = -4 (arithmetic, sign-preserving)
  mut w : u64 = 0xF0
  x86_64.andq(w, 0x3C)                    ## 0xF0 & 0x3C = 0x30 = 48
  mut o : u64 = 0x20
  x86_64.orq(o, 0x01)                     ## 0x21 = 33
  mut e : u64 = 0xFF
  x86_64.xorq(e, 0xF0)                    ## 0x0F = 15
  ## 8 + 15 + (-4→bitcast +4=0) + 48 + 33 + 15 = 119; then normalize to 42
  s := x + y + unchecked bitcast(u64, z + 4) + w + o + e   ## 8+15+0+48+33+15 = 119
  s - 77                                  ## 42
}
