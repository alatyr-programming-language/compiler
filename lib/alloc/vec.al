## std::vec — growable arrays over a pluggable allocator (ROADMAP §3).
##
## The generic `Vec(T)` takes its backing from an **`Arena`** (region protocol,
## D84), not a direct `mmap`, so a compiler can run many vectors over one arena it
## owns and frees in one shot (the natural discipline for compiler passes). For a
## `u64` array use `Vec(u64)` — there is no separate concrete container.

## --- Generic `Vec(T)`, allocator-borne (ROADMAP §3) --------------------------
## The element-type-parametric growable array. Its storage comes from a pluggable
## **`Arena`** (the region allocator protocol, Stdlib §5 / D84) — NOT a direct
## `mmap` — so a compiler can run many vectors over one arena it owns and frees in
## one shot (the natural discipline for compiler passes).
##
## **Handle-based (Memory §5.3.1 / D19):** the vector stores the backing's arena
## **index** (a `Handle` value, `idx`), NOT a pointer — a long-lived reference into
## an arena is a handle (a number, no lifetime problem), resolved to a scoped pointer
## per access via `get`. It keeps a borrow of its arena (`arena`) to do that
## resolution (and to grow), so element ops need no extra argument; the scoped
## pointer `get` yields is used immediately and never stored. The element stride is
## `size(T)`, so one body serves any `T` (the type argument is comptime, erased).
##
## `@owning` (D86): a `Vec(T)` is a **linear handle** — non-copyable, consumed once
## by `free` (which only **discharges** it with `forget`; the backing pages belong to
## the arena, reclaimed when the caller frees it via `std::os::free`). Reads borrow
## through a const scoped reference (`in v`); mutations are `in out` place borrows.
pub Vec := fn(T : type) -> type { @owning struct { idx : usize, len : usize, cap : usize, arena : ptr(mut Arena) } }

## A new `Vec(T)` with room for `cap` elements (`cap >= 1`), backed by arena `a`
## (kept as a borrow for per-access resolution + grow). Traps on exhaustion (I11);
## stores the backing's handle index.
vec_in := fn(T : type, a : ptr(mut Arena), cap : usize) -> Vec(T) {
  idx := allocate(deref(a), T, cap * size(T), align(T)).expect("vec_in: allocator out of memory").idx
  return Vec(T)(idx = idx, len = 0, cap = cap, arena = a)
}

## `with_capacity` — the **canonical** v1 constructor name (Stdlib §160); the alias
## the spec mandates over the impl's `vec_in`. A thin (inlined) forwarder.
pub with_capacity := fn(T : type, a : ptr(mut Arena), cap : usize) -> Vec(T) {
  return vec_in(T, a, cap)
}

## `new` — the **basic** constructor: an empty vector backed by arena `a`, with a small
## default capacity (it grows on `push`). The stutter-free everyday name (Stdlib §160);
## reach for `with_capacity` when the final size is known, to avoid regrowth.
pub new := fn(T : type, a : ptr(mut Arena)) -> Vec(T) {
  return vec_in(T, a, 8)
}

## The backing's element-0 address, resolved from the stored handle via the stored
## arena (`get(arena, handle)`). The scoped pointer is returned to the immediate
## caller (an element op) and used at once — never stored (§5.3.1).
@inline vec_base := fn(T : type, v : ptr(Vec(T))) -> ptr(mut T) {
  aa := deref(deref(v).arena)
  p := alloc::get(T, aa, Handle(T)(idx = deref(v).idx))
  ## `get`'s result is scoped to the arena (§5.4) — returning it needs a deliberate
  ## first-class escape (§5.6 rule 5, the trusted allocator layer): fabricate the
  ## raw pointer under `unchecked`. Validity rests on the arena outliving the `Vec`.
  return unchecked bitcast(ptr(mut T), bitcast(usize, p))
}

## Append `x`, doubling the backing through the **arena** when full: allocate a new,
## larger block (the old one is left to the arena's bulk reclaim — the standard
## arena trade-off), copy the live elements, and re-cache the pointer. The arena is
## reached through the stored borrow (`deref(v.arena)`), so `push` keeps its
## two-argument shape.
pub push := fn(T : type, in out v : Vec(T), x : T) -> Result(usize, AllocError) {
  if v.len >= v.cap {
    new_cap := v.cap * 2
    nidx := allocate(deref(v.arena), T, new_cap * size(T), align(T))?.idx
    aa := deref(v.arena)
    oldp := alloc::get(T, aa, Handle(T)(idx = v.idx))
    newp := alloc::get(T, aa, Handle(T)(idx = nidx))
    old_int := unchecked bitcast(usize, oldp)
    new_int := unchecked bitcast(usize, newp)
    ## Copy the live elements **byte by byte** (a whole-aggregate store through a
    ## pointer is not lowered, but a `u8` is): works for any element type `T`.
    nbytes := v.len * size(T)
    mut k : usize = 0
    while k < nbytes {
      sb := unchecked bitcast(ptr(mut u8), old_int + k)
      db := unchecked bitcast(ptr(mut u8), new_int + k)
      deref(db) = deref(sb)
      k += 1
    }
    v.idx = nidx
    v.cap = new_cap
  }
  ab := deref(v.arena)
  base := alloc::get(T, ab, Handle(T)(idx = v.idx))
  base_int := unchecked bitcast(usize, base)
  elem := unchecked bitcast(ptr(mut T), base_int + v.len * size(T))
  deref(elem) = x
  v.len += 1
  return Result(usize, AllocError).Ok(v.len)
}

