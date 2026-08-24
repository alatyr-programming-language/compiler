## e2e — a module-level ARRAY global whose elements are ENUM values, end to end: the `.data` image, the
## strided element READ (`e := GE[i]` and `match GE[i]`, at a CONSTANT and a RUNTIME index) and the
## strided element WRITE (an enum LITERAL and an enum VAR RHS).
##
## Before: the `.data` emitter fell to the scalar `else` and wrote ONE `.quad global_init_value(…)` per
## element — an enum literal has no scalar init value, so every cell came out 0 (discriminants AND
## payloads lost) and the element stride was 1 word instead of `1 + max payload`; `GE[i]` then read and
## wrote a single word at `LABEL + i*8`, i.e. the MIDDLE of an element. Reads matched the wrong variant
## (0) and writes landed mid-element (255) — both SILENT. A previous lane made the shape fail-loud; this
## fixture is the correct implementation.
##
## Layout exercised: `E` has a NULLARY variant (`N`), a 1-payload variant (`A`) and a 2-payload-word
## variant (`P`), so `enum_max_arity(E) == 2` and every element occupies `1 + 2 == 3` words:
## `[disc, p0, p1]`, zero-padded for the narrower/nullary variants.
E := enum { N, A(u64), P(u64, u64) }

mut GE := [E.A(5), E.N, E.P(7, 9), E.A(1)]

## a CONST (non-`mut`) enum array global — also `.data`-imaged at the same stride, read-only.
CE := [E.P(1, 2), E.A(4), E.N]

## a GENERIC enum element (`Option(i64)`): the stride comes from `enum_inst_words` of the INSTANCE.
mut GO := [Option(i64).Some(11), Option(i64).None]

main := fn() -> u64 {
  ## READ at a CONSTANT index — the disc and payload of element 0 (`A(5)`).
  match GE[0] {
    E::N => { return 1 }
    E::A(n) => { if n != 5 { return 2 } }
    E::P(x, y) => { return 3 }
  }
  ## the NULLARY variant at element 1 — its payload words are the image's zero padding.
  match GE[1] {
    E::N => {}
    E::A(n) => { return 4 }
    E::P(x, y) => { return 5 }
  }
  ## the 2-payload-word variant at element 2 — BOTH payload words must survive the stride.
  match GE[2] {
    E::N => { return 6 }
    E::A(n) => { return 7 }
    E::P(x, y) => { if x != 7 { return 8 } if y != 9 { return 9 } }
  }
  ## READ at a RUNTIME index — the same element, addressed by a scaled register.
  mut i : u64 = 2
  match GE[i] {
    E::N => { return 10 }
    E::A(n) => { return 11 }
    E::P(x, y) => { if x + y != 16 { return 12 } }
  }
  ## whole-element READ into a LOCAL (`e := GE[i]`), then match the local — constant index.
  e := GE[3]
  match e {
    E::N => { return 13 }
    E::A(n) => { if n != 1 { return 14 } }
    E::P(x, y) => { return 15 }
  }
  ## the same whole-element READ at a RUNTIME index.
  mut m : u64 = 2
  e2 := GE[m]
  match e2 {
    E::N => { return 36 }
    E::A(n) => { return 37 }
    E::P(x, y) => { if x != 7 { return 38 } if y != 9 { return 39 } }
  }
  ## a CONST array global — `match CE[i]` and `c := CE[i]`, constant and runtime index.
  match CE[0] {
    E::N => { return 40 }
    E::A(n) => { return 41 }
    E::P(x, y) => { if x != 1 { return 43 } if y != 2 { return 44 } }
  }
  mut ci : u64 = 1
  c := CE[ci]
  match c {
    E::N => { return 45 }
    E::A(n) => { if n != 4 { return 46 } }
    E::P(x, y) => { return 47 }
  }
  match CE[2] { E::N => {} E::A(n) => { return 48 } E::P(x, y) => { return 49 } }
  ## a GENERIC enum element — the instance's stride, read then written.
  match GO[0] { Option::Some(v) => { if v != 11 { return 50 } } Option::None => { return 51 } }
  match GO[1] { Option::Some(v) => { return 52 } Option::None => {} }
  GO[1] = Option(i64).Some(13)
  match GO[1] { Option::Some(v) => { if v != 13 { return 53 } } Option::None => { return 54 } }
  match GO[0] { Option::Some(v) => { if v != 11 { return 55 } } Option::None => { return 56 } }
  ## WRITE an enum LITERAL at a CONSTANT index — a WIDER variant over a narrower one.
  GE[0] = E.P(20, 22)
  match GE[0] {
    E::N => { return 16 }
    E::A(n) => { return 17 }
    E::P(x, y) => { if x != 20 { return 18 } if y != 22 { return 19 } }
  }
  ## WRITE an enum LITERAL at a RUNTIME index — a NULLARY variant over a 2-payload one.
  mut j : u64 = 2
  GE[j] = E.N
  match GE[2] {
    E::N => {}
    E::A(n) => { return 20 }
    E::P(x, y) => { return 21 }
  }
  ## WRITE from an enum VAR (a non-ref local), constant index then runtime index.
  v := E.A(33)
  GE[1] = v
  match GE[1] {
    E::N => { return 22 }
    E::A(n) => { if n != 33 { return 23 } }
    E::P(x, y) => { return 24 }
  }
  mut k : u64 = 3
  w := E.P(4, 6)
  GE[k] = w
  match GE[3] {
    E::N => { return 25 }
    E::A(n) => { return 26 }
    E::P(x, y) => { if x != 4 { return 27 } if y != 6 { return 28 } }
  }
  ## the neighbours were NOT clobbered by any of the strided writes (element 0 is still P(20,22)).
  match GE[0] {
    E::N => { return 29 }
    E::A(n) => { return 30 }
    E::P(x, y) => { if x + y != 42 { return 31 } }
  }
  ## the source locals were read, not aliased.
  match v { E::A(n) => { if n != 33 { return 32 } } E::N => { return 33 } E::P(x, y) => { return 34 } }
  ## 20 + 22 = 42
  mut acc : u64 = 0
  match GE[0] { E::P(x, y) => { acc = x + y } E::N => {} E::A(n) => {} }
  acc
}
