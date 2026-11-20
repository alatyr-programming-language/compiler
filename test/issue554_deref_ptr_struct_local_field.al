## Issue #554 / Memory §4.3 — `deref(ptr(l)).field` where `l` is a plain struct LOCAL is the ordinary
## field read `l.field`, and must answer the field's value. `ptr(x)` "takes a memory-resident place `x` …
## and yields an address value"; `deref(p)` "takes an address `p` and yields the place it denotes". On such a
## place the two are INVERSE, so there is nothing to follow: `deref(ptr(loc)).b` IS `loc.b`. DECIDED at the
## pinned revision 1.8.0 (tag v1.8.0, commit 8da0372); no clause was invented.
##
## On the parent it answered NOTHING. `emit_gas`' `Expr::Field` arm resolves the pointee through
## `deref_struct_span`, and that helper peels `Deref(Var)` — here the inner node is an `AddrOf`, so it
## answered 0/0. #506's fallback `deref_addrof_byref_struct_span` covers the SAME shape on a BY-REFERENCE
## struct PARAMETER and refuses at `if ent.is_ref == false`, a branch its own comment names as "every other
## `ek = 2` binding" — i.e. exactly this struct local. Every other deref arm wants a different inner node
## (`deref_deref_struct_span`, `deref_call_struct_span`, `deref_field_ptrstruct_span`,
## `deref_index_ptrstruct_span`), so no arm matched, `field_slot` fell through, and the read contributed a
## literal 0: `40 + deref(ptr(loc)).b` answered **40** where the direct `loc.b` answered **101 on the same
## binary**. Clean compile, exit 0, no diagnostic.
##
## The fix is NOT #506's emission. A by-ref parameter's slot HOLDS a pointer, so that arm loads the slot and
## follows it; here the slot IS the struct, so its address is a `leaq` of the frame — which is what
## `emit_gas` already emits for `ptr(loc)`. The new arm re-enters on the inner `AddrOf` to get that address
## into %rax, then loads the field at its ascending word offset, the same `fi*8(%rax)` the direct read uses.
##
## Every case is CLASSIFIED into the four outcomes the issue asks for, because "not 40" is not evidence:
## class 0 the CORRECT value; class 1 the ZERO CONTRIBUTION, the defect itself (the addend alone survived);
## class 2 a NEIGHBOURING FIELD's value, which is what a wrong word offset produces; class 3 anything else,
## including garbage. Each case owns its OWN struct local with values no other case produces, and each reads
## a DIFFERENT field or a different local, so no case can pass off another's slot and no wrong word offset
## survives cases 1 to 3 reading three different offsets. The code returned is `10 * case + class` of the
## FIRST failing case; 99 only when all seven are correct. Failure codes run 11..73, 99 is outside that
## range, and every code is below 126 (#386).
##
## Cases 6 and 7 are CONTROLS, green on BOTH sides of the fix: the direct `loc.b` read (which already
## answered 101 and must stay 101 — it is the proof that the frame layout was never wrong, only the root
## resolution), and a BY-VALUE struct PARAMETER reached through `deref(ptr(p))`, the same shape on a
## different home for the name.
##
## REGISTERED ON x86_64 ONLY (`run_x86`). Measured on the parent AND on this tree, the `deref(ptr(local))`
## shape TRAPS on all three twins identically before and after (aarch64 133, riscv64 133, wasm 134) while
## the direct read runs on all four (101). Those traps are unchanged by this fix — loud, not wrong values —
## and belong to the twins' own emitters; they are reported to the integrator as residuals, not registered
## here as permissions. The issue itself predicted this ("the same is expected here but was not measured");
## it is now measured.
S := struct { a : u64, b : u64, c : u64 }

## 0 correct, 1 the zero contribution (the defect), 2 a neighbouring field (wrong word offset), 3 garbage.
classify := fn(got : u64, want : u64, zero : u64, neighbour : u64) -> u64 {
  if got == want { return 0 }
  if got == zero { return 1 }
  if got == neighbour { return 2 }
  return 3
}

## 7 — control: a BY-VALUE struct PARAMETER through `deref(ptr(p))`, the same shape on another home.
case7 := fn(p : S) -> u64 { return 100 + deref(ptr(p)).b }

main := fn() -> u64 {
  ## 1 — the MIDDLE field: `40 + deref(ptr(l1)).b`, the issue's own reproducer and shape.
  l1 := S(a = 11, b = 61, c = 31)
  k1 := classify(40 + deref(ptr(l1)).b, 101, 40, 51)
  if k1 != 0 { return 10 + k1 }

  ## 2 — the FIRST field, a different word offset on a different local.
  l2 := S(a = 12, b = 62, c = 32)
  k2 := classify(41 + deref(ptr(l2)).a, 53, 41, 103)
  if k2 != 0 { return 20 + k2 }

  ## 3 — the LAST field, a third word offset.
  l3 := S(a = 13, b = 63, c = 33)
  k3 := classify(42 + deref(ptr(l3)).c, 75, 42, 105)
  if k3 != 0 { return 30 + k3 }

  ## 4 — all three fields of one local summed: a wrong offset cannot hide inside this case.
  l4 := S(a = 14, b = 64, c = 34)
  s4 := deref(ptr(l4)).a + deref(ptr(l4)).b + deref(ptr(l4)).c
  k4 := classify(s4, 112, 0, 42)
  if k4 != 0 { return 40 + k4 }

  ## 5 — a MUT local, rebound before the read: the address must be taken afresh, not cached.
  mut l5 := S(a = 15, b = 65, c = 35)
  l5 = S(a = 16, b = 67, c = 36)
  k5 := classify(200 + deref(ptr(l5)).b, 267, 200, 216)
  if k5 != 0 { return 50 + k5 }

  ## 6 — control: the DIRECT read, green on both sides of the fix.
  l6 := S(a = 17, b = 68, c = 37)
  k6 := classify(43 + l6.b, 111, 43, 60)
  if k6 != 0 { return 60 + k6 }

  ## 7 — control: the same shape on a by-value struct PARAMETER.
  k7 := classify(case7(S(a = 18, b = 69, c = 38)), 169, 100, 118)
  if k7 != 0 { return 70 + k7 }

  99
}
## expect: run 99
