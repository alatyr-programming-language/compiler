## Expected exit: 109 — Issue #406: a local declared in a NESTED block and then declared again in the
## ENCLOSING scope under the same name but a different enum type. Declarations §5/§6.1 make the program
## VALID — the two declarations belong to two different scopes, §6.2 forbids only a same-scope
## re-declaration — and the aarch64, riscv64 and WAT backends all answer 109 for it. The legacy x86
## slot map keys a frame slot by NAME alone for the whole function and records the type of whichever
## binding it saw FIRST, so the later `match` resolved `Some`/`None` in `Result`'s variant list, found
## neither, and fell through taking no arm at all — `out` kept its `77` initializer and a clean compile
## answered 77 where 109 was due. The refusal that stood in place of that wrong value was a STOPGAP,
## not the requirement: it refused spec-valid code three backends ran correctly, and #1022 says such a
## refusal must not be registered as law. The shared IR's x86 selector answers 109, measured on native
## x86_64 through the DEFAULT surface after the slice-9 flip (`docs/ir.md` §7.4, #980), so this fixture
## asserts the value. `alatyr x86-legacy` on this file still refuses, which is the escape hatch's whole
## purpose — to show what the flip replaced. (Renaming one of the two locals remains the fix at the
## source for anyone staying on the legacy surface.)
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
