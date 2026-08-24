## e2e — field access DIRECTLY on a POINTER-returning call: `get(S, ar, h).a` / `.b`, with NO
## intermediate `p := get(...); deref(p).f` binding. `get` returns `scoped ptr(mut S)`, so the field
## must be read THROUGH the returned pointer. This was a SILENT MISCOMPILE: the base (a Call whose
## result is a POINTER, not a struct by value) fell to the `field_slot` `pushq $0` default → the field
## read 0/stale (it silently zeroed the DA header words `da_fvec_value(x).len`). The two-step form
## already worked (`dsb`/`dcf` deref reads). Verifies offset-0 (`.a`) AND non-zero-offset (`.b`) fields,
## plus that the direct form AGREES with the two-step form. Types §9.4.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

S := struct { a : u64, b : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  @alloc(ar) hh := S(a = 7, b = 99)

  p := get(S, ar, hh)
  two_a := deref(p).a          ## two-step: 7
  two_b := deref(p).b          ## two-step: 99
  direct_a := get(S, ar, hh).a ## direct call().field, offset 0: was 0, now 7
  direct_b := get(S, ar, hh).b ## direct call().field, offset 1: was 0, now 99

  mut bad := 0
  if direct_a != two_a { bad = 1 }        ## direct form must agree with the two-step form
  if direct_b != two_b { bad = 1 }
  return direct_a + direct_b + bad * 9     ## 7 + 99 = 106 when correct; 0 under the old silent-0 bug
}
