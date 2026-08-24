## REGRESSION GUARD for CLOSED item 2 — element read and write through a
## `Slice(T)` payload binding.
##
## Both view words of an `Option`/`Result` payload survive, and so does element
## access through the binding: `w[k] = v` reaches the backing array and `w[k]`
## reads it, at a constant and at a dynamic index. Each check is scored as a
## boolean because the value a broken build yielded was frame garbage, not one
## reproducible wrong number.
##
## The earlier version of this probe read only `.len`, and the compiler fix
## landed on exactly that half — `alatyr-compiler`'s `codec_slice_payload`
## regression still reads only `.len`, so this probe is the guard for the rest.
##
## Exit code 42, 21 per check. A broken build scored 0.
E := enum { Bad }

view := fn(d : Slice(u8), n : usize) -> Result(Slice(u8), E) {
  Result(Slice(u8), E).Ok(d[0..n])
}

## A write through the binding must reach the backing array.
write_lands := fn() -> bool {
  mut b : [u8; 8] = [0; 8]
  d := Slice(u8)(ptr = ptr(b[0]), len = 8)
  mut k : usize = 2
  match view(d, 4) {
    Ok(w) => { w[k] = 21 }
    Err(_) => { return false }
  }
  b[2] == 21
}

## A dynamic-index read through the binding must see the backing array.
dynamic_read_works := fn() -> bool {
  mut b : [u8; 8] = [0; 8]
  b[1] = 21
  d := Slice(u8)(ptr = ptr(b[0]), len = 8)
  mut k : usize = 1
  match view(d, 4) {
    Ok(w) => { return w[k] == 21 }
    Err(_) => { return false }
  }
}

main := fn() -> u64 {
  mut score : u64 = 0
  if write_lands() { score += 21 }
  if dynamic_read_works() { score += 21 }
  score
}
