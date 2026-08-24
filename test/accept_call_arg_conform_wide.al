## check-only companion to `accept_call_arg_conform` — the shapes whose CONFORMANCE must stay accepted
## even where the lower/linker has a separate, pre-existing limitation (an overload set that does not
## link, `alloc`-free variadics), so they cannot be run end-to-end. Each is a REFUSAL TO JUDGE in
## `call_arg_lit_incompatible`, and each has its spec reason:
##   - a GENERIC callee (`id(str, "ok")`): the parameter's declared type is the type-PARAMETER `T`,
##     bound by monomorphization at the call (Functions §1.3) — conforming for every `T`;
##   - an OVERLOAD SET (`f(u64)` + `f(str)` given `f("ok")`): sema does not resolve overloads, so a
##     parameter type read off "one of them" would reject the other one's legal call;
##   - a BRAND parameter (`Meters`) and a GENERIC-INSTANCE parameter (`Option(u64)`): `resolve_ty`
##     leaves both UNKNOWN, and the whitelist never rejects on an unknown sink — brand identity is
##     always explicit (Types §4.2), and generic-payload conformance is not judged here;
##   - a `ptr(T)` parameter fed the MEM-7/8 `usize`↔`ptr` seam;
##   - a comptime-VARIADIC `...` rest and a DEFAULTED parameter: the positional argument index is not
##     a parameter index there (Functions §5.1/§7.2);
##   - an `in out` parameter (pmode 2): it takes a PLACE argument (Functions §2.3), a judgement this
##     literal rule does not make;
##   - `embed(path)` into a `[u8; N]` parameter: `embed` folds to a StrLit NODE while its spec surface
##     is `[u8; N]` (Comptime §2.4) — a StrLit node is NOT proof of a `str`-typed value.
Meters := brand(u64)

id := fn(T : type, x : T) -> T { return x }
ovl := fn(n : u64) -> u64 { return n }
ovl := fn(s : str) -> u64 { return s.len() }
branded := fn(m : Meters) -> u64 { return u64(m) }
opt := fn(o : Option(u64)) -> u64 { return o.unwrap() }
thru := fn(p : ptr(u64)) -> u64 { return deref(p) }
seam := fn(h : usize) -> u64 { return thru(unchecked bitcast(ptr(u64), h)) }
vari := fn(xs : ...) -> u64 { return 0 }
defd := fn(n : u64 = 7) -> u64 { return n }
bumped := fn(in out n : u64) -> u64 { n = n + 1; return n }
bytes4 := fn(b : [u8; 4]) -> u64 { return u64(b[0]) }

main := fn() -> u64 {
  a := id(str, "ok")
  b := ovl("ok")
  c := branded(Meters(3))
  d := opt(Option(u64).Some(4))
  x := 5
  e := seam(unchecked bitcast(usize, ptr(x)))
  g := vari("a", true, 1)
  h := defd()
  mut m := 9
  k := bumped(m)
  n := bytes4(embed("test/embed_fixture.bin"))
  return a.len() + b + c + d + e + g + h + k + n
}
