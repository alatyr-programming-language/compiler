## Issue #524 — an EXTERNAL package reaches the base tier through the qualified `pub`-chain surface.
## Modules §3:90-92 makes the `pub` chain to the root the ONLY way out of a package ("a library's
## public API is exactly the pub-chain-to-root-reachable surface"), Stdlib §1/§7.1 require the base
## tier to be reachable from any program, and the Stdlib appendix §8.6 makes every definition there
## REQUIRED v1 content. So each qualified call below is an instance of a required definition, not a
## chosen API extension.
##
## Failure-first on parent 71ea8df: every one of the seven qualified families below is refused with a
## located `check` diagnostic on the parent, because none of the callees carried a `pub` marker. Each
## family is measured on its own and every rejection code is distinct, so no total can alias a pass.
##
## The families, one specification anchor each:
##   num.al        overflow policy prefixes x the checked-overflow operations (appendix §4.3,
##                 Concurrency §6.3/§8.5)                          — wrapping/saturating/checked
##   cmp.al        the per-type concrete `eq`/`lt` overrides (appendix §2.6)
##   derive.al     the generic structural `eq`/`lt` derives (appendix §2.6)
##   u128.al       `uint`/`u128` and the ordinary library operator-functions (Types §7:687-704)
##   alloc.al      the §5.1 mechanism surface and the §5.2.1 arena surface
##   assert.al     `assert` (appendix §4.2, Stdlib §4.3)
##   process.al    `exit` (appendix §4.2)
##
## NOT covered here on purpose: the qualified overflow calls use the `u8` interpretation. The wider
## interpretations pass `check` after this unit and then fail at LINK with an undefined
## `base__num__wrapping_add__u16_u16`, because the qualified-callee resolver picks the FIRST
## same-named ambient overload for emission while the call site mangles by argument type. That is a
## separate emission defect this unit uncovers rather than causes; see the PR body.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Pair := struct { x : u64, y : u64 }

main := fn() -> u64 {
  ## ---- num.al: the overflow-policy family (appendix §4.3; Concurrency §6.3/§8.5) ----
  a : u8 = 250
  if base::num::wrapping_add(a, 10) != 4 { return 1 }
  if base::num::wrapping_sub(a, 255) != 251 { return 2 }
  if base::num::wrapping_mul(a, 3) != 238 { return 3 }
  if base::num::saturating_add(a, 10) != 255 { return 4 }
  if base::num::saturating_sub(a, 255) != 0 { return 5 }
  b : u8 = 40
  if unwrap(u8, base::num::checked_add(b, 2)) != 42 { return 6 }

  ## ---- cmp.al: the per-type concrete `eq`/`lt` overrides (appendix §2.6) ----
  x : u64 = 42
  if base::cmp::eq(x, 42) == false { return 7 }
  if base::cmp::lt(x, 43) == false { return 8 }
  if base::cmp::lt(x, 42) { return 9 }

  ## ---- derive.al: the generic structural derives (appendix §2.6) ----
  p := Pair(x = 1, y = 2)
  q := Pair(x = 1, y = 2)
  if base::derive::eq(Pair, p, q) == false { return 10 }
  w := Pair(x = 1, y = 3)
  if base::derive::eq(Pair, p, w) { return 11 }
  if base::derive::lt(Pair, p, w) == false { return 12 }

  ## ---- u128.al: `uint(N)` and its library operator-functions (Types §7:687-704) ----
  lo : base::u128::u128 = u128(words = [18446744073709551615, 0])
  one : base::u128::u128 = u128(words = [1, 0])
  carried := lo + one
  if carried.words[1] != 1 { return 13 }
  back := carried - one
  if back.words[0] != 18446744073709551615 { return 14 }
  if carried == one { return 15 }

  ## ---- alloc.al: the §5.1 mechanism surface and the §5.2.1 arena surface ----
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := base::alloc::arena_over(bp, 65536)
  if base::alloc::mechanism(ar) != Mechanism.region { return 17 }
  @alloc(ar) h := 40
  ptr40 := base::alloc::get(isize, ar, h)
  stored := u64(deref(ptr40))
  base::alloc::close(ar)
  if ar.off != 0 { return 18 }

  ## ---- assert.al / process.al (appendix §4.2) ----
  base::assert::assert(stored == 40)
  if stored != 40 { base::process::exit(1) }

  return stored + 2
}
