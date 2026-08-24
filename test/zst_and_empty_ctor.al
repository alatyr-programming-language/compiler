## ZERO-SIZED TYPES (spec Types §6.5) + the ZERO-NAMED-FIELD constructor `T()` (grammar §130
## struct-ctor with an EMPTY field-init list; §9.4 all-defaulted construction).
##
## §6.5: an empty `struct {}` and `[T; 0]` are ZERO-SIZED — size 0, alignment 1; they occupy no
## bytes and emit none. A ZST FIELD contributes 0 words, so it does not shift a following field.
## §9.4/§130: `TypeName()` constructs an empty struct (a marker/phantom) or an all-defaulted struct
## (every field filled from its declared default). Recognized as CONSTRUCTION (not a call) because the
## head is a known concrete struct in the field-order table. Returns 42. A parse desugar + layout →
## correct on x86_64 → `run`.

Z := struct {}                          ## a zero-sized marker type

M := struct { m : Z, x : u64 }          ## a ZST field BEFORE a real field — must not shift `x`

N := struct { x : u64, m : Z, y : u64 } ## a ZST field BETWEEN real fields

W := struct { x : u64 = 42 }            ## an ALL-DEFAULTED struct — `W()` fills `x` from its default

V := struct { a : u64 = 10, b : u64 = 32 } ## multi-field all-defaulted

E := struct { pad : [u64; 0], x : u64 } ## a ZERO-LENGTH array field (ZST) before a real field

take_marker := fn(z : Z) -> u64 { return 7 }   ## a ZST passed BY VALUE is a no-op

main := fn() -> u64 {
  ## (1) construct an empty struct via `Z()`; bind it, use it as a marker argument.
  z := Z()
  if take_marker(z) != 7 { return 1 }
  if take_marker(Z()) != 7 { return 2 }

  ## (2) size(Z) == 0, align(Z) == 1  (spec §6.5).
  if size(Z) != 0 { return 3 }
  if align(Z) != 1 { return 4 }

  ## (3) a ZST field does not shift the other fields — `M(m = Z(), x = 7)` reads `x` correctly.
  a := M(m = Z(), x = 7)
  if a.x != 7 { return 5 }

  ## (3b) a ZST field BETWEEN two real fields — both neighbours land right.
  n := N(x = 3, m = Z(), y = 9)
  if n.x != 3 { return 6 }
  if n.y != 9 { return 7 }

  ## (4) the empty-ctor for an ALL-DEFAULTED struct — `W()` fills `x` from its default (42).
  w := W()
  if w.x != 42 { return 8 }

  ## (4b) multi-field all-defaulted `V()` → a = 10, b = 32.
  v := V()
  if v.a != 10 { return 9 }
  if v.b != 32 { return 10 }

  ## (5) a `[T; 0]` field is zero-sized — `[]` provides it and `x` still reads right.
  e := E(pad = [], x = 11)
  if e.x != 11 { return 11 }

  return 42
}
