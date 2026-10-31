## The JSON document model: a tree of `Value`s whose containers and strings live in one
## caller-owned arena. A whole document is released at once by freeing that arena.
##
## Objects keep their members in source order (a `Vec(Member)`), so printing a parsed
## document reproduces its key order, and duplicate keys survive as written; `find`
## returns the first member with a key.

## One JSON value. Numbers are split by their source form: an integer literal that fits
## `i64` is `Int`; a literal with a fraction or exponent, or an integer outside `i64`, is
## `Float`.
##
## A container's elements are a slice over the arena storage its parser filled; that
## storage is complete once the container is parsed and is never grown again, so the
## slice stays valid until the arena is freed.
## blocked-by: #1172 — an `alloc::vec::Vec(T)` payload reads back wrong fields after a
## `match`, so the payloads are `Slice`s rather than the `Vec`s themselves.
pub Value := enum {
  Null,
  Bool(bool),
  Int(i64),
  Float(f64),
  Str(str),
  Arr(Slice(Value)),
  Obj(Slice(Member)),
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
      for m in ms {
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
      xs.len
    }
    Value.Obj(ms) => {
      ms.len
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
      if i < xs.len { return Option(Value).Some(xs[i]) }
      Option(Value).None
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

arrays_equal := fn(xs : Slice(Value), ys : Slice(Value)) -> bool {
  if xs.len != ys.len { return false }
  mut i : usize = 0
  for x in xs {
    if equal(x, ys[i]) == false { return false }
    i += 1
  }
  true
}

objects_equal := fn(xs : Slice(Member), ys : Slice(Member)) -> bool {
  if xs.len != ys.len { return false }
  mut i : usize = 0
  for x in xs {
    y := ys[i]
    if x.key != y.key { return false }
    if equal(x.val, y.val) == false { return false }
    i += 1
  }
  true
}
