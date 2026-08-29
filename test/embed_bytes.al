## e2e — the `embed(comptime path : str)` comptime file-embed builtin (Comptime §2.4 / appendix §160 /
## Assembly §9). `embed("path")` bakes the file's exact bytes into the program as a read-only byte
## sequence: `.len` is the file's byte length N and `bytes(embed(...))[i]` is byte i. The fixture
## `test/embed_fixture.bin` is the 4 BINARY bytes [0x00, 0xFF, 0x41, 0x0A] — a NUL, a high byte, 'A',
## and a newline — proving the embed is byte-EXACT and binary-safe (no `.ascii`-escaping loss). The
## path resolves relative to the compiler's CWD; e2e runs from the repo root, so `test/…` is correct.
## Failure-first formatter evidence: on parent `f98c62f`, `seed/alatyr fmt test/embed_bytes.al` returned
## rc=1, wrote 0 stdout bytes and 91 stderr bytes, with `selfhost: fmt — embed("…") is not modelled: the
## node keeps the file BYTES, not the path`. The focused formatter row now proves the path survives.
## `run_x86` (the byte-read surface — `bytes()[i]` `movzbq` — is x86-shaped; other arches are a
## follow-up). Returns 42 iff length, every byte, and the byte sum (0+255+65+10 = 330) all match.
## The byte probes below are kept as standalone documentation so the formatter's comment-preservation
## check covers them without depending on unsupported inline-comment placement inside a block.
## NUL — a bare .ascii would truncate here; high byte; 'A'; newline.
main := fn() -> u64 {
  e := embed("test/embed_fixture.bin")
  if e.len != 4 { return 1 }
  b := bytes(e)
  if u64(b[0]) != 0 { return 2 }
  if u64(b[1]) != 255 { return 3 }
  if u64(b[2]) != 65 { return 4 }
  if u64(b[3]) != 10 { return 5 }
  mut s : u64 = 0
  for i in 0..e.len { s = s + u64(b[i]) }
  if s != 330 { return 6 }
  return 42
}
