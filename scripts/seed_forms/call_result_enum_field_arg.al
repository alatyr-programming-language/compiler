## Seed-forms registry entry `call_result_enum_field_arg` (scripts/seed_forms.tsv) — NOT a corpus fixture.
## An enum-typed field of a call's struct result passed straight as an argument, `is_c(mk().kind)`.
## `src/sema.al` (`resolve_kind`) records the SEGFAULT against the seed and binds the result first.
## Measured, the tree compiler segfaults too. State `tree`, #791. Due: 42.
K := enum { KA, KB, KC }
T := struct { a : u64, kind : K, b : u64 }
mk := fn() -> T { T(a = 1, kind = K.KC, b = 2) }
is_c := fn(k : K) -> u64 {
  match k {
    K::KA => { 1 }
    K::KB => { 2 }
    K::KC => { 42 }
  }
}
main := fn() -> u64 { is_c(mk().kind) }
