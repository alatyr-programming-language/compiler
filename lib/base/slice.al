## Slice `[T]` — a pointer + length pair over a contiguous run of `T`
## (Stdlib §3.5). The layout is this **library pair**, not a primitive: an
## ordinary `struct` of a pointer and a length, so it composes from the
## existing pointer (`ptr`) and aggregate machinery.
##
## Construct one over an array place via an alias of the instantiation, e.g.
## `SU := Slice(u64)` then `SU(ptr = ptr(xs[0]), len = 3)`; read its count
## with the `len` field. The curated operations of §3.5 — bounds-checked
## indexing `self[i]`, sub-slicing `self[a..b]`, `first` / `last`, `iter`, and
## in-place `sort` on `[mut T]` — are the next increments (they need
## pointer-based, runtime-bounds-checked element addressing in the backends).
Slice := fn(T : type) -> type { return struct { ptr : ptr(T), len : usize } }

## `len` — the element count (Stdlib §3.5). Generic over `Slice(T)`, with `T`
## inferred from the slice argument at the call (the underlying `len` field is
## also directly readable).
pub len := fn(T : type, s : Slice(T)) -> usize { return s.len }

## `first` / `last` — the first / last element, or `None` for an empty slice
## (Stdlib §3.5). `T` is inferred from the slice argument at the call.
pub first := fn(T : type, s : Slice(T)) -> Option(T) {
  if 0 < s.len {
    v := s[0]
    some := Option(T).Some(v)
    return some
  }
  none := Option(T).None
  none
}

pub last := fn(T : type, s : Slice(T)) -> Option(T) {
  if 0 < s.len {
    v := s[s.len - 1]
    some := Option(T).Some(v)
    return some
  }
  none := Option(T).None
  none
}

## Higher-order slice queries (Stdlib §3.5): each takes a **predicate** function
## value `pred` (Memory §6) — a `fn(x : T) -> bool` applied to each element. `T`
## is inferred from the slice argument; the predicate is called indirectly.

## `count_if` — the number of elements satisfying `pred`.
pub count_if := fn(T : type, s : Slice(T), pred : fn(x : T) -> bool) -> usize {
  mut n : usize = 0
  mut i : usize = 0
  while i < s.len {
    v := s[i]
    if pred(v) { n = n + 1 }
    i += 1
  }
  n
}

## `any` — whether **at least one** element satisfies `pred` (short-circuits).
pub any := fn(T : type, s : Slice(T), pred : fn(x : T) -> bool) -> bool {
  mut i : usize = 0
  while i < s.len {
    v := s[i]
    if pred(v) { return true }
    i += 1
  }
  false
}

## `all` — whether **every** element satisfies `pred` (short-circuits; vacuously
## true for an empty slice).
pub all := fn(T : type, s : Slice(T), pred : fn(x : T) -> bool) -> bool {
  mut i : usize = 0
  while i < s.len {
    v := s[i]
    if not pred(v) { return false }
    i += 1
  }
  true
}

## `reduce` — left-fold the slice into an accumulator (Stdlib §3.5): starting from
## `init`, replace the accumulator with `f(acc, element)` for each element, in
## order, returning the final accumulator. `f` is a `fn(acc : A, x : T) -> A`
## function value (Memory §6); the accumulator type `A` is inferred from `init`. No
## allocation — sum / product / max / a running parse state all ride this.
pub reduce := fn(T : type, A : type, s : Slice(T), init : A, f : fn(acc : A, x : T) -> A) -> A {
  mut acc : A = init
  mut i : usize = 0
  while i < s.len {
    v := s[i]
    acc = f(acc, v)
    i += 1
  }
  acc
}

## `contains` — whether `s` holds an element equal to `x` (membership by `==`, §2.6;
## the structural `Eq` derive, so it works for any element type incl. `str`). The
## value counterpart of `find` for the common "is it in this set" check.
pub contains := fn(T : type, s : Slice(T), x : T) -> bool {
  for el in s {
    if el == x { return true }
  }
  false
}

