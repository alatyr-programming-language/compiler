## `Result(T, E)` — a success value (`Ok`) or an error (`Err`).
## Base tier (freestanding, no allocation; Stdlib §1 / §3.4).
##
## Satisfies the `Tryable` protocol (success = `Ok`, failure = `Err`), so `x?`
## unwraps an `Ok` or propagates an `Err` (Control Flow §8.2). The propagated
## error keeps its type unless a declared `OutErr` conversion applies.
Result := fn(T : type, E : type) -> type { return enum { Ok(T), Err(E) } }

## Curated operations (Stdlib §160). Unwrapping an `Err` is a **defined-failure**
## `panic` (§4), never UB — and a **named** method (CF-7/CF-9: there is no `!`
## force-unwrap glyph). Reached prefix `unwrap(r)` or UFCS `r.unwrap()`.

## The success value, trapping on `Err` (defined-failure `panic`, §4).
pub unwrap := fn(T : type, E : type, self : Result(T, E)) -> T {
  match self { Ok(v) => v; Err(e) => panic("Result::unwrap on an Err") }
}

## The success value, trapping with a caller-supplied message on `Err`.
pub expect := fn(T : type, E : type, self : Result(T, E), msg : str) -> T {
  match self { Ok(v) => v; Err(e) => panic(msg) }
}

## The success value, or a fallback `default` on `Err`.
pub unwrap_or := fn(T : type, E : type, self : Result(T, E), default : T) -> T {
  match self { Ok(v) => v; Err(e) => default }
}

## Whether this is an `Ok`.
pub is_ok := fn(T : type, E : type, self : Result(T, E)) -> bool {
  match self { Ok(v) => true; Err(e) => false }
}

## Whether this is an `Err`.
pub is_err := fn(T : type, E : type, self : Result(T, E)) -> bool {
  match self { Ok(v) => false; Err(e) => true }
}

## Discard the error, converting to an `Option`: `Ok(v)` → `Some(v)`, `Err(e)` → `None`
## (Stdlib §160). The dual of `Option::ok_or`. A statement-`match` with an explicit `return` per
## arm (the lean lower delivers an enum return from `return <ctor>`; a tail value-`match` over an
## enum scrutinee in an enum-returning fn is a separate, unhandled path).
pub ok := fn(T : type, E : type, self : Result(T, E)) -> Option(T) {
  match self {
    Ok(v) => { return Option(T).Some(v) }
    Err(e) => { return Option(T).None }
  }
}

## Map the success value, leaving an `Err` unchanged: `Ok(v)` → `Ok(f(v))`, `Err(e)` → `Err(e)`
## (the functorial `map` over the `Ok` arm). A THREE-type-param generic (`map(T, E, U, …)`); the
## caller's `rr := map(…)` sizes/stages/matches `Result(U, E)` with `U` resolved to the call's type-arg.
pub map := fn(T : type, E : type, U : type, self : Result(T, E), f : fn(T) -> U) -> Result(U, E) {
  match self {
    Ok(v) => { return Result(U, E).Ok(f(v)) }
    Err(e) => { return Result(U, E).Err(e) }
  }
}

## Map the error value, leaving an `Ok` unchanged: `Ok(v)` → `Ok(v)`, `Err(e)` → `Err(g(e))`.
pub map_err := fn(T : type, E : type, F : type, self : Result(T, E), g : fn(E) -> F) -> Result(T, F) {
  match self {
    Ok(v) => { return Result(T, F).Ok(v) }
    Err(e) => { return Result(T, F).Err(g(e)) }
  }
}

## Chain a fallible step: `Ok(v)` → `f(v)` (itself a `Result(U, E)`), `Err(e)` → `Err(e)` (the monadic
## `and_then`/bind, the `Result` analogue of `Option::and_then`). A THREE-type-param generic.
pub and_then := fn(T : type, E : type, U : type, self : Result(T, E), f : fn(T) -> Result(U, E)) -> Result(U, E) {
  match self {
    Ok(v) => { return f(v) }
    Err(e) => { return Result(U, E).Err(e) }
  }
}
