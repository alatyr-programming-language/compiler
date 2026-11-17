## IR #1033 step 2: a generic enum instance whose one payload component is an AGGREGATE — a struct or
## another enum — is built by the shared IR as a result, a local, a parameter and a payload. The
## component is a sub-object at the payload offset `lower_layout::enum_layout` gives, sized by
## `lower_layout::agg_words` (Types §6.2); a match binds it by copying its bytes out.
##   * `Option(P)`: built in place, returned, matched, passed on as a parameter;
##   * `Result(u64, Error)`: an enum error component, passed through `?` unconverted;
##   * `Option(Option(u64))`: an enum instance inside an enum instance;
##   * `Option(Id)`: a brand payload has its underlying scalar's representation (Types §5.4).
## Each check returns its own code on failure; 42 when all hold. x86_64 only: on aarch64, riscv64 and
## wasm a signature carrying such an instance stays legacy (`ir::sig_pins_legacy`), whose emitters trap
## on it (133/134); `ir_enum_inst_local` holds the shapes on all four.
P := struct { x : u64, y : u64 }
Error := enum { Missing, Bad(u64) }
Id := brand(u64)

find := fn(k : u64) -> Option(P) {
  if k == 0 { return Option(P).None }
  Option(P).Some(P(x = k, y = k + 1))
}
sum := fn(o : Option(P)) -> u64 {
  match o { Option::Some(p) => { return p.x + p.y }; Option::None => { return 50 } }
}
pass := fn(o : Option(P)) -> u64 { return sum(o) }

parse := fn(k : u64) -> Result(u64, Error) {
  if k == 0 { return Result(u64, Error).Err(Error.Missing) }
  if k > 9 { return Result(u64, Error).Err(Error.Bad(k)) }
  Result(u64, Error).Ok(k * 2)
}
twice := fn(k : u64) -> Result(u64, Error) {
  v := parse(k)?
  Result(u64, Error).Ok(v + 1)
}
code := fn(r : Result(u64, Error)) -> u64 {
  match r {
    Result::Ok(v) => { return v }
    Result::Err(e) => { match e { Error.Missing => { return 60 }; Error.Bad(b) => { return 70 + b } } }
  }
}

nest := fn(k : u64) -> Option(Option(u64)) {
  if k == 0 { return Option(Option(u64)).None }
  if k == 1 { return Option(Option(u64)).Some(Option(u64).None) }
  Option(Option(u64)).Some(Option(u64).Some(k))
}
depth := fn(o : Option(Option(u64))) -> u64 {
  match o {
    Option::Some(inner) => { match inner { Option::Some(v) => { return v }; Option::None => { return 2 } } }
    Option::None => { return 1 }
  }
}

ident := fn(k : u64) -> Option(Id) {
  if k == 0 { return Option(Id).None }
  Option(Id).Some(Id(k))
}

main := fn() -> u64 {
  if sum(find(3)) != 7 { return 1 }
  if sum(find(0)) != 50 { return 2 }
  o := find(5)
  if pass(o) != 11 { return 3 }
  if code(parse(4)) != 8 { return 4 }
  if code(parse(0)) != 60 { return 5 }
  if code(parse(12)) != 82 { return 6 }
  if code(twice(3)) != 7 { return 7 }
  if code(twice(11)) != 81 { return 8 }
  if code(twice(0)) != 60 { return 9 }
  if depth(nest(0)) != 1 or depth(nest(1)) != 2 or depth(nest(9)) != 9 { return 10 }
  i := ident(40)
  w : u64 = match i { Some(v) => u64(v); None => 100 }
  if w != 40 { return 11 }
  n := ident(0)
  z : u64 = match n { Some(v) => u64(v); None => 2 }
  w + z
}
## expect(x86_64): run 42
