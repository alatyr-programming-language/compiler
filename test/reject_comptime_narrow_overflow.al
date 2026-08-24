## e2e — CT-12 covers the NARROWING guard too: the exact sum 300 is not representable in `u8`, so the
## declaration is rejected where it is written rather than silently materializing a wrapped 44
## ("no wrapped, saturated, or otherwise adjusted value is materialized in its place",
## Comptime §2.6). Located at the arithmetic (line 5).
K : u8 = 200 + 100

main := fn() -> i64 {
  return i64(K)
}
