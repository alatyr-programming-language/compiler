## e2e / issue #393 (residual) — the ALLOCATOR ERROR ENUM name, alone, must pull the ambient base
## prelude.
##
## `cli::ambient_paths` decides the prelude from a TEXTUAL scan of the user source, and its
## allocator-surface trigger used to be the bare name of the fallible-result type only. A program can
## reach the error enum without ever naming that type — annotate a parameter with it, build one of
## its variants, match it — and such a program got no prelude and was rejected on its first line.
##
## Isolation is the point: this file names no arena type and calls no arena constructor, so it fails
## on the parent unless the error enum name itself is a trigger. On the parent it is refused with
## `check: invalid`, located on the annotated signature below.
## The arms return 1/2/4 and are asserted one at a time — the codes are compared, never combined, so
## a swapped pair cannot add up to a pass.
##
## 42 means every check held. Each miss owns its own code from 100 up.
rank := fn(e : AllocError) -> u64 {
  match e {
    OutOfMemory => { return 1 }
    BadAlignment => { return 2 }
    SizeTooLarge => { return 4 }
  }
}

main := fn() -> u64 {
  if rank(AllocError.OutOfMemory) != 1 { return 100 }
  if rank(AllocError.BadAlignment) != 2 { return 101 }
  if rank(AllocError.SizeTooLarge) != 4 { return 102 }
  return 42
}
