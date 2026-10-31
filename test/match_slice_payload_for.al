## e2e (#1318) — a single `match` payload binding typed `Slice(T)` is a slice like any other
## (Control Flow §5.2 binds the payload at its declared type; §6 iterates it with `for x in`).
## x86_64 bound it as the nominal two-word `Slice` struct, so `for` copied one word per element:
## a struct element read wrong fields and a recursive enum element (the json pilot's
## `Value.Arr(xs)`) segfaulted, and `ps[1].a` was refused. Each check returns its own code; the
## expected exit is 42. On the parent the build is refused (`ps[1].a`); without `second` it exits 2.
P := struct { a : u64, b : u64 }
E := enum {
  A,
  I(Slice(u64)),
  S(Slice(P)),
  T(Slice(str)),
}
V := enum {
  Null,
  Int(u64),
  Arr(Slice(V)),
}

sum := fn(e : E) -> u64 {
  match e {
    E.A => { 0 }
    E.I(xs) => {
      mut t : u64 = 0
      for x in xs { t += x }
      t
    }
    E.S(ps) => {
      mut t : u64 = 0
      for p in ps { t += p.a * 10 + p.b }
      t
    }
    E.T(ss) => {
      mut t : u64 = 0
      for s in ss { t += s.len }
      t
    }
  }
}

## a loop body that binds a local (#1321 kept the index in that local's slot)
firsts := fn(e : E) -> u64 {
  match e {
    E.S(ps) => {
      mut t : u64 = 0
      for p in ps {
        pa : u64 = p.a
        t += pa
      }
      t
    }
    E.A => { 0 }
    E.I(_) => { 0 }
    E.T(_) => { 0 }
  }
}

## the element read by index, and the length, of a struct-element payload
second := fn(e : E) -> u64 {
  match e {
    E.S(ps) => { ps[1].a * 10 + ps.len }
    E.A => { 0 }
    E.I(_) => { 0 }
    E.T(_) => { 0 }
  }
}

## the json pilot's shape: recurse over an enum-element payload
total := fn(v : V) -> u64 {
  match v {
    V.Null => { 0 }
    V.Int(n) => { n }
    V.Arr(xs) => {
      mut t : u64 = 0
      for x in xs { t += total(x) }
      t
    }
  }
}

main := fn() -> u64 {
  ints := [3, 4]
  if sum(E.I(ints[0..2])) != 7 { return 1 }
  ps := [P(a = 3, b = 1), P(a = 4, b = 2)]
  if sum(E.S(ps[0..2])) != 73 { return 2 }
  if second(E.S(ps[0..2])) != 42 { return 3 }
  if firsts(E.S(ps[0..2])) != 7 { return 6 }
  strs := ["ab", "cde"]
  if sum(E.T(strs[0..2])) != 5 { return 4 }
  inner := [V.Int(30), V.Null]
  nest := [V.Int(10), V.Arr(inner[0..2]), V.Int(2)]
  if total(V.Arr(nest[0..3])) != 42 { return 5 }
  42
}
