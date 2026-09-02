## e2e (issue #349) — `Arena.allocate` must reject an INVALID alignment with
## `Err(AllocError.BadAlignment)` (Stdlib appendix §5.1: "`BadAlignment` — the requested
## alignment is invalid or unsupported (e.g. not a power of two)"). The pre-fix `allocate`
## computed `self.off % align` with no validation at all, so a non-power-of-two alignment
## silently produced a MISALIGNED `Ok(Handle)` (align 3 over a fresh arena returned
## `Ok(idx = 0)`), and align 0 reached a modulo-by-zero and TRAPPED instead of returning a
## `Result` at all.
##
## `try_alloc` classifies the `Result` into a small code — 0 Ok, 1 OutOfMemory,
## 2 BadAlignment, 3 SizeTooLarge — so each case is checked against ONE expected code and
## the failure codes (100+) are distinct per case, never a sum or a product of them.
## Every case runs over its OWN fresh 8-byte arena, so a case cannot inherit another's cursor.
##
## The `allocate` result is bound through an EXPLICIT annotation
## (`r : Result(Handle(u8), AllocError) = …`) rather than an inferred `r := …`. That is
## load-bearing, not decoration: `alatyr fmt` de-qualifies every variant pattern
## (`Result::Ok(h)` -> `Ok(h)`, `AllocError.OutOfMemory` -> `OutOfMemory`), and the bare
## names only resolve when the matched value's type is written in the source. With the type
## inferred through the generic `allocate` call the reformatted file stops compiling — that
## formatter defect is issue #393. The annotation is what lets this fixture keep the
## EXHAUSTIVE qualified arm list (the stronger assertion) while surviving today's formatter.
## Note that both spellings are fmt-IDEMPOTENT, so only building the formatted output shows
## the difference; `scripts/fmt_corpus.sh` is the gate that checks it.
##
## Boundary coverage: 0 (invalid), 1/2/4/8 (valid powers of two, must still succeed),
## 3/5/6/7 (invalid non-powers of two, including the values immediately either side of a
## valid 4 and 8). A rejection must leave the cursor untouched, so the arena still hands out
## index 0 afterwards, and the existing `OutOfMemory` path for a representable over-capacity
## request is unchanged. The expected result is 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

try_alloc := fn(in out a : Arena, size : usize, align : usize) -> u64 {
  r : Result(Handle(u8), AllocError) = allocate(a, u8, size, align)
  match r {
    Result::Ok(h) => { return 0 }
    Result::Err(e) => {
      match e {
        AllocError.OutOfMemory => { return 1 }
        AllocError.BadAlignment => { return 2 }
        AllocError.SizeTooLarge => { return 3 }
      }
    }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  m := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, m))

  ## --- invalid: not a power of two ---
  mut a3 := arena_over(bp, 8)
  if try_alloc(a3, 1, 3) != 2 { return 100 }
  ## the rejected request must not have moved the bump cursor
  if a3.off != 0 { return 101 }
  ## and the arena is still usable: the next valid request lands at index 0
  i3 := allocate(a3, u8, 1, 1).expect("post-reject allocate").idx
  if i3 != 0 { return 102 }

  mut a5 := arena_over(bp, 8)
  if try_alloc(a5, 1, 5) != 2 { return 103 }
  mut a6 := arena_over(bp, 8)
  if try_alloc(a6, 1, 6) != 2 { return 104 }
  mut a7 := arena_over(bp, 8)
  if try_alloc(a7, 1, 7) != 2 { return 105 }

  ## --- invalid: zero (the pre-fix modulo-by-zero trap) ---
  mut a0 := arena_over(bp, 8)
  if try_alloc(a0, 1, 0) != 2 { return 106 }
  if a0.off != 0 { return 107 }

  ## --- valid: powers of two still succeed ---
  mut b1 := arena_over(bp, 8)
  if try_alloc(b1, 1, 1) != 0 { return 108 }
  mut b2 := arena_over(bp, 8)
  if try_alloc(b2, 1, 2) != 0 { return 109 }
  mut b4 := arena_over(bp, 8)
  if try_alloc(b4, 1, 4) != 0 { return 110 }
  mut b8 := arena_over(bp, 8)
  if try_alloc(b8, 1, 8) != 0 { return 111 }

  ## --- the existing OutOfMemory path is unchanged (valid alignment, request > capacity).
  ## The request is representable (`0 + 9` does not overflow), so this is OutOfMemory and
  ## not the `SizeTooLarge` overflow of #352.
  mut oom := arena_over(bp, 8)
  if try_alloc(oom, 9, 1) != 1 { return 112 }

  return 42
}
