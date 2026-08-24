## TYP-6 / Types §4.6 — the MIRROR direction: a struct literal argument against a `str` parameter.
## Same settlement as the `str`-into-nominal case — a `@convert` fires only through an explicit
## `T(v)`, never implicitly (§4.3/§4.6) — so there is no reading under which `f(S(a = 1))` conforms.
## It built and returned 0 silently.
S := struct { a : u64 }

f := fn(s : str) -> u64 { return s.len() }

main := fn() -> u64 { return f(S(a = 1)) }
