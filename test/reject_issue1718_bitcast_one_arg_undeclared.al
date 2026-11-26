## #1718 — with no program declaration of `bitcast`, a one-argument `bitcast(x)` is not the prelude's
## reinterpret, which takes a target type and a value. It is an ordinary call with nothing to resolve
## to, refused at its line. NON-VACUOUS: on the parent da8f96af the parser read it as the two-argument
## reinterpret, ran past its `)` and refused the file with no source position.
main := fn() -> u64 {
  x : u64 = 3
  bitcast(x)
}
## expect: reject "unbound name" "at line 7"
