## e2e (Grammar §130 line 287 · OP-2 · Memory §1): compound assignment on an ARRAY ELEMENT
## place, for a literal and a variable index, across all eight operators' two halves.
##
## Before the fix EVERY place form except a bare name and `name.field` silently dropped its
## store, for ALL EIGHT operators INCLUDING `+=`, which "worked" on a name: each place form's
## statement-head lookahead required the plain `=` token (kind 21), so `a[1] += 2` matched no
## statement head, fell to the trailing-return expression path, and left the element untouched
## while compiling clean. Measured on the frozen seed with `[10,100,30]`: `a[1] += 2` returned
## 100, not 102, and `a[1] &= 58` returned 100, not 32 — a silent wrong value (I11).
##
## Memory §1 requires the place to be evaluated ONCE. Every place here is re-readable (a name, a
## constant, an index over those — no call), so the desugar's cloned READ is observationally
## identical to taking the address once. A place holding a call is a located reject instead; see
## reject_compound_place_call.al.
##
## Measured x86_64 = aarch64 = riscv64 = wasm = 42. The deeper place forms — a tuple component, a
## dereference, an aggregate field — live in compound_assign_place_deep.al, because the non-x86
## backends already trap on their PLAIN `=` store (measured there).
##
## Expected exit: 42 (every store agrees). A failure exits 100 + the store's 1-based index.
main := fn() -> u64 {
  mut bad : u64 = 0
  ## 1. `a[<literal>] &=` — a newly added operator on an array element
  mut a1 : [u64; 3] = [10, 100, 30]
  a1[1] &= 58
  if bad == 0 and a1[1] != 32 { bad = 1 }
  ## 2. `a[<name>] +=` — the index is a local, so the desugar's re-read is identical
  mut a2 : [u64; 3] = [10, 100, 30]
  i2 : usize = 1
  a2[i2] += 2
  if bad == 0 and a2[i2] != 102 { bad = 2 }
  ## 3. the plain `=` store on the same place must be untouched
  mut a3 : [u64; 3] = [10, 100, 30]
  a3[1] = 7
  if bad == 0 and a3[1] != 7 { bad = 3 }
  ## 4. `-=` — an operator that already existed, on a place that already dropped it
  mut a4 : [u64; 3] = [10, 100, 30]
  a4[1] -= 7
  if bad == 0 and a4[1] != 93 { bad = 4 }
  ## 5-7. the remaining three newly added operators
  mut a5 : [u64; 3] = [10, 100, 30]
  a5[1] %= 7
  if bad == 0 and a5[1] != 2 { bad = 5 }
  mut a6 : [u64; 3] = [10, 100, 30]
  a6[1] |= 58
  if bad == 0 and a6[1] != 126 { bad = 6 }
  mut a7 : [u64; 3] = [10, 100, 30]
  a7[1] ^= 58
  if bad == 0 and a7[1] != 94 { bad = 7 }
  if bad != 0 { return 100 + bad }
  return 42
}
