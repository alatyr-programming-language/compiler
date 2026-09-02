## Allocator protocol + the region mechanism (Stdlib appendix §5).
##
## This is the **base-tier** allocator surface (available freestanding) — the
## mechanism *menu* (Memory §5.2), not the `alloc` *tier* (`Vec`/`String`/…,
## which is forbidden under `no_alloc`). v1 specifies exactly one mechanism, the
## **region/arena** (§5.2.1): two ordinary library types plus prelude functions;
## the language adds only the meaning of `@alloc` (Memory §2.4 / §5.4).

## `Mechanism` — how an allocator declares the lifetime mechanism it supplies
## (Stdlib §5.1). `@alloc(a)` reads it at comptime (via the `mechanism` accessor)
## to pick the reference representation. Further mechanisms are additive
##; `region` is the only one with a v1 surface.
Mechanism := enum { region, generational, manual }

## `AllocError` — the closed v1 error set of the allocator protocol (Stdlib §5.1).
## `OutOfMemory`: no capacity for the request; `BadAlignment`: the requested
## alignment is invalid/unsupported; `SizeTooLarge`: the size (after alignment
## rounding) exceeds the limit or overflows `usize`.
AllocError := enum { OutOfMemory, BadAlignment, SizeTooLarge }

## `Handle(T)` — a region handle: an index into its arena (Stdlib §5.2.1).
## Just a number, so it has no lifetime problem; copyable, not owning. Distinct
## per `T` because a type-function result is nominal by (function, args) (Type
## System §4.1) — even though the layout (`usize`) does not mention `T`. It
## carries **no** region name and **no** lifetime variable (holds). A handle
## is **never** dereferenced (§5.6 rule 4); the value is reached via `get`.
Handle := fn(T : type) -> type { return struct { idx : usize } }

## `Arena` — the region/arena allocator: a bump allocator over a caller-supplied
## buffer (Stdlib §5.2.1). `base` points at the buffer, `cap` is its size in
## bytes, `off` is the bump cursor. Allocation bumps `off`; `close` reclaims in
## bulk. Over a caller buffer (`arena_over`) it holds no releasable resource, so
## it carries no finalize obligation (Memory §5.9 — "own forever"); an OS-backed
## arena (additive) makes `close` a real release and is therefore linear.
Arena := struct { base : ptr(mut bits8), cap : usize, off : usize }

## `mechanism` — the comptime accessor (Stdlib §5.1): an `Arena` supplies the
## `region` mechanism. `@alloc(a)` evaluates this at comptime to choose the
## reference representation.
mechanism := fn(self : Arena) -> Mechanism { return Mechanism.region }

## `arena_over` — construct an arena over a caller-supplied buffer (`buf`, `cap`
## bytes); freestanding, no OS (Stdlib §5.2.1). The cursor starts at 0.
arena_over := fn(buf : ptr(mut bits8), cap : usize) -> Arena {
  a := Arena(base = buf, cap = cap, off = 0)
  return a
}

## `close` — bulk reclamation (Stdlib §5.2.1): reset the cursor so the buffer is
## reusable. For a caller-supplied buffer this releases nothing the arena owns
## (the buffer is the caller's); an OS-backed arena's `close` is a real release.
close := fn(in out self : Arena) { self.off = 0 }

## `allocate` — the allocator protocol's bump allocation for the region mechanism
## (Stdlib §5.1, typed by the mechanism → `Handle(T)`): VALIDATE the requested
## alignment, round the cursor up to `align`, return `OutOfMemory` if the request
## does not fit the remaining capacity, else bump the cursor and return the byte
## offset as a `Handle(T)`. `size`/`align` are the caller's `size(T)` /
## `align(T)`. The handle is an index into the arena — never a pointer; the value
## is reached with `get`.
##
## The alignment check comes FIRST and is part of the protocol's error set, not a
## precondition the caller must have satisfied: Stdlib §5.1 defines `BadAlignment`
## as "the requested alignment is invalid or unsupported (e.g. not a power of
## two)", so an invalid `align` is a `Result` the caller can recover from. Zero is
## rejected before the `%` below (a modulo by zero is a trap, not a `Result`), and
## a non-power-of-two is rejected because rounding to it yields an address that is
## not a multiple of the requested alignment at all (`off = 0`, `align = 3` used
## to hand back `Ok(idx = 0)`). `align & (align - 1)` is the power-of-two test;
## `align != 0` is already established, so the `- 1` cannot underflow. A rejection
## returns before any store, so the bump cursor is untouched and the arena stays
## usable.
allocate := fn(in out self : Arena, T : type, size : usize, align : usize) -> Result(Handle(T), AllocError) {
  if align == 0 {
    zero_align := Result(Handle(T), AllocError).Err(AllocError.BadAlignment)
    return zero_align
  }
  if (align & (align - 1)) != 0 {
    bad_align := Result(Handle(T), AllocError).Err(AllocError.BadAlignment)
    return bad_align
  }
  rem := self.off % align
  mut aligned : usize = self.off
  if rem != 0 {
    aligned = self.off + (align - rem)
  }
  if aligned + size > self.cap {
    oom := Result(Handle(T), AllocError).Err(AllocError.OutOfMemory)
    return oom
  }
  self.off = aligned + size
  h := Handle(T)(idx = aligned)
  ok := Result(Handle(T), AllocError).Ok(h)
  return ok
}

