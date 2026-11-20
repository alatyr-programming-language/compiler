## Issue #554 / Memory §4.3 — `w := deref(ptr(o)).i`, where `i` is a two-word struct field of a struct
## LOCAL, binds the value of `o.i`. The legacy x86_64 emitter cannot yet copy a value wider than one
## word out of `deref(ptr(local))`, so it must refuse it with a located diagnostic rather than produce
## a value. The first fix for this root copied ONE word of `i` (`movq 8(%rax)`), so `w.y` read 0 where
## 33 is due: a clean compile with a wrong value. Out of scope here: reading a leaf through the field path
## (`deref(ptr(o)).i.y`, #1785).
##
## The twins trap at their field-access stub (#1187), listed in scripts/known-deviations.tsv.
In := struct { x : u64, y : u64 }
Out := struct { t : u64, i : In, z : u64 }

main := fn() -> u64 {
  o := Out(t = 1, i = In(x = 22, y = 33), z = 44)
  w := deref(ptr(o)).i
  return w.y
}
## expect: reject "has no multi-word value path here"
