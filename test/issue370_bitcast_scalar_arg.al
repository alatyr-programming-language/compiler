## Issue #370 / Types §§3.4, 4.4 and Memory §5.9 — an equal-width aggregate bitcast used DIRECTLY as
## a by-value struct ARGUMENT is the identity on the source block, so the callee must receive the
## source aggregate's own words. Before the fix the argument fell through `emit_arg`'s aggregate
## probes to the scalar default: word 0 was pushed as a VALUE and the callee dereferenced it as the
## aggregate's address, so the program died with exit 139 on x86_64.
##
## Each field is checked SEPARATELY, with distinct non-zero values, so a swapped or partly-copied
## image names the word that moved wrong (issue #386: a commutative sum cannot see a word swap).
## The callees answer with a field INDEX and each call site maps it onto its own refusal base at
## 100 or above, so every refusal is distinct, below 126, and cannot alias the success value 42.
## Plain and `unchecked` forms are both exercised at one, two and three words; an ordinary aggregate
## argument is the control; and the new argument-position form is placed next to the old
## bind-then-pass form in both orders. Two further shapes of the same argument arm are covered: the
## reinterpret's source is a by-REF aggregate PARAM (the pointer half of the by-ref argument
## address) and the reinterpret sits beside a scalar argument in both register positions.
A1 := struct { a : u64 }
B1 := struct { x : u64 }
A2 := struct { a : u64, b : u64 }
B2 := struct { x : u64, y : u64 }
A3 := struct { a : u64, b : u64, c : u64 }
B3 := struct { x : u64, y : u64, z : u64 }

take1 := fn(b : B1) -> u64 {
  if b.x != 7 { return 1 }
  return 0
}

take2 := fn(b : B2) -> u64 {
  if b.x != 11 { return 1 }
  if b.y != 13 { return 2 }
  return 0
}

take3 := fn(b : B3) -> u64 {
  if b.x != 17 { return 1 }
  if b.y != 19 { return 2 }
  if b.z != 23 { return 3 }
  return 0
}

## the reinterpret's SOURCE here is a by-REF aggregate PARAM, not a frame-local block
fwd3 := fn(a : A3) -> u64 {
  return take3(bitcast(B3, a))
}

## the reinterpret beside a SCALAR argument, in both register positions
aggfirst := fn(b : B3, k : u64) -> u64 {
  if b.x != 17 { return 1 }
  if b.z != 23 { return 2 }
  if k != 9 { return 3 }
  return 0
}

scalarfirst := fn(k : u64, b : B3) -> u64 {
  if k != 8 { return 1 }
  if b.x != 17 { return 2 }
  if b.y != 19 { return 3 }
  return 0
}

main := fn() -> u64 {
  a1 := A1(a = 7)
  a2 := A2(a = 11, b = 13)
  a3 := A3(a = 17, b = 19, c = 23)

  ## the OLD form — bind the reinterpret to a local, then pass the local — must keep working
  o3 := bitcast(B3, a3)
  mut r := take3(o3)
  if r != 0 { return 100 + r }

  ## the NEW form — the bitcast IS the argument expression
  r = take1(bitcast(B1, a1))
  if r != 0 { return 104 + r }
  r = take2(bitcast(B2, a2))
  if r != 0 { return 105 + r }
  r = take3(bitcast(B3, a3))
  if r != 0 { return 107 + r }

  ## the `unchecked` wrapper, same three widths
  r = take1(unchecked bitcast(B1, a1))
  if r != 0 { return 110 + r }
  r = take2(unchecked bitcast(B2, a2))
  if r != 0 { return 111 + r }
  r = take3(unchecked bitcast(B3, a3))
  if r != 0 { return 113 + r }

  ## the old form again, AFTER the new one — the reverse order of the pair above
  o2 := unchecked bitcast(B2, a2)
  r = take2(o2)
  if r != 0 { return 116 + r }

  ## the ordinary aggregate argument control — no bitcast at all
  b3 := B3(x = 17, y = 19, z = 23)
  r = take3(b3)
  if r != 0 { return 118 + r }

  ## the reinterpret's source is a by-ref aggregate PARAM one frame down
  r = fwd3(a3)
  if r != 0 { return 96 + r }

  ## the reinterpret next to a scalar argument, in both orders
  r = aggfirst(bitcast(B3, a3), 9)
  if r != 0 { return 90 + r }
  r = scalarfirst(8, unchecked bitcast(B3, a3))
  if r != 0 { return 93 + r }

  ## the source aggregate must be unchanged by having been passed through a bitcast
  if a3.a != 17 { return 122 }
  if a3.b != 19 { return 123 }
  if a3.c != 23 { return 124 }
  return 42
}
