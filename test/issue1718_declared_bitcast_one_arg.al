## #1718 — a program-declared one-parameter `bitcast` is an ordinary call (Grammar §2.3, Declarations
## §6.1): 10 + 32. NON-VACUOUS: on the parent da8f96af the parser read `bitcast(10)` as the two-argument
## reinterpret and refused the program at parse time (exit 1).
bitcast := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  bitcast(10) + 32
}
## expect: run 42
