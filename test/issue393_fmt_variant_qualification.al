## e2e / issue #393 — `alatyr fmt` must re-emit an enum-variant PATTERN with the qualifier the
## author wrote. Control Flow §5.2 makes the bare name, the `::`-path and the `.`-spelling three
## spellings of ONE variant — "a pattern may mirror exactly how the variant is built" — and Tooling
## §4.3 makes `fmt` semantics-preserving over a canonical form that is the lexical frame, spacing,
## wrapping and comments; nothing in it licenses respelling a path. On the parent `parse_pat_alt`
## overwrote the arm's name span with the LAST path segment, and BOTH arm emitters re-emitted that
## bare tail, so every qualifier the author wrote was deleted.
##
## That was not cosmetic. The ambient base prelude is injected by a TEXTUAL scan of the user source
## (`cli::ambient_paths`): the bare name of the fallible-result type is what pulls in `Arena`,
## `allocate` and the allocator error enum. This file's only occurrence of that word outside a
## comment is inside `classify`'s qualified patterns, so de-qualifying them took the whole prelude
## out of scope and the formatted text NO LONGER COMPILED — `fmt` exiting 0 while writing source
## that does not build, which `scripts/fmt_corpus.sh` calls a silent miscompile because the
## formatter has no fail-loud channel for a wrong rendering.
##
## Coverage — one row per emitter, one per spelling:
##   · `classify` — STATEMENT-form arms (braced bodies): the shape that stopped compiling, in both
##     the path and the dotted spelling, over an ambient enum this file never names any other way.
##   · `weight` — EXPRESSION-form arms (comma-separated expression bodies): the second, independent
##     emitter, carrying all three spellings side by side. The bare arm must stay bare — the
##     recovery must not invent a qualifier where the author wrote none.
##   · `pair` — qualified OR-pattern alternatives (the parser stores them as adjacent arms sharing
##     one body) followed by a bare arm.
##   · `dotted` — a bare first arm under a FIELD-ACCESS scrutinee: the separator the backward scan
##     looks for is present in the `match` header and must not be read as this arm's qualifier.
##
## 42 means every check held. Each miss owns its own code from 100 up — never a sum or a product, so
## one wrong arm cannot alias a passing run.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Tag := enum { Red, Green, Blue }

Holder := struct { t : Tag }

classify := fn(in out a : Arena, size : usize, align : usize) -> u64 {
  r := allocate(a, u8, size, align)
  match r {
    Result::Ok(h) => { return 1 }
    Result::Err(e) => {
      match e {
        AllocError.OutOfMemory => { return 2 }
        AllocError.BadAlignment => { return 3 }
        AllocError.SizeTooLarge => { return 4 }
      }
    }
  }
}

weight := fn(t : Tag) -> u64 {
  match t { Tag::Red => 1, Tag.Green => 2, Blue => 4 }
}

pair := fn(t : Tag) -> u64 {
  match t {
    Tag::Red | Tag::Blue => { return 8 }
    Green => { return 16 }
  }
}

dotted := fn(h : Holder) -> u64 {
  match h.t {
    Red => { return 32 }
    Tag::Green => { return 64 }
    Tag.Blue => { return 128 }
  }
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  nofd := unchecked bitcast(usize, neg1)
  m := unchecked sys_mmap(9, 0, 65536, 3, 34, nofd, 0)
  bp := unchecked bitcast(ptr(mut bits8), m)

  mut a1 := arena_over(bp, 64)
  if classify(a1, 8, 8) != 1 { return 100 }

  mut a2 := arena_over(bp, 8)
  if classify(a2, 9, 1) != 2 { return 101 }

  if weight(Tag.Red) != 1 { return 102 }
  if weight(Tag.Green) != 2 { return 103 }
  if weight(Tag.Blue) != 4 { return 104 }

  if pair(Tag.Red) != 8 { return 105 }
  if pair(Tag.Blue) != 8 { return 106 }
  if pair(Tag.Green) != 16 { return 107 }

  if dotted(Holder(t = Tag.Red)) != 32 { return 108 }
  if dotted(Holder(t = Tag.Green)) != 64 { return 109 }
  if dotted(Holder(t = Tag.Blue)) != 128 { return 110 }

  return 42
}
