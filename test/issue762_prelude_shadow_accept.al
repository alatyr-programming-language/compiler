## e2e / issue #762 — a program's OWN `Arena` shadows the ambiently injected prelude's `alloc::Arena`
## in `check`, not only in `build`.
##
## Naming `Arena` pulls the shipped prelude in (#393), so two struct declarations answer the bare name.
## `check_expr`'s struct-literal arm used to take the first in declaration order — the prelude's, whose
## first field is `base : ptr(mut bits8)` — and compared this literal's `live = true` against that
## pointer field, refusing a well-formed program. Modules §3 resolves the name in the module that writes
## it, so the literal is checked against the declaration below, and every field value here fits it.
##
## 42 means the program was accepted and every field reads back. Each miss owns its own code from 100 up.
Arena := struct { live : bool, cap : u64 }

main := fn() -> u64 {
  a := Arena(live = true, cap = 5)
  if not a.live { return 100 }
  if a.cap != 5 { return 101 }
  return 42
}
