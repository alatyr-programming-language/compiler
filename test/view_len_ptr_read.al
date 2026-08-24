## e2e (Types §7 — a `[T]`/`str` view IS its two-word {ptr, len} pair wherever it appears, so `.len`
## and `.ptr` are reads of that pair's two words). A view VALUE with no frame home matched no `Field`
## arm and fell through to the slot default, which read a garbage frame word — in practice 0. Silent
## wrong values (I11), every one measured before this fixture existed:
##   "hi\n".len == 3                 was FALSE
##   "hi\n".ptr                      handed a write(2) a NULL buffer, so it wrote NOTHING — the
##                                   shipped workaround was to bind the literal to a local first
##   sub(s, 0, 5).len                answered 0
##   s[0..5].len                     answered 0
##   bytes(s).len                    answered 0
##   xs[2..6].len (a scalar array)   answered 0
## CONTENT, not just a length: the `.ptr` probes go through a real `write(2)` whose byte COUNT and
## whose captured stdout both have to be right (see `view_len_ptr_read.out`), and the lengths checked
## are all DIFFERENT (3/5/2/4/8) so one wrong pair cannot be masked by another. The last two checks
## are the POSITIVE CONTROLS — `.len` on a plain `str` LOCAL and on a struct FIELD, the placed forms
## that always worked and must stay byte-identical. Returns 42.
sys_write := @abi(syscall) fn(num : usize, fd : usize, buf : ptr(u8), len : usize) -> isize

P := struct { name : str, n : u64 }

main := fn() -> u64 {
  s : str = "AliceBob"
  xs : [u64; 8] = [1, 2, 3, 4, 5, 6, 7, 8]
  p := P(name = "Bo", n = 7)
  mut k : u64 = 0
  if "hi\n".len == 3 { k += 1 }              ## a str LITERAL's len
  if sub(s, 0, 5).len == 5 { k += 1 }        ## a `sub(…)` view's len
  if s[0..2].len == 2 { k += 1 }             ## a range sub-view's len
  if bytes(s).len == 8 { k += 1 }            ## a `bytes(…)` view's len
  if xs[2..6].len == 4 { k += 1 }            ## a typed ARRAY range slice's len
  ## `.ptr` off a homeless view, through a real write(2): the byte COUNT must come back, and the
  ## bytes themselves are checked against the stdout golden.
  w1 := unchecked sys_write(1, 1, "hi\n".ptr, 3)
  if w1 == 3 { k += 1 }
  w2 := unchecked sys_write(1, 1, sub(s, 0, 5).ptr, 5)
  if w2 == 5 { k += 1 }
  w3 := unchecked sys_write(1, 1, bytes(s).ptr, 8)
  if w3 == 8 { k += 1 }
  if s.len == 8 { k += 1 }                   ## POSITIVE CONTROL — a `str` LOCAL
  if p.name.len == 2 { k += 1 }              ## POSITIVE CONTROL — a `str` FIELD
  if k == 10 { return 42 }
  k
}
