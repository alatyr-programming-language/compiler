## fmt fixture — DECL ATTRIBUTES. The parser consumes every `@…` a declaration carries and records
## none of them on the `Decl`, so fmt dropped them all. None of the drops is a formatting difference:
##   a function-valued `@convert` constructor  (Types §4.6)  — `Celsius(42)` no longer resolves at all;
##   `NonZero := @require(is_nonzero) u32` (Types §8.1)  — the validity contract silently disappears;
##   `@export("sym") producer := fn …`     (Modules §6.3) — the symbol is never exported;
##   `consumer := @extern("sym") fn() -> u64` (Modules §7) — a BODYLESS import came back WITH a body
##       (`{ 0 }`), DEFINING the symbol it was meant to import, so `extern_call` ran 42 -> 0.
## `@abi(naked)` fns (`naked_add`, `raw_asm_*`) lost their attribute the same way and link-errored.
## All are recovered verbatim by source-scan: the run of `@attr(args)` tokens after the `:=`, the run
## written before the NAME, and — for the bodyless form — a source check that a `{` really follows the
## return type. Returns 42.
is_nonzero := fn(v : u32) -> bool { return v != 0 }

NonZero := @require(is_nonzero) u32

Celsius := struct { deg : u64 }

mkc := @convert fn(x : u64) -> Celsius { return Celsius(deg = x) }

@export("fmt_attrs_impl") producer := fn() -> u64 {
  return 20
}

consumer := @extern("fmt_attrs_impl") fn() -> u64

main := fn() -> u64 {
  x := NonZero(5)
  c := Celsius(22)
  return consumer() + c.deg
}
