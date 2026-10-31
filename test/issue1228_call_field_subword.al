## e2e / issue #1228 — a field read straight off a struct-returning call, when the struct has sub-word
## fields.
##
## Types §6.1: a field access reads the named field of the struct value, a call's result included. A
## struct with a `bool` / `u8` field is built at its byte offsets, and the call returns that image word
## by word in registers. `mk(1).eek` picked the register by counting one word per field, so `eek` (byte 1
## of word 0) read `stride` (word 1) and `stride` read the register after it. Binding first
## (`d := mk(1); d.eek`) was already right.
##
## Each check owns a code from 10 up; 42 means all held.
Info := struct { is_slice : bool, eek : u8, stride : usize }
Info5 := struct { is_slice : bool, eek : u8, stride : usize, ess : usize, esl : usize }
Signed := struct { flag : bool, lo : i8, mid : i16, wide : i32, tail : u64 }

mk := fn(q : usize) -> Info {
  Info(is_slice = true, eek = 4, stride = 2)
}
mk5 := fn(q : usize) -> Info5 {
  Info5(is_slice = true, eek = 4, stride = 2, ess = 7, esl = 9)
}
mks := fn(q : usize) -> Signed {
  Signed(flag = false, lo = 0 - 5, mid = 0 - 300, wide = 0 - 70000, tail = 11)
}

main := fn() -> u64 {
  ## the issue's three bold rows
  if u64(mk(1).eek) + 10 * u64(mk(1).stride) != 24 { return 10 }
  if u64(mk5(1).eek) + 10 * u64(mk5(1).stride) != 24 { return 11 }
  if not (mk5(1).eek == 4) { return 12 }
  ## every field of the five-field struct, and the bool
  if mk5(1).is_slice == false { return 13 }
  if mk5(1).ess != 7 { return 14 }
  if mk5(1).esl != 9 { return 15 }
  ## signed sub-word fields keep their sign; a false bool next to them reads false
  if mks(1).flag { return 16 }
  if mks(1).lo != 0 - 5 { return 17 }
  if mks(1).mid != 0 - 300 { return 18 }
  if mks(1).wide != 0 - 70000 { return 19 }
  if mks(1).tail != 11 { return 20 }
  ## the bound form agrees
  d := mk5(1)
  if d.eek != mk5(1).eek { return 21 }
  42
}
