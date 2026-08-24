## a struct with an ENUM FIELD, then `match s.c`. Previously silently miscompiled — an
## enum field was sized as ONE word (field_words defaulted it to wsize 1), so the following field
## overwrote the enum's payload, AND the struct constructor never stored the enum (an EnumLit isn't an
## ArrayLit), AND `match s.c` read a garbage discriminant. Now field_words counts an enum field as
## 1 + max_arity words, emit_struct_assign stores it via emit_enum_assign, and try_field_enum_scrut
## materializes the field's enum for the match. `s.c` = G(40), `s.n` = 2 → 40 + 2 = 42.
Col := enum { R, G(u64), B }
S := struct { c : Col, n : u64 }
main := fn() -> u64 {
  s := S(c = Col.G(40), n = 2)
  match s.c {
    Col::R => { return 0 }
    Col::G(x) => { return x + s.n }
    Col::B => { return 1 }
  }
}