## `find` — the index of the first element satisfying `pred`, or `None`.
pub find := fn(T : type, s : Slice(T), pred : fn(x : T) -> bool) -> Option(usize) {
  mut i : usize = 0
  while i < s.len {
    v := s[i]
    if pred(v) { return Option(usize).Some(i) }
    i += 1
  }
  Option(usize).None
}

## `sift_down` — HEAP property restoration (introsort/heapsort, O(n log n) worst-case, appendix §160
## mandates "introsort-class algorithm; a quadratic worst case is non-conforming"). Restores the heap
## property at `i` in a `[mut T]` slice of length `n` (the active heap size). Uses `Ord` (`<`).
## Iterative (no recursion), in-place, no allocation.
sift_down := fn(T : type, s : Slice(T), n : usize, i : usize) {
  mut idx := i
  loop {
    mut largest := idx
    l := 2 * idx + 1
    r := 2 * idx + 2
    if l < n {
      lv := s[l]
      bv := s[largest]
      if bv < lv { largest = l }
    }
    if r < n {
      rv := s[r]
      bv := s[largest]
      if bv < rv { largest = r }
    }
    if largest == idx { break }
    vi := s[idx]
    vj := s[largest]
    s[idx] = vj
    s[largest] = vi
    idx = largest
  }
}

## `sort` — in-place ascending sort by `Ord` (`<`, §2.6), no allocation
## (Stdlib §3.5). **Heapsort** — O(n log n) worst-case, in-place, no allocation;
## **not guaranteed stable** (a stable sort and key/comparator variants are additive,
## D16). Sorts the slice's backing storage, so the slice must be over a mutable place.
## Conforms to appendix §160 (introsort-class algorithm; a quadratic worst case is
## non-conforming).
pub sort := fn(T : type, s : Slice(T)) {
  n := s.len
  if n <= 1 { return }
  ## Build max-heap
  mut i : usize = n / 2
  while i > 0 {
    i = i - 1
    sift_down(T, s, n, i)
  }
  ## Extract
  i = n - 1
  while i > 0 {
    vi := s[0]
    vm := s[i]
    s[0] = vm
    s[i] = vi
    i = i - 1
    sift_down(T, s, i + 1, 0)
  }
}

## `sift_down_by` — comparator variant of `sift_down`, for `sort_by` below.
sift_down_by := fn(T : type, s : Slice(T), n : usize, i : usize, less : fn(a : T, b : T) -> bool) {
  mut idx := i
  loop {
    mut largest := idx
    l := 2 * idx + 1
    r := 2 * idx + 2
    if l < n {
      lv := s[l]
      bv := s[largest]
      if less(bv, lv) { largest = l }
    }
    if r < n {
      rv := s[r]
      bv := s[largest]
      if less(bv, rv) { largest = r }
    }
    if largest == idx { break }
    vi := s[idx]
    vj := s[largest]
    s[idx] = vj
    s[largest] = vi
    idx = largest
  }
}

## `sort_by` — in-place sort by a **comparator** function value (Memory §6): `less`
## is a `fn(a : T, b : T) -> bool` returning whether `a` should come **before**
## `b` (Stdlib §3.5). Heapsort, O(n log n) worst-case, no allocation.
## Not guaranteed stable. The comparator is called indirectly per compare.
pub sort_by := fn(T : type, s : Slice(T), less : fn(a : T, b : T) -> bool) {
  n := s.len
  if n <= 1 { return }
  mut i : usize = n / 2
  while i > 0 {
    i = i - 1
    sift_down_by(T, s, n, i, less)
  }
  i = n - 1
  while i > 0 {
    vi := s[0]
    vm := s[i]
    s[0] = vm
    s[i] = vi
    i = i - 1
    sift_down_by(T, s, i + 1, 0, less)
  }
}

