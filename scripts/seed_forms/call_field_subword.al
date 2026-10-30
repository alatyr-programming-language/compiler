## #1228 — a field read straight off a struct-returning call reads the wrong field when the struct
## has sub-word (`bool`, `u8`) fields. Due 24: eek 4 + 10 * stride 2. Binding the result first
## (`d := mk(1); d.eek`) reads it correctly.
Info := struct { is_slice : bool, eek : u8, stride : usize }

mk := fn(q : usize) -> Info {
  Info(is_slice = true, eek = 4, stride = 2)
}

main := fn() -> u64 {
  u64(mk(1).eek) + 10 * u64(mk(1).stride)
}
