## alloc::fmt — the **alloc-tier renderer** (Stdlib §2.7; Comptime §5.3).
## `display(T, v, sb)` renders any value into a `StrBuf` (the §2.7 sink) **field by
## field**: an aggregate as `{ name = value, … }` (recursing via `comptime for` over
## `typeinfo(T).fields` + the projection `a.(f)`), a scalar leaf as its base-10 text.
## Monomorphized per type, fully erased — zero-cost, no RTTI.
##
## **Tier:** this is the **alloc** tier — it builds an in-memory `StrBuf` and
## never reaches the OS, so `format`/`display` are usable on a `freestanding` (no
## `std`) target with only an allocator. Writing a built buffer to a stream is the
## **std** tier (`std::fmt::write_buf`/`print`/`println`), which composes over this.
## (`std::fmt` re-exports `display`/`format` so the historical `std::fmt::*` paths
## keep resolving.)
##
## Two known interim limits, both additive: (1) v1 leaf rendering of a nested
## **aggregate field** needs the backend to read an aggregate field through a
## by-reference parameter's pointer; (2) the sink is the concrete `StrBuf` — the
## general `Writer`-protocol sink (any type with `write([u8])`) is the §2.7
## generalization.

## Trap on an in-memory render failure — the **trapping boundary** for the
## `print`/`println` conveniences (Stdlib §1: a buffer's `Writer` error is
## `AllocError`; these conveniences own a throwaway arena, where OOM is a hard
## error, not a recoverable one — so they absorb the fallible renderer's `Result`
## here and trap). This is *not* a hidden failure (I3/I11): a trap is observable.
pub trap_oom := fn(r : Result(usize, AllocError)) {
  ## Match the `Result` directly rather than `r.expect(msg)`: `.expect` is UFCS-overloaded
  ## across `Option`/`Result` and the lean lower can't resolve an overloaded UFCS method on a
  ## PARAM receiver (it mis-mangled the type-arg to the receiver name). The explicit `match` is
  ## the same trap semantics (§4 `panic` on `Err`) with no reliance on that sugar.
  match r {
    Result::Ok(n) => {}
    Result::Err(e) => { panic("fmt: out of memory rendering to in-memory buffer") }
  }
}

