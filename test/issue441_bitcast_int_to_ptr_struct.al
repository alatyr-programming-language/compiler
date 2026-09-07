## e2e / issue #441 — Types §4.4 — the POINTER-TO-USER-TYPE half of the same reinterpret.
##
## `bitcast(ptr([mut] <UserType>), n)` is the parser's OTHER preserved pointer shape (it keeps the
## full target span so a local bound from it can be typed as a pointer-to-struct). It reached the same
## aarch64/riscv64 stub as the sub-word pointee shape, so it trapped there too — a different parse
## arm, one lowering, and the fixture asserts both arms rather than assuming they share a path.
##
## The pointee is never dereferenced: the null base is inert and only the outer struct's scalar fields
## are read, so this measures the reinterpret and nothing about pointee layout.
##
## The wasm backend still refuses this shape (its own stub, a clean trap the sweeps accept) while it
## already lowers the sub-word pointee spelling — so this file deliberately carries no wasm assertion.
##
## 42 means both arms lowered; each miss owns its own code, both below 126.
Node := struct { v : u64, n : u64 }
Slot := struct { at : ptr(mut Node), tag : u64, len : u64 }
RoSlot := struct { at : ptr(Node), tag : u64, len : u64 }

tag_of := fn(s : Slot) -> u64 { return s.tag }

ro_tag_of := fn(s : RoSlot) -> u64 { return s.tag }

main := fn() -> u64 {
  mp := unchecked bitcast(ptr(mut Node), usize(0))
  m := Slot(at = mp, tag = 5, len = 0)
  if tag_of(m) != 5 { return 20 }
  rp := unchecked bitcast(ptr(Node), usize(0))
  r := RoSlot(at = rp, tag = 6, len = 0)
  if ro_tag_of(r) != 6 { return 21 }
  return 42
}
