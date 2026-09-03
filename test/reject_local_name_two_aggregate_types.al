## Issue #406 — a local declared in a NESTED block and then declared again in the ENCLOSING scope
## under the same name but a different enum type. Declarations §5/§6.1 make the program valid: the two
## declarations belong to two different scopes, and the aarch64, riscv64 and WAT backends all answer
## 109 for it. The x86_64 slot map, however, keys a frame slot by NAME alone for the whole function
## and records the type of whichever binding it saw FIRST, so the later `match` resolved `Some`/`None`
## in `Result`'s variant list, found neither, and fell through taking no arm at all — `out` kept its
## `77` initializer and a clean compile answered 77 where 109 was due. It must refuse the collision
## with a located diagnostic instead. (Renaming one of the two locals is the fix at the source.)
pick := fn(flag : bool) -> usize {
  if flag {
    r := Result(usize, u32).Ok(7)
  }
  r := Option(usize).Some(9)
  mut out : usize = 77
  match r {
    Some(v) => { out = 100 + v }
    None => { out = 50 }
  }
  return out
}

main := fn() -> u64 {
  return u64(pick(true))
}