## The element at `i` (bounds-checked, traps when `i >= len`) — also the **read arm
## of the index operator** (D94 / Type System §4.5): `v[i]` desugars to `v.at(i)`.
## There is no separate `index` shim; the established named read `at` is the read
## the `[]` notation resolves to (write/range stay `index_set`/`index_range`). A
## non-consuming **scoped-reference** read (`in v : ptr(Vec(T))`); the UFCS
## auto-ref form `v.at(i)` (and `v[i]`) supplies the address, so no `mut` and no
## explicit `ptr` at the call — the caller keeps ownership and still `free`s `v`.
@inline pub at := fn(T : type, v : ptr(Vec(T)), i : usize) -> T {
  comptime if verify.checked { assert(i < deref(v).len) }
  base_int := unchecked bitcast(usize, vec_base(T, v))
  elem := unchecked bitcast(ptr(mut T), base_int + i * size(T))
  return deref(elem)
}

## The **`index_range` operator** (D94): `v[lo..hi]` desugars to `v.index_range(lo,
## hi)`, a borrowed `Slice(T)` view over the half-open element range (bounds-checked,
## traps on `lo > hi` or `hi > len`). The view aliases the backing and stays valid
## while `v` is unmodified (a `push` may move the region). A non-consuming read.
pub index_range := fn(T : type, v : ptr(Vec(T)), lo : usize, hi : usize) -> Slice(T) {
  comptime if verify.checked { assert(lo <= hi) }
  comptime if verify.checked { assert(hi <= deref(v).len) }
  base_int := unchecked bitcast(usize, vec_base(T, v))
  p := unchecked bitcast(ptr(T), base_int + lo * size(T))
  return Slice(T)(ptr = p, len = hi - lo)
}

## The **`index_set` operator** (D94): `v[i] = x` desugars to `v.index_set(i, x)`,
## the bounds-checked element write. The receiver is taken **by scoped pointer**
## (`ptr(mut Vec(T))`) — like `index`/`at` — so the write borrows `v` (it is
## not consumed); it writes the backing heap directly (the `set` body, through the
## pointer) rather than the `{idx,len,cap}` handle.
pub index_set := fn(T : type, v : ptr(mut Vec(T)), i : usize, x : T) {
  comptime if verify.checked { assert(i < deref(v).len) }
  ab := deref(deref(v).arena)
  base := alloc::get(T, ab, Handle(T)(idx = deref(v).idx))
  base_int := unchecked bitcast(usize, base)
  elem := unchecked bitcast(ptr(mut T), base_int + i * size(T))
  deref(elem) = x
}

## Overwrite the element at `i` (bounds-checked). A **mutation** of the vector's
## contents — an `in out` place borrow (the expressive mutation contract); writes
## the backing heap through `v.ptr`, not the `{ptr,len,cap}` handle.
pub set := fn(T : type, in out v : Vec(T), i : usize, x : T) {
  comptime if verify.checked { assert(i < v.len) }
  ab := deref(v.arena)
  base := alloc::get(T, ab, Handle(T)(idx = v.idx))
  base_int := unchecked bitcast(usize, base)
  elem := unchecked bitcast(ptr(mut T), base_int + i * size(T))
  deref(elem) = x
}

## The element count — a non-consuming scoped-reference read (`v.vlen()`).
pub vlen := fn(T : type, v : ptr(Vec(T))) -> usize {
  return deref(v).len
}

## Canonical v1 element count (§160). `vlen` remains as the implementation-era alias.
pub len := fn(T : type, v : ptr(Vec(T))) -> usize {
  return vlen(T, v)
}

## The backing capacity in elements (§160). A non-consuming scoped-reference read.
pub capacity := fn(T : type, v : ptr(Vec(T))) -> usize {
  return deref(v).cap
}

