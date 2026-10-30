## The JSON document model: a tree of `Value`s whose containers and strings live in one
## caller-owned arena. A whole document is released at once by freeing that arena.
##
## Objects keep their members in source order (a `Vec(Member)`), so printing a parsed
## document reproduces its key order, and duplicate keys survive as written; `find`
## returns the first member with a key.

## One JSON value. Numbers are split by their source form: an integer literal that fits
## `i64` is `Int`; a literal with a fraction or exponent, or an integer outside `i64`, is
## `Float`.
pub Value := enum {
  Null,
  Bool(bool),
  Int(i64),
  Float(f64),
  Str(str),
  Arr(alloc::vec::Vec(Value)),
  Obj(alloc::vec::Vec(Member)),
}

## One `"key": value` pair of an object.
pub Member := struct {
  key : str,
  val : Value,
}

## The value of the first member named `key` in an object, or `None` when `v` is not an
## object or has no such member.
pub find := fn(v : Value, key : str) -> Option(Value) {
  match v {
    Value.Obj(ms) => {
      ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
      ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
      for m in alloc::vec::iter(Member, ptr(ms)) {
        if m.key == key { return Option(Value).Some(m.val) }
      }
      Option(Value).None
    }
    _ => {
      Option(Value).None
    }
  }
}

## The number of elements of an array or members of an object; 0 for a scalar.
pub count := fn(v : Value) -> usize {
  match v {
    Value.Arr(xs) => {
      ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
      ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
      alloc::vec::len(Value, ptr(xs))
    }
    Value.Obj(ms) => {
      ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
      ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
      alloc::vec::len(Member, ptr(ms))
    }
    _ => {
      0
    }
  }
}

## The `i`-th element of an array, or `None` past its end or when `v` is not an array.
pub item := fn(v : Value, i : usize) -> Option(Value) {
  match v {
    Value.Arr(xs) => {
      ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
      ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
      alloc::vec::get(Value, ptr(xs), i)
    }
    _ => {
      Option(Value).None
    }
  }
}

## Structural equality: the same variant with equal contents, arrays element by element,
## objects member by member in order. `Int(1)` and `Float(1.0)` differ, as their source
## forms do.
pub equal := fn(a : Value, b : Value) -> bool {
  match a {
    Value.Null => {
      match b {
        Value.Null => { true }
        _ => { false }
      }
    }
    Value.Bool(x) => {
      match b {
        Value.Bool(y) => { x == y }
        _ => { false }
      }
    }
    Value.Int(x) => {
      match b {
        Value.Int(y) => { x == y }
        _ => { false }
      }
    }
    Value.Float(x) => {
      match b {
        Value.Float(y) => { x == y }
        _ => { false }
      }
    }
    Value.Str(x) => {
      match b {
        Value.Str(y) => { x == y }
        _ => { false }
      }
    }
    Value.Arr(xs) => {
      match b {
        Value.Arr(ys) => { arrays_equal(xs, ys) }
        _ => { false }
      }
    }
    Value.Obj(xs) => {
      match b {
        Value.Obj(ys) => { objects_equal(xs, ys) }
        _ => { false }
      }
    }
  }
}

arrays_equal := fn(xs : alloc::vec::Vec(Value), ys : alloc::vec::Vec(Value)) -> bool {
  ## blocked-by: #987 — `ys[i]` reads 0; `at` is the index operator's own read arm.
  ## blocked-by: #1146 — `ys.at(i)` cannot infer `T`, so `at` is called with it.
  ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
  ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
  if alloc::vec::len(Value, ptr(xs)) != alloc::vec::len(Value, ptr(ys)) { return false }
  mut i : usize = 0
  for x in alloc::vec::iter(Value, ptr(xs)) {
    if equal(x, alloc::vec::at(Value, ptr(ys), i)) == false { return false }
    i += 1
  }
  true
}

objects_equal := fn(xs : alloc::vec::Vec(Member), ys : alloc::vec::Vec(Member)) -> bool {
  ## blocked-by: #987 — `ys[i]` reads 0; `at` is the index operator's own read arm.
  ## blocked-by: #1146 — `ys.at(i)` cannot infer `T`, so `at` is called with it.
  ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
  ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
  if alloc::vec::len(Member, ptr(xs)) != alloc::vec::len(Member, ptr(ys)) { return false }
  mut i : usize = 0
  for x in alloc::vec::iter(Member, ptr(xs)) {
    y := alloc::vec::at(Member, ptr(ys), i)
    if x.key != y.key { return false }
    if equal(x.val, y.val) == false { return false }
    i += 1
  }
  true
}
