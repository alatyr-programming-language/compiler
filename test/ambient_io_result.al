## e2e (P3 ambient stdlib — a Result-returning std fn across modules): calls `std::io::write`
## (returns `Result(usize, IoError)`) ambiently and MATCHES on the cross-module `Result`. Exercises
## more of the ambient path than `ambient_io`: `bytes(<string literal>)` as a by-reference arg (a
## str temp block seen through the `bytes` view), a cross-module enum RESULT (`Result`/`IoError`
## defined in the injected `base`/`std::io`), and `match` on its `Ok`/`Err` discriminant. The
## string is 10 bytes ("via write\n"); a successful write returns `Ok(10)` → this exits 42.
main := fn() -> u64 {
  r := std::io::write(1, bytes("via write\n"))
  match r {
    Result::Ok(n) => { if n == 10 { return 42 } ; 1 }
    Result::Err(e) => { 99 }
  }
}
