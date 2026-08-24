## Regression: THREE-type-parameter monomorphization. A generic fn `pick3(A, B, C, …)` returning a
## 3-type-param generic enum `Tri(A, B, C)`, monomorphized + mangled by all three type-args
## (`…__pick3__u64__u64__u64`), erasing three leading type-args and binding gp/gp2/gp3; the 3-param
## generic enum is sized/constructed/matched. Exercises the mono machinery's third type-param.
Tri := fn(A : type, B : type, C : type) -> type { return enum { First(A), Second(B), Third(C) } }

pick3 := fn(A : type, B : type, C : type, sel : u64, a : A, b : B, c : C) -> Tri(A, B, C) {
  if sel == 0 { return Tri(A, B, C).First(a) }
  if sel == 1 { return Tri(A, B, C).Second(b) }
  return Tri(A, B, C).Third(c)
}

main := fn() -> u64 {
  t := pick3(u64, u64, u64, 2, 10, 20, 12)
  match t {
    First(x) => { return x }
    Second(y) => { return y }
    Third(z) => { return z + 30 }
  }
}
