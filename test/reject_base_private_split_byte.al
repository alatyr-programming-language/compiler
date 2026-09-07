## Issue #524 over-reach control — publishing the 203 specification-enumerated base declarations must
## NOT publish the 21 that are genuinely internal. `split_byte` (lib/base/str.al) is one of them: it
## is not named by any Stdlib appendix code block, so Modules §3:90-92 keeps it out of the library's
## public API and a qualified reference from outside `base::str` stays refused.
##
## The row is self-proving: line 12 calls the PUBLIC `base::str::byte_len` from the same module and is
## accepted, so `lib/base/str.al` is demonstrably injected and the module path demonstrably resolves.
## Only line 13 is refused, and it is refused for the visibility reason, not because the module was
## never reached. `lib/base/str.al` itself is untouched by #524 — #452 owns it.
main := fn() -> u64 {
  s := "a,b"
  if base::str::byte_len(s) != 3 { return 1 }
  k := base::str::split_byte(s, 44)
  42
}
