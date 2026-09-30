## e2e / issue #770 — a generic instance over a `ptr(mut T)` type argument has a valid label.
##
## The instance label is spelled from each type argument's source text, and `ptr(mut T)` contributes
## `mut T` — with a space, so `base__option__is_some__ptr_mut Node` split in two and the assembler
## rejected a build `check` had accepted. The label now maps every non-symbol byte to `_`. Once it
## assembles, the `-> T` result of `Option::unwrap` / an identity at `T = ptr(mut Node)` must also carry
## its pointee, or `deref(n).v` reads 0 — that half is checked here too.
##
## 42 means every call linked and every read held. Each miss owns its own code from 100 up.
Node := struct { v : u64, w : u64 }

id := fn(T : type, x : T) -> T { x }

main := fn() -> u64 {
  mut c := Node(v = 40, w = 2)
  o : Option(ptr(mut Node)) = Option(ptr(mut Node)).Some(ptr(c))
  none : Option(ptr(mut Node)) = Option(ptr(mut Node)).None
  if not Option::is_some(ptr(mut Node), o) { return 100 }
  if Option::is_some(ptr(mut Node), none) { return 101 }
  if not Option::is_none(ptr(mut Node), none) { return 102 }
  n := Option::unwrap(ptr(mut Node), o)
  if deref(n).v != 40 { return 103 }
  m := id(ptr(mut Node), ptr(c))
  if deref(m).w != 2 { return 104 }
  k := Option::unwrap_or(ptr(mut Node), none, ptr(c))
  return deref(k).v + deref(m).w
}
