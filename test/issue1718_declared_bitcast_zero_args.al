## #1718 — a program-declared `bitcast` with no parameters is an ordinary call (Grammar §2.3,
## Declarations §6.1): 10 + 32. NON-VACUOUS: on the parent da8f96af the parser read `bitcast(` as the
## two-argument reinterpret, ran past the `)` and refused the program at parse time (exit 1).
bitcast := fn() -> u64 { 10 }
main := fn() -> u64 {
  bitcast() + 32
}
## expect: run 42
