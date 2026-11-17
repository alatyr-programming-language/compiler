## #1719 / spec#166, fail closed. A program declaration under a prelude intrinsic's name, called with
## an argument it does not accept. Under shadowing the call is ill-formed; under overloading it is the
## prelude's own call. Under neither is it a call of this declaration with that argument, which is what
## it compiled to once #1434 routed it here. Until spec#166 is decided it is refused, located at the
## argument, because the argument's type is not PROVEN accepted.
## Shape: a `u64` local into `s : str` (one word where two are due).
## Native x86_64 (omen, tree Stage1): parent 8375ac06 answered 38 (wrong); the first #1719 refusal
## (6b43c402) built it with no diagnostic and the program died with SIGSEGV (139).
len := fn(s : str) -> u64 { 7 }
main := fn() -> u64 {
  n : u64 = 4
  len(n) + 38
}
## expect: reject "type mismatch" "at line 12"
