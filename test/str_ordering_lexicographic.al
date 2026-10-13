## e2e — an ORDERING compare (`<`/`>`/`<=`/`>=`) over `str` operands compares their CONTENT,
## lexicographically by byte, exactly as `base::str::str_cmp` defines it (Stdlib §2.6 /
## `lib/base/str.al`: compare bytes up to the SHORTER length; on a common prefix the SHORTER string
## is the smaller, so a prefix precedes its extension). The operators over `str` desugar to
## `str_cmp(a, b) <> 0`.
##
## What was silently wrong: x86_64 had a byte-compare arm for `==`/`!=` over `str`
## (`emit_str_eq_core`) but NONE for the orderings, so `c >= "a"` fell through to the scalar
## `cmpq` at the bottom of the `Bin` case and compared the two operands' `.rodata` ADDRESSES:
##
##   leaq .Lstr0_0(%rip), %rax     ## "z"
##   leaq .Lstr0_1(%rip), %rbx     ## "a"
##   cmpq %rbx, %rax                ## two addresses, not two strings
##   setge %al
##
## `"z" >= "a"` therefore answered FALSE — a normal-exit wrong value whose answer depended on where
## the linker happened to place the literals, so it could flip with an unrelated edit.
##
## This is NOT a signedness question: no `s`/`u` answer makes an address compare correct. That is
## why it sat in the census's `sema-unknown` column (sema records a `str` operand as an aggregate
## and `ir::sema_answer` has no signedness to name for one) rather than in the DISAGREE column
## that 1e moves. The bytes load with `movzbq` and are unsigned, so the setcc forms the fix emits
## are the carry ones (`setb`/`seta`/`setbe`/`setae`).
##
## Each block is one shape the address compare could get wrong:
##   1-4   byte order, both directions — an address compare answers here only by luck;
##   5-7   equal strings: `<=`/`>=` hold, `<`/`>` do not;
##   8-10  the PREFIX rule, both directions — a shape no word-wise compare can express at all;
##   11-13 the identifier-scan shapes that live in the compiler's own source (`iface.al:72`,
##         `driver.al:312`, `sema.al:18139`, `lower_attrs.al:28`, `wat.al:117`): a one-byte `str`
##         against a one-byte literal, over each of the three ranges `[a-z]`, `[A-Z]`, `[0-9]`.
main := fn() -> i64 {
  if not ("z" >= "a") { return 1 }
  if ("a" >= "z") { return 2 }
  if not ("a" < "z") { return 3 }
  if ("z" < "a") { return 4 }

  if not ("a" <= "a") { return 5 }
  if ("a" < "a") { return 6 }
  if not ("z" >= "z") { return 7 }

  if not ("a" <= "ab") { return 8 }
  if ("ab" <= "a") { return 9 }
  if not ("ab" > "a") { return 10 }

  c : str = "h"
  if not (c >= "a" and c <= "z") { return 11 }
  d : str = "H"
  if not (d >= "A" and d <= "Z") { return 12 }
  e : str = "9"
  if not (e >= "0" and e <= "9") { return 13 }

  return 42
}
