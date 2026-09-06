## e2e (#472) — the SILENT face of a GENERIC OVERLOAD SET. Two generic `pick` declarations in one
## module differ only in their VALUE parameter, and the instance label `<module>__<fn>__<typetag>`
## was built from the TYPE ARGUMENTS ALONE, so at one `(T)` both collapsed onto one linker symbol.
## Their ARITY is equal, so `generic_decl_of` answered BOTH call sites with the LAST-declared match:
## one body was emitted and `pick(u64, A(…))` ran the `B` body, reading the SECOND word of a ONE-word
## `A`. That is a clean compile with a wrong answer, which is why the exit codes below are distinct —
## a bare non-zero exit would not tell the two overloads apart.
##
## Parent verdict: builds rc=0, exits 10 (`m` was 7, not 1). Fixed verdict: 42.
## Modules §6.7 (linker-symbol uniqueness). x86_64 is the surface that is made CORRECT here. The
## three cross backends resolve a generic callee by name alone and label the instance with no
## signature, so they can neither select nor separate two overloads; on the parent aarch64 and
## riscv64 emitted duplicate labels and wasm answered 10 SILENTLY. A generic overload set is now
## outside `lower_layout::gen_call_ok`'s shape fence, so all three fail loudly instead — the same
## route every other out-of-fence generic shape already takes.

A := struct { x : u64 }
B := struct { p : u64, y : u64 }

pick := fn(T : type, a : A) -> u64 { a.x }
pick := fn(T : type, b : B) -> u64 { b.y }

## Declaration order is part of the measurement: with the two swapped the parent answered 11 instead
## of 10, because "last-declared wins" is what chose the surviving body. Both directions are covered.
grab := fn(T : type, b : B) -> u64 { b.y }
grab := fn(T : type, a : A) -> u64 { a.x }

main := fn() -> u64 {
  m := pick(u64, A(x = 1))
  n := pick(u64, B(p = 7, y = 42))
  if m != 1 { return 10 }          ## the parent stopped here
  if n != 42 { return 11 }
  ## the reversed declaration order: the parent stopped at 13 instead
  g := grab(u64, A(x = 1))
  h := grab(u64, B(p = 7, y = 42))
  if g != 1 { return 12 }
  if h != 42 { return 13 }
  ## a local (not a struct literal) reaches the redirect through the receiver resolver rather than
  ## the syntactic struct-literal one — both passes must type it the same way or the collected
  ## instance and the emitted call name different symbols.
  lb : B = B(p = 7, y = 42)
  if pick(u64, lb) != 42 { return 14 }
  42
}
