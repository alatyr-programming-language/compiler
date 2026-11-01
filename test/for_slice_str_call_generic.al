## #1177 — `for s in f(str, ...)` over a GENERIC call whose declared return is `Slice(T)`, with
## `T = str` from the call's type argument, binds two-word `str` elements, like the concrete
## `-> Slice(str)` call in `for_slice_str_call`. Expected exit 32 (3 then 2). The parent compiler at
## 2cf60b45 (x86_64) read one word per element and the program exited 1; so did PR #1224's first head 1618dd05.
pass := fn(T : type, t : Slice(T)) -> Slice(T) {
  t
}

main := fn() -> u64 {
  t : [str; 2] = ["abc", "de"]
  mut n : u64 = 0
  for s in pass(str, t[0..2]) {
    n = n * 10 + u64(s.len)
  }
  n
}
## expect: run 32
