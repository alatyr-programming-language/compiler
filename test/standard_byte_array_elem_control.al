## CLAYOUT S3(d) — THE CONTROL. The two array kinds the byte-precise element tier must NOT capture,
## measured beside the ones it does:
##
##   a WORD-GRANULAR struct element (`struct { x : u64, y : u64 }`) — every field is 8 bytes wide and
##     8-aligned, so its §6.1 offsets ARE its word offsets times 8 (the audit §5 staging principle) and
##     it keeps the pre-existing word-denominated element addressing, byte-identically.
##   a plain `[u8; N]` BYTE array — its own tier (`eek` 8, raw byte index, stride 1) and completely
##     untouched by the element tier, which only ever fires for a struct element.
##
## Both are exactly the emission that existed before this slice; a change in either is a regression,
## not a win. `standard_byte_array_elem*.al` carry the shapes that DO change.
##
## Every comparison is INSIDE the program; every value is < 126.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   S3(c) as landed (dd10312)   42 / 42 / 42 / 42
##   S3(d), this commit          42 / 42 / 42 / 42   (unchanged, which is the point of the fixture)
Word := struct { x : u64, y : u64 }
main := fn() -> u64 {
  ## the word-granular struct element array — the pre-existing path
  mut ws : [Word; 3]
  ws[0] = Word(x = 20, y = 22)
  ws[1] = Word(x = 24, y = 26)
  ws[2] = Word(x = 28, y = 30)
  if ws[0].x != 20 { return 1 }
  if ws[0].y != 22 { return 2 }
  if ws[1].x != 24 { return 3 }
  if ws[1].y != 26 { return 4 }
  if ws[2].x != 28 { return 5 }
  if ws[2].y != 30 { return 6 }
  ws[1] = Word(x = 32, y = 34)
  if ws[1].y != 34 { return 7 }
  if ws[0].y != 22 { return 8 }
  if ws[2].y != 30 { return 9 }
  ws[2].y = 36
  if ws[2].y != 36 { return 10 }
  if ws[2].x != 28 { return 11 }
  ## NOTE `w := ws[1]` — a whole-element copy OUT of a word-granular struct array — is deliberately
  ## NOT here: measured on this same base (dd10312) it TRAPS under wasmtime (exit 134) on the plain
  ## `struct { x : u64, y : u64 }` element, with x86_64/aarch64/riscv64 all answering 42. That is a
  ## pre-existing wasm gap in the WORD-granular element path, outside this slice, and a trap is not an
  ## I11 violation — but a bare `run` line here would fail the wasm sweep for a reason this slice did
  ## not create. The byte-tier equivalent is covered by `standard_byte_array_elem_copy.al`.

  ## the plain byte array — its own tier, stride 1
  mut bs : [u8; 6]
  bs[0] = 1
  bs[1] = 2
  bs[2] = 3
  bs[3] = 4
  bs[4] = 5
  bs[5] = 6
  if u64(bs[0]) != 1 { return 14 }
  if u64(bs[3]) != 4 { return 15 }
  if u64(bs[5]) != 6 { return 16 }
  bs[3] = 9
  if u64(bs[3]) != 9 { return 17 }
  if u64(bs[2]) != 3 { return 18 }
  if u64(bs[4]) != 5 { return 19 }
  mut i := 0
  mut acc := 0
  while i < 6 {
    acc = acc + u64(bs[i])
    i = i + 1
  }
  if acc != 1 + 2 + 3 + 9 + 5 + 6 { return 20 }
  42
}
