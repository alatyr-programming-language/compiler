## selfhost::lower::decl_index — the per-decl NAME INDEX the emit hot path resolves names through.
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower` — which is what lets it name `lower.al`'s non-`pub` items
## (`DNH`, `decl_get`, `fn_is_convert`) by bare name (Modules §3, privacy flows DOWN).
##
## The nine index globals (`DNH`/`DNH_N`/`DIC`, `DNI_B`/`DNI_L`/`DNI_NB`/`DNI_N`, `DCV_L`/`DCV_N`)
## DELIBERATELY stay declared in `src/lower.al`: several of `lower.al`'s own scans read `DNH`/`DNH_N`
## inline rather than through `dnh_skip`, and an ancestor cannot name a descendant's item without a
## path + `pub`. Keeping the storage in the parent and the LOGIC here is the shape §3 rewards — every
## read and write below addresses `lower__<NAME>(%rip)` through the ancestor chain.
##
## `lower.al` re-imports the eleven externally-called entry points by BARE NAME
## (`(name_hash, …) := decl_index`) rather than calling them as `decl_index::name_hash(…)`. That is
## not cosmetic: a QUALIFIED cross-module call site does not expand an `@inline` callee, while a
## bare-name one does (measured), so the bare-name import is the form that keeps the boundary
## `@inline`-transparent for every band that follows.
(Decl) := ast

pub name_hash := fn(src : ptr(u8), s : usize, n : usize) -> usize {
  w := str_at((src + s), n)
  mut h := 1469598103934665603                              ## FNV-1a 64-bit offset basis
  mut i := 0
  while i < n {
    unchecked { h = (h ^ usize(bytes(w)[i])) * 1099511628211 }   ## xor byte, * FNV prime (wrapping)
    i = i + 1
  }
  h
}
## true → decl index `i` CANNOT match the target name `th` (its precomputed hash differs), so the caller
## may skip it without `decl_get`/`streq`. Conservative: returns false (do the full check) whenever the
## fast path is unavailable or stale, so it never hides a real match.
pub dnh_skip := fn(cnt : usize, i : usize, th : usize) -> bool {
  if DNH == 0 { return false }
  if DNH_N != cnt { return false }
  rt::rec_get(unchecked bitcast(ptr(mut u8), DNH), i) != th
}
## Is decl `i` a `@convert` fn, per the precomputed `DIC` (mirrors `d.is_fn and fn_is_convert`)? `has` reports
## whether the fast path is live (DIC built + sized); callers fall back to the direct scan when it is not.
pub dic_is_convert := fn(cnt : usize, i : usize) -> bool {
  if DIC == 0 { return false }
  if DNH_N != cnt { return false }
  rt::rec_get(unchecked bitcast(ptr(mut u8), DIC), i) == 1
}
pub dic_live := fn(cnt : usize) -> bool { DIC != 0 and DNH_N == cnt }
dni_live := fn(cnt : usize) -> bool { DNI_B != 0 and DNI_N == cnt and DNH != 0 and DNH_N == cnt }
## First / one-past-last CURSOR into the candidate list for target hash `th`, and the decl index at a
## cursor. Degrade to the full `[0, cnt)` identity scan whenever the index is not live.
pub dni_lo := fn(cnt : usize, th : usize) -> usize {
  if dni_live(cnt) == false { return 0 }
  rt::rec_get(unchecked bitcast(ptr(mut u8), DNI_B), th & (DNI_NB - 1))
}
pub dni_hi := fn(cnt : usize, th : usize) -> usize {
  if dni_live(cnt) == false { return cnt }
  rt::rec_get(unchecked bitcast(ptr(mut u8), DNI_B), (th & (DNI_NB - 1)) + 1)
}
pub dni_at := fn(cnt : usize, j : usize) -> usize {
  if dni_live(cnt) == false { return j }
  rt::rec_get(unchecked bitcast(ptr(mut u8), DNI_L), j)
}
## The `@convert` candidate cursors (same degradation contract as `dni_*`).
dcv_live := fn(cnt : usize) -> bool { DCV_L != 0 and DNI_N == cnt and dic_live(cnt) }
pub dcv_hi := fn(cnt : usize) -> usize {
  if dcv_live(cnt) == false { return cnt }
  DCV_N
}
pub dcv_at := fn(cnt : usize, j : usize) -> usize {
  if dcv_live(cnt) == false { return j }
  rt::rec_get(unchecked bitcast(ptr(mut u8), DCV_L), j)
}
## FNV-1a of a `str` LITERAL, matching `name_hash` byte for byte — so an operator glyph (`"+"`) spelled
## as a literal indexes into the same buckets as the decl names hashed from source.
pub str_name_hash := fn(w : str) -> usize {
  n := w.len
  mut h := 1469598103934665603
  mut i := 0
  while i < n {
    unchecked { h = (h ^ usize(bytes(w)[i])) * 1099511628211 }
    i = i + 1
  }
  h
}
## Build `DNH` (per-decl name hash) + `DIC` (per-decl is-@convert flag) + the `DNI` bucket index + the
## `DCV` convert list for `decls` into the persistent arena `mar`. A few O(cnt) passes; called once per
## `emit_program`, after lambda lifting finalizes `decls`.
pub build_decl_name_hash := fn(decls : ptr(rt::Vec), src : ptr(u8), in out mar : rt::Arena) {
  cnt := rt::vec_len(deref(decls))
  base := rt::bump(mar, cnt * 8 + 8)
  dbase := rt::bump(mar, cnt * 8 + 8)
  mut nconv := 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    rt::rec_set(unchecked bitcast(ptr(mut u8), base), i, name_hash(src, d.name_start, d.name_len))
    mut cv := 0
    if d.is_fn and fn_is_convert(src, d.name_start, d.name_len) { cv = 1 }
    rt::rec_set(unchecked bitcast(ptr(mut u8), dbase), i, cv)
    if cv == 1 { nconv = nconv + 1 }
    i = i + 1
  }
  DNH = base
  DIC = dbase
  DNH_N = cnt
  ## bucket count = the smallest power of two ≥ 2·cnt (load factor ≤ 0.5), floor 64
  mut nb := 64
  while nb < cnt * 2 { nb = nb * 2 }
  bb := rt::bump(mar, nb * 8 + 16)
  cur := rt::bump(mar, nb * 8 + 16)
  lb := rt::bump(mar, cnt * 8 + 8)
  mut b := 0
  while b < nb + 1 {
    rt::rec_set(unchecked bitcast(ptr(mut u8), bb), b, 0)
    rt::rec_set(unchecked bitcast(ptr(mut u8), cur), b, 0)
    b = b + 1
  }
  ## COUNT into slot `bucket + 1`, so the inclusive prefix below leaves `bb[b]` = bucket `b`'s START.
  i = 0
  while i < cnt {
    h := rt::rec_get(unchecked bitcast(ptr(mut u8), base), i) & (nb - 1)
    rt::rec_set(unchecked bitcast(ptr(mut u8), bb), h + 1, rt::rec_get(unchecked bitcast(ptr(mut u8), bb), h + 1) + 1)
    i = i + 1
  }
  b = 1
  while b < nb + 1 {
    rt::rec_set(unchecked bitcast(ptr(mut u8), bb), b, rt::rec_get(unchecked bitcast(ptr(mut u8), bb), b) + rt::rec_get(unchecked bitcast(ptr(mut u8), bb), b - 1))
    b = b + 1
  }
  ## FILL in increasing decl order → each bucket's slice is ascending, preserving scan order.
  i = 0
  while i < cnt {
    h := rt::rec_get(unchecked bitcast(ptr(mut u8), base), i) & (nb - 1)
    p := rt::rec_get(unchecked bitcast(ptr(mut u8), bb), h) + rt::rec_get(unchecked bitcast(ptr(mut u8), cur), h)
    rt::rec_set(unchecked bitcast(ptr(mut u8), lb), p, i)
    rt::rec_set(unchecked bitcast(ptr(mut u8), cur), h, rt::rec_get(unchecked bitcast(ptr(mut u8), cur), h) + 1)
    i = i + 1
  }
  DNI_B = bb
  DNI_L = lb
  DNI_NB = nb
  DNI_N = cnt
  cvb := rt::bump(mar, nconv * 8 + 8)
  mut k := 0
  i = 0
  while i < cnt {
    if rt::rec_get(unchecked bitcast(ptr(mut u8), dbase), i) == 1 {
      rt::rec_set(unchecked bitcast(ptr(mut u8), cvb), k, i)
      k = k + 1
    }
    i = i + 1
  }
  DCV_L = cvb
  DCV_N = k
  ## the sibling index in `lower_layout` (own hash + arrays; the import edge only runs this way)
  lower_layout::build_layout_name_index(decls, src, mar)
}