## `free` — a **no-op** for the region mechanism (Stdlib §5.2.1): storage is
## reclaimed in bulk by `close`, so an individual free reclaims nothing. Present
## to satisfy the allocator-protocol shape (§5.1).
free := fn(in out self : Arena, T : type, h : Handle(T), size : usize, align : usize) {
}

## `get` — exchange a handle + its arena for a **scoped pointer** to the value
## (Stdlib §5.2.1): bounds-check the handle's index against the arena's
## high-water mark (out-of-range → trap, I11), then form `base + idx` as a
## `ptr(mut T)`. The pointer arithmetic is a raw, capability-requiring
## reinterpret, hence the `unchecked` grant (Memory §4.5).
##
## The discipline is enforced by the checkers: the second-class-reference
## **escape checker** (Memory §5.3.1) recognizes `get(T, arena, handle)` (and its
## an **ordinary function with a `scoped` return**, not a privileged intrinsic:
## the `scoped` result qualifier makes the escape checker treat a `get` result as a
## second-class scoped reference — it flows only downward (deref/read/pass-on) and may
## **not** be returned or stored, so the scoped pointer cannot outlive the arena (§5.4).
## A user could write the same signature. The **linearity checker** enforces that
## an owning arena is consumed exactly once. The body below deliberately escapes its own
## return via `unchecked` (§5.6 rule 5), forming the raw `ptr` the bounds-checked
## arithmetic computes.
get := fn(T : type, a : Arena, h : Handle(T)) -> scoped ptr(mut T) {
  comptime if verify.checked { assert(h.idx < a.off) }
  base_int := unchecked bitcast(usize, a.base)
  elem_int := base_int + h.idx
  p := unchecked bitcast(ptr(mut T), elem_int)
  return p
}

## `alloc_into` — the trapping allocation that backs the `@alloc(a) x := init`
## storage attribute (Memory §2.4): allocate a `T` in `a`, **trap** on
## `OutOfMemory` (a defined failure, I11 — the convenient attribute form has no
## `Result` to carry it; the recoverable path is `a.allocate(…)?` directly),
## write `init` into the storage, and return the binding's `Handle(T)`. `T` is
## inferred from `init`.
alloc_into := fn(T : type, in out a : Arena, init : T) -> Handle(T) {
  ## Extract the allocated index as a SCALAR (`.expect(…).idx` — the post-mono Result-payload
  ## field-read seam), then rebuild the handle as an explicit `Handle(T)` STRUCT LITERAL so the
  ## `get` call below receives it BY REFERENCE (an aggregate local, ek 2). Binding it directly from
  ## `.expect(…)` records a scalar slot, so `get` — whose `h : Handle(T)` param is read through a
  ## pointer — would deref the raw index value and trap; the explicit literal is the by-ref bridge.
  idx := allocate(a, T, size(T), align(T)).expect("allocation failed").idx
  h := Handle(T)(idx = idx)
  p := get(T, a, h)
  deref(p) = init
  return h
}

## --- `Buf(T)`: a growable array over the allocator protocol -------------------
## The canonical **"container over a pluggable allocator"** (Memory §5;
##). A dynamic array whose backing storage comes from an `Arena` (the
## region mechanism) — NOT a direct `mmap`, the way `std::vec`'s `Vec(T)` does it.
## It holds the arena **index** of its backing (the `Handle(T)`'s value, kept as a
## flat `usize` so the `Buf` is three scalars) plus `len`/`cap`. It is **non-owning**:
## the arena owns the pages and reclaims them in one shot (`close` / the owning
## `OsArena`'s `free`), so a `Buf` has no `free` of its own — the arena discipline
## a compiler pass wants. Allocation flows through the allocator: `buf_make` and a
## growing `buf_push` take it `in out`; element reads resolve the index via `get`.
## A grow allocates a fresh, larger backing and copies — the old backing is left to
## the arena's bulk reclaim (the standard arena trade-off; no per-object free).
Buf := fn(T : type) -> type { return struct { idx : usize, len : usize, cap : usize } }

