## e2e — the `embed(comptime path : str)` comptime file-embed builtin (Comptime §2.4 / appendix §160 /
## Assembly §9). `embed("path")` bakes the file's exact bytes into the program as a read-only byte
## sequence: `.len` is the file's byte length N and `bytes(embed(...))[i]` is byte i. The fixture
## `test/embed_fixture.bin` is the 4 BINARY bytes [0x00, 0xFF, 0x41, 0x0A] — a NUL, a high byte, 'A',
## and a newline — proving the embed is byte-EXACT and binary-safe (no `.ascii`-escaping loss). The
## path resolves relative to the compiler's CWD; e2e runs from the repo root, so `test/…` is correct.
## `run_x86` (the byte-read surface — `bytes()[i]` `movzbq` — is x86-shaped; other arches are a
## follow-up). Returns 42 iff length, every byte, and the byte sum (0+255+65+10 = 330) all match.
main := fn() -> u64 {
  e := embed("test/embed_fixture.bin")
  if e.len != 4 { return 1 }
  b := bytes(e)
  if u64(b[0]) != 0 { return 2 }         ## NUL — a bare .ascii would truncate here
  if u64(b[1]) != 255 { return 3 }       ## high byte
  if u64(b[2]) != 65 { return 4 }        ## 'A'
  if u64(b[3]) != 10 { return 5 }        ## newline
  mut s : u64 = 0
  for i in 0..e.len { s = s + u64(b[i]) }
  if s != 330 { return 6 }
  return 42
}
