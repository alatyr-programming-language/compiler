## #986 — `<call>.expect(m)` unwrapped inline with success hardcoded to variant 0, and only payload
## word 0 delivered. The library `Option` is `{None, Some}`, so Some is variant 1: an `Option(u64)`
## receiver panicked on Some, and every other inline unwrap (`.expect(m).field`, a statement
## `<call>?` / `<call>.expect(m)`) made the same assumption. A struct payload bound with
## `x := <call>.expect(m)` kept word 0 only. The fix sends every inline unwrap through one check that
## takes the success variant from the receiver's type, and binds a struct payload whole.
##
## Expected: builds, runs to exit 42. Each check owns a code from 101 up.
##
## Parent `55fa477` (x86_64, omen): built rc 0, ran to rc 1 (the `expect` panic on `Some(42)`, step 1)
## where 42 was due.
S := struct { a : u64, b : u64 }

some42 := fn() -> Option(u64) { return Option(u64).Some(42) }
none_u := fn() -> Option(u64) { return Option(u64).None }
ok_s := fn() -> Result(S, u64) { return Result(S, u64).Ok(S(a = 1, b = 41)) }
some_s := fn() -> Option(S) { return Option(S).Some(S(a = 2, b = 40)) }

## A statement `?` over a lib Option: Some continues, None returns None.
stmt_try_some := fn() -> Option(u64) {
  some42()?
  return Option(u64).Some(7)
}
stmt_try_none := fn() -> Option(u64) {
  none_u()?
  return Option(u64).Some(7)
}

opt_code := fn(o : Option(u64)) -> u64 {
  match o {
    Option.Some(x) => { return x }
    Option.None => { return 1000 }
  }
}

main := fn() -> u64 {
  ## 1. scalar Option payload in value position
  v := some42().expect("v")
  if v != 42 { return 101 }
  ## 2. a Result struct payload, bound whole
  r := ok_s().expect("r")
  if r.a != 1 { return 102 }
  if r.b != 41 { return 103 }
  ## 3. an Option struct payload, bound whole
  o := some_s().expect("o")
  if o.a != 2 { return 104 }
  if o.b != 40 { return 105 }
  ## 4. a field of the unwrapped payload, at offset 1
  fb := some_s().expect("fb").b
  if fb != 40 { return 106 }
  ## 5. a statement `expect` on Some does not panic
  some42().expect("stmt")
  ## 6. a statement `?`: Some continues to the fn's own result, None returns None
  if opt_code(stmt_try_some()) != 7 { return 107 }
  if opt_code(stmt_try_none()) != 1000 { return 108 }
  ## 7. a library constructor's Result, through `expect`
  mem := std::os::arena(65536).expect("arena")
  c := mem.cap
  f := std::os::free(mem)
  if c != 65536 { return 109 }
  42
}
## expect: run 42
