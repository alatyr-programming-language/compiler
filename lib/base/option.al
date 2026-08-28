## `Option(T)` — a value that is either present (`Some`) or absent (`None`).
## Base tier (freestanding, no allocation; Stdlib §1 / §3.3).
##
## Satisfies the `Tryable` protocol (success = `Some`, failure = `None`), so
## `x?` unwraps a `Some` or propagates a `None` (Control Flow §8.2).
Option := fn(T : type) -> type { return enum { None, Some(T) } }

## Curated operations (Stdlib §160). Unwrapping a `None` is a **defined-failure**
## `panic` (§4), never UB — a **named** method (CF-7/CF-9: no `!` force-unwrap).
## Reached prefix `unwrap(o)` or UFCS `o.unwrap()`.

## The present value, trapping on `None` (defined-failure `panic`, §4).
pub unwrap := fn(T : type, self : Option(T)) -> T {
  match self { Some(v) => v; None => panic("Option::unwrap on a None") }
}

## The present value, trapping with a caller-supplied message on `None`.
pub expect := fn(T : type, self : Option(T), msg : str) -> T {
  match self { Some(v) => v; None => panic(msg) }
}

## The present value, or a fallback `default` on `None`.
pub unwrap_or := fn(T : type, self : Option(T), default : T) -> T {
  match self { Some(v) => v; None => default }
}

## Whether a value is present.
pub is_some := fn(T : type, self : Option(T)) -> bool {
  match self { Some(v) => true; None => false }
}

## Whether the value is absent.
pub is_none := fn(T : type, self : Option(T)) -> bool {
  match self { Some(v) => false; None => true }
}

## A non-consuming pointer to the payload of `Some`, or `None` for an absent value
## (§160). The pointer is borrowed from the option place and must not outlive it.
## Pointer payloads use the §8 null niche, so `Option(ptr(T))` is one word; other payloads retain the
## ordinary discriminant-plus-payload representation.
pub get := fn(T : type, self : ptr(mut Option(T))) -> Option(ptr(T)) {
  comptime if (match typeinfo(T) { Pointer(_) => true; _ => false }) {
    ## `get` returns a pointer to the payload's storage. In the niche representation the option word
    ## is that storage, so test its contents and return `self` reinterpreted as `ptr(T)`.
    word := deref(unchecked bitcast(ptr(usize), unchecked bitcast(usize, self)))
    if word == 0 { return Option(ptr(T)).None }
    payload := unchecked bitcast(ptr(T), unchecked bitcast(usize, self))
    Option(ptr(T)).Some(payload)
  } else {
    tag := deref(unchecked bitcast(ptr(usize), unchecked bitcast(usize, self)))
    if tag != 1 { return Option(ptr(T)).None }
    payload := unchecked bitcast(ptr(T), unchecked bitcast(usize, self) + 8)
    Option(ptr(T)).Some(payload)
  }
}

## Chain a fallible step: `Some(v)` → `f(v)` (itself an `Option(U)`), `None` → `None`
## (the monadic `and_then`/bind). A statement-`match` with an explicit `return` per arm.
pub and_then := fn(T : type, U : type, self : Option(T), f : fn(T) -> Option(U)) -> Option(U) {
  match self {
    Some(v) => { return f(v) }
    None => { return Option(U).None }
  }
}

## Apply `f` to a present value, leaving `None` unchanged: `Some(v)` → `Some(f(v))`, `None` → `None`
## (the functorial `map`). The result binding `om := map(…)` sizes/stages/matches `Option(U)` with `U`
## resolved to the call's type-arg (the generic-enum-return substitution on the caller side); a struct
## `U` produced by `f` (`Some(f(v))`, `f -> struct`) is staged whole from the fn value's struct return.
pub map := fn(T : type, U : type, self : Option(T), f : fn(T) -> U) -> Option(U) {
  match self {
    Some(v) => { return Option(U).Some(f(v)) }
    None => { return Option(U).None }
  }
}

## Convert to a `Result`, supplying the error for the absent case: `Some(v)` → `Ok(v)`,
## `None` → `Err(err)` (Stdlib §160).
pub ok_or := fn(T : type, E : type, self : Option(T), err : E) -> Result(T, E) {
  match self {
    Some(v) => { return Result(T, E).Ok(v) }
    None => { return Result(T, E).Err(err) }
  }
}
