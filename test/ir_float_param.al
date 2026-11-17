## #1728: a float parameter does not cross between the shared IR and a legacy-emitted function. The
## selectors take every parameter from an integer argument register; legacy x86_64 passes a float in
## `%xmm0`, so an IR-built callee read the wrong register: x86_64 answered 1 where 42 was due (parent;
## `x86-legacy` 42). Such a function now stays legacy.
##   * `f1`: a float parameter, a scalar result;
##   * `f2`: a float parameter, an enum-instance result;
##   * `f3` / `f4`: a float parameter after an `in out` one.
## `main` holds a float local, so the shared IR refuses it and it stays LEGACY-emitted. Each check
## returns its own code; 42 when all hold. x86_64 only, as the other #1033 crossing fixtures.
E := enum { A, B }
f1 := fn(x : f64) -> u64 { unchecked bitcast(u64, x) }
f2 := fn(x : f64) -> Result(u64, E) { Result(u64, E).Ok(unchecked bitcast(u64, x)) }
f3 := fn(in out n : u64, x : f64) -> Result(usize, E) {
  n = unchecked bitcast(u64, x)
  Result(usize, E).Ok(8)
}
f4 := fn(in out n : u64, x : f64) -> u64 {
  n = unchecked bitcast(u64, x)
  8
}

main := fn() -> u64 {
  w : f64 = 3.14159265358979
  want := unchecked bitcast(u64, w)
  if f1(3.14159265358979) != want { return 1 }
  match f2(3.14159265358979) {
    Ok(v) => { if v != want { return 2 } }
    Err(e) => { return 3 }
  }
  mut n : u64 = 0
  match f3(n, 3.14159265358979) {
    Ok(v) => { if n != want { return 4 } }
    Err(e) => { return 5 }
  }
  mut m : u64 = 0
  z := f4(m, 3.14159265358979)
  if m != want { return 6 }
  if f1(0.5) != 4602678819172646912 { return 7 }
  42
}
## expect(x86_64): run 42