## Fallible element access (§160): `Some(value)` when `i < len`, otherwise `None`.
## Unlike the indexing read `at`, this operation never traps for an out-of-range index.
pub get := fn(T : type, v : ptr(Vec(T)), i : usize) -> Option(T) {
  if i >= deref(v).len { return Option(T).None }
  base_int := unchecked bitcast(usize, vec_base(T, v))
  elem := unchecked bitcast(ptr(mut T), base_int + i * size(T))
  Option(T).Some(deref(elem))
}

## True when the vector holds no elements (§160) — a non-consuming read.
pub is_empty := fn(T : type, v : ptr(Vec(T))) -> bool {
  return deref(v).len == 0
}

## Remove all elements (length → 0); the backing capacity is retained (§160).
## An `in out` place borrow (mutation), like `set`/`push`.
pub clear := fn(T : type, in out v : Vec(T)) {
  v.len = 0
}

## Drop all but the first `n` elements (a no-op when `n >= len`); the backing
## capacity is retained (§160). The shrinking counterpart of `push`.
pub truncate := fn(T : type, in out v : Vec(T), n : usize) {
  if n < v.len { v.len = n }
}

## Remove and return the last element, or `None` when the vector is empty (§160).
## No allocation — only the length shrinks (the backing is untouched). An `in out`
## place borrow.
pub pop := fn(T : type, in out v : Vec(T)) -> Option(T) {
  if v.len == 0 { return Option(T).None }
  v.len = v.len - 1
  ab := deref(v.arena)
  base := alloc::get(T, ab, Handle(T)(idx = v.idx))
  base_int := unchecked bitcast(usize, base)
  elem := unchecked bitcast(ptr(mut T), base_int + v.len * size(T))
  return Option(T).Some(deref(elem))
}

## The element at `i` as `Some(x)`, or `None` when `i` is out of range (§160) — the bounds-CHECKED
## by-value read (`try_at`, distinct from the unchecked `at` above which traps out of range). Non-
## consuming. `try_at(v, 0)` / `try_at(v, len-1)` give the first / last element without a separate name
## (base::slice::first/last already cover a Slice, reached via `as_slice(v)`).
pub try_at := fn(T : type, v : ptr(Vec(T)), i : usize) -> Option(T) {
  if i >= deref(v).len { return Option(T).None }
  ab := deref(deref(v).arena)
  base := alloc::get(T, ab, Handle(T)(idx = deref(v).idx))
  base_int := unchecked bitcast(usize, base)
  elem := unchecked bitcast(ptr(mut T), base_int + i * size(T))
  Option(T).Some(deref(elem))
}

## Remove the element at `i` in O(1) by MOVING the last element into its place, returning the removed
## value (or `None` if `i` is out of range). Order is NOT preserved (use it when order does not matter —
## the fast alternative to a shifting remove). An `in out` place borrow.
pub swap_remove := fn(T : type, in out v : Vec(T), i : usize) -> Option(T) {
  if i >= v.len { return Option(T).None }
  ab := deref(v.arena)
  base := alloc::get(T, ab, Handle(T)(idx = v.idx))
  base_int := unchecked bitcast(usize, base)
  elem_i := unchecked bitcast(ptr(mut T), base_int + i * size(T))
  removed := deref(elem_i)
  last_idx := v.len - 1
  elem_last := unchecked bitcast(ptr(mut T), base_int + last_idx * size(T))
  deref(elem_i) = deref(elem_last)
  v.len = last_idx
  Option(T).Some(removed)
}

## Ensure room for `additional` more elements without reallocating (§160): grow the
## backing through the **arena** (doubling capacity until it fits) iff `len +
## additional` exceeds the current capacity, otherwise a no-op. **Fallible** — a
## growth that exhausts the allocator surfaces `AllocError` (D91), it does not trap.
## The amortized counterpart of `push`'s on-demand grow (call it before a known
## batch of `push`es to make each one allocation-free). An `in out` place borrow.
pub reserve := fn(T : type, in out v : Vec(T), additional : usize) -> Result(usize, AllocError) {
  need := v.len + additional
  if need <= v.cap { return Result(usize, AllocError).Ok(v.cap) }
  mut new_cap : usize = v.cap
  while new_cap < need { new_cap = new_cap * 2 }
  nidx := allocate(deref(v.arena), T, new_cap * size(T), align(T))?.idx
  aa := deref(v.arena)
  oldp := alloc::get(T, aa, Handle(T)(idx = v.idx))
  newp := alloc::get(T, aa, Handle(T)(idx = nidx))
  old_int := unchecked bitcast(usize, oldp)
  new_int := unchecked bitcast(usize, newp)
  nbytes := v.len * size(T)
  mut k : usize = 0
  while k < nbytes {
    sb := unchecked bitcast(ptr(mut u8), old_int + k)
    db := unchecked bitcast(ptr(mut u8), new_int + k)
    deref(db) = deref(sb)
    k += 1
  }
  v.idx = nidx
  v.cap = new_cap
  return Result(usize, AllocError).Ok(new_cap)
}