## `map_in_place` — replace each element with `f` of it (Stdlib §3.5): a
## transforming map with **no allocation**, over a mutable slice. `f` is a
## `fn(x : T) -> T` (same element type), called indirectly per element.
pub map_in_place := fn(T : type, s : Slice(T), f : fn(x : T) -> T) {
  mut i : usize = 0
  while i < s.len {
    v := s[i]
    s[i] = f(v)
    i += 1
  }
}

## `filter_into` — copy the elements of `src` satisfying `pred` into `dst`, in
## order, returning the count written (Stdlib §3.5). No allocation: `dst` is a
## caller-provided buffer; any matches beyond `dst.len` are dropped (the returned
## count reflects only what fit). `pred` is a `fn(x : T) -> bool`.
pub filter_into := fn(T : type, src : Slice(T), pred : fn(x : T) -> bool, dst : Slice(T)) -> usize {
  mut n : usize = 0
  mut i : usize = 0
  while i < src.len {
    v := src[i]
    if pred(v) {
      if n < dst.len {
        dst[n] = v
        n += 1
      }
    }
    i += 1
  }
  n
}

## `bytes_eq` — content equality of two byte slices: equal length and equal
## bytes, short-circuiting (the `[u8]` counterpart of `str_eq`, §3.6). The reuse
## primitive for byte-keyed lookups (a hash map's key compare).
bytes_eq := fn(a : Slice(u8), b : Slice(u8)) -> bool {
  if a.len != b.len {
    return false
  }
  mut i : usize = 0
  while i < a.len {
    xa := a[i]
    xb := b[i]
    if xa != xb {
      return false
    }
    i += 1
  }
  true
}

## `slice_eq` — content equality of two slices of **any** element type `T`
## (Stdlib §3.5): equal length, then element-by-element over the structural
## `==` (the derived `Eq`, §2.6) — so a `Slice(Point)` / `Slice(u64)` compares
## by value, short-circuiting. The general counterpart of `bytes_eq` (`T = u8`,
## which stays the specialized byte path). Each element is read into a local
## before the compare (the aggregate slice-element read path).
slice_eq := fn(T : type, a : Slice(T), b : Slice(T)) -> bool {
  if a.len != b.len {
    return false
  }
  mut i : usize = 0
  while i < a.len {
    xa := a[i]
    xb := b[i]
    if xa != xb {
      return false
    }
    i += 1
  }
  true
}

## `slice_cmp` — lexicographic order of two slices of **any** element type `T`
## (Stdlib §3.5): compare element-by-element over the derived `Ord` (`<`, §2.6);
## the first differing element decides, else the shorter slice is less. Returns
## a three-way `isize` (`-1` / `0` / `+1`) — the general counterpart of a
## `bytes_cmp`, and the engine the `<`/`<=`/`>`/`>=` operators over slices
## desugar onto (`slice_cmp(a, b) ⊕ 0`). Each element is read into a local first.
slice_cmp := fn(T : type, a : Slice(T), b : Slice(T)) -> isize {
  mut n : usize = a.len
  if b.len < n {
    n = b.len
  }
  mut i : usize = 0
  while i < n {
    xa := a[i]
    xb := b[i]
    if xa < xb {
      return 0 - 1
    }
    if xb < xa {
      return 1
    }
    i += 1
  }
  if a.len < b.len {
    return 0 - 1
  }
  if b.len < a.len {
    return 1
  }
  0
}

## `hash_bytes` — a polynomial hash of a byte slice into a `u64` (Stdlib §2.6 /
## Comptime §5: the `Hash` derive's byte-level core). `h := h*prime + byte`,
## wrapping (so `unchecked`). The reuse primitive for byte-keyed hash maps; the
## structural `Hash` over arbitrary fields rides `typeinfo` (a later step).
hash_bytes := fn(s : Slice(u8)) -> u64 {
  mut h : u64 = 1469598103934665603
  mut i : usize = 0
  while i < s.len {
    b := s[i]
    h = unchecked (h * 1099511628211 + u64(b))
    i += 1
  }
  h
}
