## e2e — `ptr(x)` CARRIES ITS POINTEE, so an inferred pointer key reaches a generic (#sema form 9)
##
## Before this change the compiler refused this program at sema:
##
##   alatyr: this generic call omits its comptime type argument and it cannot be inferred here
##           (Comptime 3.3) - pass it explicitly (`f(str, v)`) or annotate the argument's binding
##
## for the single line `hash(k)` where `k := ptr(x)`. The reason is one expression in `sema.al`:
##
##   Expr::AddrOf(p) => { tp := check_expr(p, …)?
##                        Ok(Ty(kind = TyKind.TyPtr, ns = 0, nl = 0)) }
##
## — the inner place's type `tp` was computed and then THROWN AWAY, so the expression-level `Ty`
## said "a pointer" without saying to what. Five other sites in the same file already build a
## `TyPtr` with its pointee span (2585, 3560, 4314, 7164, 7171); this was the only one that
## dropped it, and its own comment said why: "the toy grammar's pointers point to ints". That
## grammar is gone — the tree declares `ptr(mut Stmt)` and `ptr(u8)` — and Types §4 models the
## opposite of the drop: an operand `ptr([mut] R)` in a position wanting `R` REACHES THE POINTEE,
## so the pointee is known at that node by definition.
##
## ## Why each probe is here
##
##   A  `hash(k)` on an INFERRED `k := ptr(x)`            100   THE DEFECT. Refused before, and the
##                                                               only way to make it compile was to
##                                                               annotate — which is what every pointer
##                                                               fixture in this repo had to do, and what
##                                                               made the gap invisible in the corpus
##   B  same address, two inferred handles, equal hash     101   the span carried is the POINTEE's,
##                                                               not the variable's: two different
##                                                               expressions naming one place must agree
##   C  distinct places, inferred handles, unequal hash   102   non-vacuity of B — a constant hash
##                                                               would pass B and fail here
##   D  `eq(k, k2)` inferred, same place                   103   the same span feeds `eq`, not just
##                                                               `hash`; §2.6 requires them to agree
##   E  the pointer still points where it did              104   the span is TYPE information only:
##                                                               carrying it must not disturb the value,
##                                                               so the load is checked here too
##   F  an inferred pointer to a NON-u64 place            105   the span is not hardcoded to one
##                                                               type name: `x : u32` must reach
##                                                               `hash` as `ptr(u32)` and answer
##                                                               without a refusal
##
## Every failure has its own code from 100 up; success is 42 (#386 — no summed discriminator).
## No `unchecked` appears in this file: the whole point is that checked code reaches these calls.

main := fn() -> u64 {
  mut x : u64 = 7
  mut y : u64 = 9
  mut w : u32 = 258

  k := ptr(x)
  k2 := ptr(x)
  ky := ptr(y)
  kw := ptr(w)

  ## A — the defect: an inferred pointer as a generic argument.
  h1 := hash(k)

  ## B — two inferred handles on one place hash alike.
  if h1 != hash(k2) { return 100 }

  ## C — a different place must not hash alike (non-vacuity of B).
  if h1 == hash(ky) { return 101 }

  ## D — the same span feeds `eq`.
  if eq(k, k2) != true { return 102 }
  if eq(k, ky) != false { return 103 }

  ## E — carrying the span must not disturb the value the pointer reads.
  if deref(k) != 7 { return 104 }
  if deref(ky) != 9 { return 105 }

  ## F — the pointee span is the place's own type name, not a fixed one.
  if hash(kw) != hash(ptr(w)) { return 106 }
  if deref(kw) != 258 { return 107 }

  42
}