## Render `v` into `sb`. A struct/aggregate renders `{ f = v, … }` recursively;
## a scalar leaf renders its base-10 text (signed with a leading `-`). Fallible:
## the buffer's growth `?`-propagates `AllocError`, so `format` surfaces OOM
## instead of trapping; `print`/`println` absorb it.
pub display := fn(T : type, v : T, in out sb : alloc::strbuf::StrBuf) -> Result(usize, AllocError) {
  ## One flat `comptime match` over `typeinfo(T)` (CT-8 §8.2) — only the matching
  ## arm is emitted, its pattern bindings (`under`/`m`, `b`/`k`) comptime values.
  comptime match typeinfo(T) {
    ## A **user nominal brand** (CT-6) — the prelude scalar brands
    ## (`uN`/`iN`/`fN`/`bool`/`char`) reify as `Scalar{kind}`, not `Brand`, so they
    ## are handled by the `Scalar` arm below; only a user brand reaches here. Dispatch on
    ## the UNDERLYING scalar's kind (`typeinfo(under)`) so a brand over a SIGNED or FLOAT
    ## underlying selects the right rendering (a leading `-` / the float formatter), not
    ## raw base-10 of `u64(v)` — the same conversions the `Scalar` arm uses, picked by the
    ## underlying kind. NOTE (compiler-side, not stdlib): the SIGNED/FLOAT path is currently
    ## blocked — `i64(v)`/`f64(v)` on a brand value peel `v` to its underlying, and in this
    ## monomorphized GENERIC context that peel emits an unresolved `bitcast to ?` (the
    ## brand's underlying is not substituted into the conversion); the prior `u64(v)`-only
    ## arm had the same gap, so a user brand over a non-identity underlying has never
    ## rendered. The UNSIGNED/bits path (the only currently-instantiable case) is unchanged.
    Brand(under, _) => comptime match typeinfo(under) {
      Scalar(ub, uk) => comptime match uk {
        Int   => { alloc::strbuf::push_int(sb, i64(v))? }
        Float => { alloc::strbuf::push_float(sb, f64(v))? }
        _     => { alloc::strbuf::push_uint(sb, u64(v))? }
      }
      _ => { alloc::strbuf::push_uint(sb, u64(v))? }
    }
    ## An **aggregate** renders field by field: `{ name = value, … }`, recursing
    ## via `comptime for` over `typeinfo(T).fields` and `v.(f)` field projection.
    Struct(fs) => {
      alloc::strbuf::push_str(sb, "{ ")?
      mut first : bool = true
      comptime for f in typeinfo(T).fields {
        if not first { alloc::strbuf::push_str(sb, ", ")? }
        first = false
        alloc::strbuf::push_str(sb, f.name)?
        alloc::strbuf::push_str(sb, " = ")?
        display(f.type, v.(f), sb)?
      }
      alloc::strbuf::push_str(sb, " }")?
    }
    ## An **enum** renders the active variant's NAME, followed by its payload in
    ## parentheses when the variant carries one (`Some(3)`, `None`). Reached through the
    ## comptime variant match (Comptime §5.5): `comptime for var in
    ## typeinfo(T).variants` unrolls one `match` arm per variant, `var.name` is the
    ## variant's comptime `str`, and `comptime match var.payload` (an `Option(type)`,
    ## appendix §4.1) folds per variant — `Some(_)` for a payloaded variant (rendered
    ## recursively via `display(p, …)`), `None` for a unit variant (name only). A
    ## multi-component payload binds as a tuple `p`; rendering it needs a `Tuple` arm
    ## (additive) — single-component + unit variants render today. Two additive limits: a
    ## multi-component (tuple) payload, and a GENERIC enum INSTANCE as the display type-arg
    ## (`display(Option(u64), …)`) — the latter needs monomorphizing `display` over a
    ## generic-instance type argument (a valid-symbol tag for `Option(u64)` + collecting the
    ## nested instance). A SIMPLE (non-generic) enum renders today.
    Enum(_) => {
      match v {
        comptime for var in typeinfo(T).variants {
          T.(var)(p) => {
            alloc::strbuf::push_str(sb, var.name)?
            comptime match var.payload {
              Some(_) => comptime match typeinfo(p) {
                ## a MULTI-component payload binds as a TUPLE — its own `display` already brackets it
                ## `(a, b)`, so emit it directly (no extra wrap) → `Pair(3, 4)`, not `Pair((3, 4))`.
                Tuple(_) => { display(p, sb)? }
                ## a single-component payload renders inside the variant's own parens → `Some(3)`.
                _ => {
                  alloc::strbuf::push_str(sb, "(")?
                  display(p, sb)?
                  alloc::strbuf::push_str(sb, ")")?
                }
              }
              None => {}
            }
          }
        }
      }
    }
    ## A **tuple** `(a, b, …)` renders each component in order inside parentheses, comma-separated —
    ## reached through a `Tuple` kind (CT §8.2). `comptime for c in typeinfo(T).components` unrolls one
    ## step per component, `c.type` is the component's comptime type and `v.(c)` projects it (a word
    ## read `Index(v, i)`), rendered recursively. Scalar/pointer components render today.
    Tuple(cs) => {
      alloc::strbuf::push_str(sb, "(")?
      mut first : bool = true
      comptime for c in typeinfo(T).components {
        if not first { alloc::strbuf::push_str(sb, ", ")? }
        first = false
        display(c.type, v.(c), sb)?
      }
      alloc::strbuf::push_str(sb, ")")?
    }
    ## A **fixed array** `[T; N]` renders `[e0, e1, …]` — each element in order, comma-separated —
    ## reached through the `Array` kind. `comptime for e in typeinfo(T).elements` unrolls one step per
    ## element (N steps), `e.type` is the element type and `v.(e)` projects element i (a word read
    ## `Index(v, i)`). Scalar/pointer elements render today (aggregate elements need by-ref, deferred).
    Array(elem, n) => {
      alloc::strbuf::push_str(sb, "[")?
      mut first : bool = true
      comptime for e in typeinfo(T).elements {
        if not first { alloc::strbuf::push_str(sb, ", ")? }
        first = false
        display(e.type, v.(e), sb)?
      }
      alloc::strbuf::push_str(sb, "]")?
    }
    ## A `str` renders its bytes verbatim (interleaved literal text of a variadic `print`).
    Str => { alloc::strbuf::push_str(sb, v)? }
    ## A **scalar leaf** dispatches on its `kind` (appendix §4.1): `bool` as
    ## `true`/`false`, a signed `Int` with a leading `-`, a `Float` via the float
    ## formatter, everything else (unsigned / raw bits) as base-10.
    Scalar(b, k) => comptime match k {
      Bool  => { if v { alloc::strbuf::push_str(sb, "true")? } else { alloc::strbuf::push_str(sb, "false")? } }
      Char  => { alloc::strbuf::push_char(sb, v)? }
      Int   => { alloc::strbuf::push_int(sb, i64(v))? }
      Float => { alloc::strbuf::push_float(sb, f64(v))? }
      _     => { alloc::strbuf::push_uint(sb, u64(v))? }
    }
    _ => { alloc::strbuf::push_uint(sb, u64(v))? }
  }
  Result(usize, AllocError).Ok(0)
}

## **Comptime-variadic** formatted build (Functions §7.1 / Stdlib §2.7): a `{}`-template
## with the trailing arguments, building and returning an owned `String` over arena
## `a`. `s := format("x = {}, y = {}\n", ar, x, y)` yields the rendered text; the
## caller owns the buffer and frees it (`string::free`). The value-returning comptime
## variadic inlines to a block whose value is the built buffer; binding it
## (`s := format(…)`) rides block-aggregate-value binding. A **trapping** convenience
## (it traps on OOM via `trap_oom`), returning the built `String` directly — **not**
## `Result`: `format` is an inlined comptime-variadic, so a `?` inside would propagate
## from the *call site's* enclosing function, and wrapping the `@owning` `String` in a
## `Result` snags linearity. The recoverable in-memory render is the `Writer` surface
## directly (`sb.write(bytes)? -> Result(usize, AllocError)`).
pub format := fn(fmt : str, a : ptr(mut Arena), args : ...) -> alloc::strbuf::StrBuf {
  mut sb := alloc::strbuf::strbuf(a, 64)
  comptime for x in args {
    rr := display(x, sb)
    trap_oom(rr)
  }
  ## A constructor copy (a non-place aggregate) rather than the local place `sb` —
  ## yielding a whole aggregate *place* by value is a separate lowering path. The
  ## body-expression (no `return`) is the inlined block's value. `by_value`
  ## **consumes** `sb` and returns a fresh handle owning the pages (move-out).
  sb.by_value()
}