## Allocate a `Buf(T)` with room for `cap` elements (≥1 so a grow can double) from
## arena `a`; an allocator failure propagates as `AllocError` via `?`.
buf_new := fn(T : type, in out a : Arena, cap : usize) -> Result(Buf(T), AllocError) {
  h := allocate(a, T, cap * size(T), align(T))?
  return Result(Buf(T), AllocError).Ok(Buf(T)(idx = h.idx, len = 0, cap = cap))
}

## `buf_make` — the trapping constructor (the convenient form): allocate `cap`
## elements and **trap** on `OutOfMemory` (a defined failure, I11).
buf_make := fn(T : type, in out a : Arena, cap : usize) -> Buf(T) {
  h := allocate(a, T, cap * size(T), align(T)).expect("buf_make: allocator out of memory")
  return Buf(T)(idx = h.idx, len = 0, cap = cap)
}

## Element pointer for index `i` of the backing at arena index `at` (resolve the
## arena base via `get`, then offset). Internal; the raw pointer arithmetic is a
## capability-requiring reinterpret, hence `unchecked`.
buf_ptr := fn(T : type, a : Arena, at : usize, i : usize) -> ptr(mut T) {
  h := Handle(T)(idx = at)
  base := get(T, a, h)
  base_int := unchecked bitcast(usize, base)
  off := base_int + i * size(T)
  return unchecked bitcast(ptr(mut T), off)
}

## Append `x`, doubling the backing through the allocator when full (allocate a new
## region, copy the live elements, drop the old to bulk reclaim).
buf_push := fn(T : type, in out b : Buf(T), in out a : Arena, x : T) {
  if b.len >= b.cap {
    new_cap := b.cap * 2
    nidx := allocate(a, T, new_cap * size(T), align(T)).expect("Buf grow: allocator out of memory").idx
    old_at := b.idx
    ## Copy the live elements **byte by byte** (a whole-aggregate store through a
    ## pointer is not lowered, but a `u8` is): works for any element type `T`.
    old_int := unchecked bitcast(usize, buf_ptr(T, a, old_at, 0))
    new_int := unchecked bitcast(usize, buf_ptr(T, a, nidx, 0))
    nbytes := b.len * size(T)
    mut k : usize = 0
    while k < nbytes {
      sb := unchecked bitcast(ptr(mut u8), old_int + k)
      db := unchecked bitcast(ptr(mut u8), new_int + k)
      deref(db) = deref(sb)
      k += 1
    }
    b.idx = nidx
    b.cap = new_cap
  }
  slot := buf_ptr(T, a, b.idx, b.len)
  deref(slot) = x
  b.len = b.len + 1
}

## The element at `i` (bounds-checked, traps when `i >= len`): resolve the backing
## via `get`, then index. Needs the arena to turn the index into a pointer; a
## non-consuming scoped-reference read of the `Buf` (`b.buf_at(a, i)`).
buf_at := fn(T : type, b : ptr(Buf(T)), a : Arena, i : usize) -> T {
  comptime if verify.checked { assert(i < deref(b).len) }
  at := deref(b).idx
  elem := buf_ptr(T, a, at, i)
  return deref(elem)
}

## Overwrite the element at `i` (bounds-checked) through the allocator-resolved
## backing — an `in out` place borrow of the `Buf` contents.
buf_set := fn(T : type, in out b : Buf(T), a : Arena, i : usize, x : T) {
  comptime if verify.checked { assert(i < b.len) }
  elem := buf_ptr(T, a, b.idx, i)
  deref(elem) = x
}

## The element count — a non-consuming scoped-reference read (`b.buf_len()`).
buf_len := fn(T : type, b : ptr(Buf(T))) -> usize {
  return deref(b).len
}

## `buf_as_slice` — a borrowed `Slice(T)` view over the elements (no copy, Stdlib
## §3.5). Resolves the backing through `get` and shares it, so the view is valid
## while the `Buf` is unmodified (a `buf_push` may move the backing on grow) and the
## arena is alive. This is the **bridge** from an allocator-borne `Buf(T)` to every
## `Slice` algorithm (`reduce`/`count_if`/`any`/`all`/`first`/`last`, base §3.5) — the
## container reuses the whole slice ecosystem rather than reimplementing it.
buf_as_slice := fn(T : type, b : ptr(Buf(T)), a : Arena) -> Slice(T) {
  at := deref(b).idx
  base := get(T, a, Handle(T)(idx = at))
  p := unchecked bitcast(ptr(T), bitcast(usize, base))
  return Slice(T)(ptr = p, len = deref(b).len)
}
