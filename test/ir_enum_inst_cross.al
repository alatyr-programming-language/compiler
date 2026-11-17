## IR #1033 step 2: a generic enum instance with an AGGREGATE payload crosses a call between an IR-built
## function and a legacy-emitted one, both ways, as a parameter and as a result. The enum's words are the
## shared layout's (`lower_layout::enum_layout`), so both sides read one {tag, payload…} object; the
## result convention is the one every enum already uses (docs/ir.md §3.7).
##
## `lg_*` hold a float local, so the shared IR refuses them and they stay LEGACY-emitted; the others are
## IR-built.
##   * IR -> legacy: `main` passes an `Option(P)` to `lg_sum` and reads `lg_find`'s and `lg_parse`'s results;
##   * legacy -> IR: `lg_call` passes an `Option(P)` to `sum`, reads `find`'s result, and `?`s `parse`'s;
##   * two words, `Option(Q)` and `Result(u64, Flag)`: the size x86_64 takes across the boundary in
##     %rax/%rdx (wider ones stay on one side there); `wrap`/`lg_wrap` and `flag`/`lg_flag` both ways.
## On aarch64, riscv64 and wasm a signature carrying such an instance stays legacy (`ir::sig_pins_legacy`).
## Each check returns its own code on failure; 42 when all hold. x86_64 only, as `ir_enum_inst`.
P := struct { x : u64, y : u64 }
Error := enum { Missing, Bad(u64) }
Q := struct { v : u64 }
Flag := enum { Off, On }

find := fn(k : u64) -> Option(P) {
  if k == 0 { return Option(P).None }
  Option(P).Some(P(x = k, y = k + 1))
}
sum := fn(o : Option(P)) -> u64 {
  match o { Option::Some(p) => { return p.x + p.y }; Option::None => { return 50 } }
}
parse := fn(k : u64) -> Result(u64, Error) {
  if k == 0 { return Result(u64, Error).Err(Error.Missing) }
  if k > 9 { return Result(u64, Error).Err(Error.Bad(k)) }
  Result(u64, Error).Ok(k * 2)
}
code := fn(r : Result(u64, Error)) -> u64 {
  match r {
    Result::Ok(v) => { return v }
    Result::Err(e) => { match e { Error.Missing => { return 60 }; Error.Bad(b) => { return 70 + b } } }
  }
}
wrap := fn(k : u64) -> Option(Q) {
  if k == 0 { return Option(Q).None }
  Option(Q).Some(Q(v = k))
}
unwrap := fn(o : Option(Q)) -> u64 { match o { Option::Some(q) => { return q.v }; Option::None => { return 30 } } }
flag := fn(k : u64) -> Result(u64, Flag) {
  if k == 0 { return Result(u64, Flag).Err(Flag.Off) }
  if k == 1 { return Result(u64, Flag).Err(Flag.On) }
  Result(u64, Flag).Ok(k)
}
fcode := fn(r : Result(u64, Flag)) -> u64 {
  match r { Result::Ok(v) => { return v }; Result::Err(f) => { match f { Flag.Off => { return 20 }; Flag.On => { return 21 } } } }
}

lg_find := fn(k : u64) -> Option(P) {
  w : f64 = 1.0
  if k == 0 { return Option(P).None }
  Option(P).Some(P(x = k, y = 2))
}
lg_sum := fn(o : Option(P)) -> u64 {
  w : f64 = 1.0
  match o { Option::Some(p) => { return p.x * 10 + p.y }; Option::None => { return 55 } }
}
lg_parse := fn(k : u64) -> Result(u64, Error) {
  w : f64 = 1.0
  if k == 0 { return Result(u64, Error).Err(Error.Missing) }
  Result(u64, Error).Err(Error.Bad(k))
}
lg_twice := fn(k : u64) -> Result(u64, Error) {
  w : f64 = 1.0
  v := parse(k)?
  Result(u64, Error).Ok(v + 1)
}
lg_wrap := fn(k : u64) -> Option(Q) {
  w : f64 = 1.0
  if k == 0 { return Option(Q).None }
  Option(Q).Some(Q(v = k + 1))
}
lg_unwrap := fn(o : Option(Q)) -> u64 {
  w : f64 = 1.0
  match o { Option::Some(q) => { return q.v * 2 }; Option::None => { return 31 } }
}
lg_flag := fn(k : u64) -> Result(u64, Flag) {
  w : f64 = 1.0
  if k == 1 { return Result(u64, Flag).Err(Flag.On) }
  Result(u64, Flag).Ok(k + 1)
}
lg_fcode := fn(r : Result(u64, Flag)) -> u64 {
  w : f64 = 1.0
  match r { Result::Ok(v) => { return v * 2 }; Result::Err(f) => { match f { Flag.Off => { return 22 }; Flag.On => { return 23 } } } }
}
lg_call := fn() -> u64 {
  w : f64 = 1.0
  o := find(4)
  return sum(Option(P).Some(P(x = 1, y = 2))) + sum(o) + code(lg_twice(3)) + code(lg_twice(0))
}

main := fn() -> u64 {
  if lg_sum(find(3)) != 34 { return 1 }
  if lg_sum(find(0)) != 55 { return 2 }
  if sum(lg_find(5)) != 7 { return 3 }
  if sum(lg_find(0)) != 50 { return 4 }
  if code(lg_parse(0)) != 60 { return 5 }
  if code(lg_parse(9)) != 79 { return 6 }
  if lg_call() != 3 + 9 + 7 + 60 { return 7 }
  if unwrap(lg_wrap(4)) != 5 or unwrap(lg_wrap(0)) != 30 { return 8 }
  if lg_unwrap(wrap(4)) != 8 or lg_unwrap(wrap(0)) != 31 { return 9 }
  if fcode(lg_flag(1)) != 21 or fcode(lg_flag(5)) != 6 { return 10 }
  if lg_fcode(flag(0)) != 22 or lg_fcode(flag(1)) != 23 or lg_fcode(flag(7)) != 14 { return 11 }
  42
}
## expect(x86_64): run 42
