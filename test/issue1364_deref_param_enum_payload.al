## e2e / issue #1364 — `Option(E).Some(deref(p))` with `p` a pointer PARAMETER and `E` a multi-word enum
## delivers every word of the enum.
##
## The payload width and the value read asked only the resolver for pointer LOCALS, which knows no
## parameter, and a generic `p : ptr(T)` at `T = Option(u64)` was not even bound as a pointer to an enum
## (`enum_decl_of` matches a declared name, not an application). So the concrete form and the generic
## form at `T = EN` kept the tag and lost the payload, and the generic form at `T = Option(u64)`
## returned 0 for 42 (a wrong value on the #1340 head; main refused it). A user function NAMED like a
## generic prelude function (`first`, `base::slice::first`) has a separate caller-side defect, #1365, so
## the concrete function here is `first_concrete`.
##
## Each check owns a code from 100 up; 42 means every shape delivered the whole enum.
## Parent `32f0f6e8` (x86_64, omen): built rc 0 and returned 100 where 42 was due.
EN := enum { A(u64), B(u64, u64), C }

first_concrete := fn(p : ptr(EN)) -> Option(EN) { Option(EN).Some(deref(p)) }
first := fn(T : type, p : ptr(T)) -> Option(T) { Option(T).Some(deref(p)) }

key := fn(e : EN) -> u64 {
  match e {
    EN::A(x) => { x }
    EN::B(x, y) => { x + y }
    EN::C => { 1 }
  }
}

## (1) a concrete function: SIGSEGV on main
check_concrete := fn() -> u64 {
  e := EN.B(20, 22)
  o := first_concrete(ptr(e))
  match o {
    Option::Some(x) => { if key(x) != 42 { return 100 } }
    Option::None => { return 101 }
  }
  0
}

## (2) the generic at `T = EN`: the payload word came back 0 on main
check_generic_enum := fn() -> u64 {
  e := EN.B(5, 22)
  o := first(EN, ptr(e))
  match o {
    Option::Some(x) => { if key(x) != 27 { return 102 } }
    Option::None => { return 103 }
  }
  0
}

## (3) the generic at `T = Option(u64)`, a nested `match`: 0 for 42 on the #1340 head
check_generic_option := fn() -> u64 {
  e := Option(u64).Some(42)
  o := first(Option(u64), ptr(e))
  match o {
    Option::Some(x) => {
      match x {
        Option::Some(v) => { if v != 42 { return 104 } }
        Option::None => { return 105 }
      }
    }
    Option::None => { return 106 }
  }
  0
}

main := fn() -> u64 {
  r1 := check_concrete()
  if r1 != 0 { return r1 }
  r2 := check_generic_enum()
  if r2 != 0 { return r2 }
  r3 := check_generic_option()
  if r3 != 0 { return r3 }
  42
}
## expect: run 42