## **Consume** the owning handle (the linear release, D86): the backing pages
## belong to the **arena**, not the vector, so this no longer `munmap`s — it only
## `forget(v)`s, discharging the consume obligation. The pages are reclaimed when
## the caller frees the arena (`std::os::free` on the owning `OsArena`), one
## shot. Kept `in` (the move/consume) so the linearity discipline is unchanged.
pub free := fn(T : type, v : Vec(T)) -> isize {
  forget(v)
  return 0
}

## `as_slice` — a borrowed `Slice(T)` view over the vector's elements (no copy,
## Stdlib §3.5). The view shares the backing storage, so it stays valid only
## while `v` is unmodified (a `push` may `mremap`-move the region) and is the
## bridge from a `Vec(T)` to the slice algorithms (`sort`, `slice_eq`, the
## higher-order queries). Writing through the view (`sort`) sorts `v` in place.
## A non-consuming scoped-reference read (`v.as_slice()`) — the view aliases the
## heap, so `v` is untouched and not consumed; the caller still owns and frees `v`.
pub as_slice := fn(T : type, v : ptr(Vec(T))) -> Slice(T) {
  p := unchecked bitcast(ptr(T), bitcast(usize, vec_base(T, v)))
  return Slice(T)(ptr = p, len = deref(v).len)
}

## `iter` — a borrowed iterable view over the elements (§160): the canonical name
## for iterating a `Vec`, returning the `Slice(T)` (which **satisfies the Iterator
## protocol**, §3.5/§2.4), so `for x in v.iter()` walks the elements. A thin alias of
## `as_slice` — the slice is the iterable; the view aliases the backing (valid while
## `v` is unmodified) and `v` is neither consumed nor mutated.
pub iter := fn(T : type, v : ptr(Vec(T))) -> Slice(T) {
  return as_slice(T, v)
}

## `map` — a new `Vec(U)` holding `f` applied to each element of slice `s`
## (Stdlib §3.5): the **allocating** map. `T` is inferred from `s`, `U` from `f`'s
## return (the function value `f` is a `fn(x : T) -> U`, Memory §6). The result
## owns its storage — the caller frees it (`free`). The eager counterpart of
## `map_in_place` (which needs `U = T` and no allocation).
pub map := fn(T : type, U : type, a : ptr(mut Arena), s : Slice(T), f : fn(x : T) -> U) -> Vec(U) {
  cap : usize = if s.len > 0 { s.len } else { 1 }
  mut out := vec_in(U, a, cap)
  mut i : usize = 0
  while i < s.len {
    v := s[i]
    y := f(v)
    push(U, out, y).expect("Vec::map: out of memory")
    i += 1
  }
  return out
}

## `split` — split `s` on the byte `sep` into a `Vec(str)` of the fields, order
## (Stdlib §3.6): `"a,b,c"` on `,` → `["a", "b", "c"]`; consecutive separators yield
## empty fields. The fields are **sub-slices of `s`** (which must outlive the
## result); the caller frees the `Vec` (`free`). The collecting counterpart of a
## manual `index_of` + `s[a..b]` loop.
pub split := fn(a : ptr(mut Arena), s : str, sep : u8) -> Vec(str) {
  bs := bytes(s)
  n : usize = s.len
  mut out := vec_in(str, a, 4)
  mut start : usize = 0
  mut i : usize = 0
  while i <= n {
    mut boundary : bool = false
    if i == n {
      boundary = true
    } else {
      c := bs[i]
      if c == sep { boundary = true }
    }
    if boundary {
      tok := s[start..i]
      push(str, out, tok).expect("split: out of memory")
      start = i + 1
    }
    i += 1
  }
  return out
}

## `filter` — a new `Vec(T)` of the elements of slice `s` satisfying `pred`
## (Stdlib §3.5): the **allocating** filter. `pred` is a `fn(x : T) -> bool`
## (Memory §6); `T` is inferred from `s`. The result owns its storage — the caller
## frees it (`free`). The growing counterpart of `filter_into` (a caller buffer).
pub filter := fn(T : type, a : ptr(mut Arena), s : Slice(T), pred : fn(x : T) -> bool) -> Vec(T) {
  cap : usize = if s.len > 0 { s.len } else { 1 }
  mut out := vec_in(T, a, cap)
  mut i : usize = 0
  while i < s.len {
    v := s[i]
    if pred(v) { push(T, out, v).expect("filter: out of memory") }
    i += 1
  }
  return out
}
