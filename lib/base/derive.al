## Structural derives over `typeinfo(T).fields` (Stdlib §2.6; Comptime §5.3 /
## §5.4) — `eq` / `lt` / `hash`, generic over any `T`. Each body iterates
## the fields with `comptime for` and projects the matching field of the value
## with `a.(f)` (≡ `a.<f.name>`), monomorphizing to **zero-cost**, fully erased
## per-field code (I2/I7). A nested aggregate field recurses through the
## per-field operator (`!=` / `<`) or the recursive `hash`. These are the v1
## default `Eq` / `Ord` / `Hash`; a type overrides by defining its own.

## Componentwise structural equality (the default `Eq`, §2.6): a **struct** is
## equal field by field (`a.(f)`); an **enum** is equal iff the same variant with
## equal payloads — matched via the comptime variant pattern `T.(v)`, one
## unrolled arm per variant, the whole payload bound and compared with `==` (a unit
## variant's empty payload compares trivially equal); a scalar leaf compares
## directly. An aggregate recurses through the per-field/-payload `==`.
eq := fn(T : type, a : T, b : T) -> bool {
  comptime match typeinfo(T) {
    Struct(_) => {
      ## RECURSE EXPLICITLY (`eq(f.type, …)`, mirroring `hash(f.type, …)`) rather than the bare
      ## `a.(f) != b.(f)` operator: a NESTED aggregate field must compare ALL its words. The bare
      ## operator over a multi-word aggregate field compares WORD 0 ONLY (a silent miscompile) — it is
      ## not wired to the structural derive — so a per-field `!=`/`==` on a struct/enum/array field
      ## would drop every later word. The explicit call re-enters `eq` for that field's type, and the
      ## mono worklist's self-recursive-derive collection instantiates the nested `eq(f.type)` (exactly
      ## as it already does for `hash`). A scalar leaf bottoms out at the `_` arm's `a == b`.
      comptime for f in typeinfo(T).fields {
        if eq(f.type, a.(f), b.(f)) == false { return false }
      }
      return true
    }
    Enum(_) => {
      ## Match both operands DIRECTLY (no `aa := a` copy): a by-ref enum param is materialized into
      ## its own nested-match scratch level, so the inner `match b` never clobbers `a`'s payload.
      ## The payload compare uses the bare `==` operator, which routes a MULTI-WORD aggregate payload
      ## through this same structural `eq` (the bare-comparison -> `base::derive::eq` routing) so every
      ## word is compared, and a scalar payload compares directly. (The former `eq(pa, pb)` IMPLICIT
      ## type-arg recursion mis-inferred `T` as the payload VARIABLE NAME `pa` -> a bogus
      ## `base__derive__eq__pa` with one arg -> wrong result; the bare operator resolves the payload
      ## type from its slot, not a name.)
      return match a {
        comptime for v in typeinfo(T).variants {
          T.(v)(pa) => match b {
            T.(v)(pb) => pa == pb
            _ => false
          }
        }
      }
    }
    Array(_) => {
      comptime for i in 0 .. typeinfo(T).n {
        if eq(a[i], b[i]) == false { return false }
      }
      return true
    }
    _ => { return a == b }
  }
}

## Lexicographic order by declaration order (the default `Ord`, §2.6): for a
## **struct**, the first field at which the two differ decides; for an **enum**,
## the variant **declaration order** decides, then the payload. A scalar leaf
## orders directly; equal ⇒ not less-than.
lt := fn(T : type, a : T, b : T) -> bool {
  comptime match typeinfo(T) {
    Struct(_) => {
      ## RECURSE EXPLICITLY (`lt(f.type, …)`) rather than the bare `a.(f) < b.(f)`: a nested aggregate
      ## field must be ordered over ALL its words, not word 0 only (the bare operator over a multi-word
      ## aggregate is a silent word-0 compare). The mono worklist instantiates the nested `lt(f.type)`.
      comptime for f in typeinfo(T).fields {
        if lt(f.type, a.(f), b.(f)) { return true }
        if lt(f.type, b.(f), a.(f)) { return false }
      }
      return false
    }
    Enum(_) => {
      ## Walk variants in declaration order. By the time we reach `v`, neither
      ## `a` nor `b` is an earlier variant (else we'd have returned). So at `v`:
      ## both `v` ⇒ compare payloads; only `a` is `v` ⇒ `b` is later ⇒ a < b;
      ## only `b` is `v` ⇒ `a` is later ⇒ a > b. No variant index needed.
      ## Match both operands DIRECTLY (no `aa := a` copy) — each by-ref param materializes into its own
      ## nested-match scratch level, so the inner `match b` never clobbers `a`'s payload.
      comptime for v in typeinfo(T).variants {
        match a {
          T.(v)(pa) => match b {
            T.(v)(pb) => { return lt(pa, pb) }
            _ => { return true }
          }
          _ => match b {
            T.(v)(pb) => { return false }
            _ => { }
          }
        }
      }
      return false
    }
    Array(_) => {
      comptime for i in 0 .. typeinfo(T).n {
        if lt(a[i], b[i]) { return true }
        if lt(b[i], a[i]) { return false }
      }
      return false
    }
    _ => { return a < b }
  }
}

## Structural hash **consistent with `eq`** (the default `Hash`, §2.6): a **struct**
## folds its field hashes (an FNV-style mix); an **enum** hashes the matched
## variant's payload (comptime variant match); an **array** folds element
## hashes; a scalar leaf hashes its own value. Recurses, so padding never enters the
## hash. Equal values (same variant / elements) hash equally — consistent with `eq`.
hash := fn(T : type, v : T) -> u64 {
  comptime if (match typeinfo(T) { Struct(_) => true; _ => false }) {
    mut h : u64 = 1469598103934665603
    comptime for f in typeinfo(T).fields {
      h = unchecked (h * 1099511628211 + hash(f.type, v.(f)))
    }
    return h
  } else {
    comptime if (match typeinfo(T) { Enum(_) => true; _ => false }) {
      vv := v
      match vv {
        comptime for var in typeinfo(T).variants {
          T.(var)(p) => { return hash(p) }
        }
      }
      return 0
    } else {
      comptime if (match typeinfo(T) { Array(_) => true; _ => false }) {
        mut h : u64 = 1469598103934665603
        comptime for i in 0 .. typeinfo(T).n {
          h = unchecked (h * 1099511628211 + hash(v[i]))
        }
        return h
      } else {
        comptime if (match typeinfo(T) { Str(_) => true; _ => false }) {
          ## `str` is the OPAQUE base view (§4.1 `TypeInfo.Str`): no fields to fold, and its two
          ## `{ptr, len}` words are an ADDRESS, not the value. The derived `eq` for a `str` bottoms
          ## out at its own `_` arm's `a == b`, which the lower compares by CONTENT — so §2.6's
          ## "`Hash` consistent with `Eq`" REQUIRES the content hash here: two equal-content views
          ## in distinct allocations must hash equally. Without this arm the fallthrough `u64(v)`
          ## rejected the two-word view as a non-scalar conversion operand, so `HashMap(str, V)`
          ## could not be instantiated at all — a valid program refused. This arm, not the concrete
          ## `hash(s : str)` overload below, is the one that a generic container reaches: the
          ## generic map's own `rehash` spells `hash(K, k)` EXPLICITLY, which can only ever select
          ## the generic, so a fix that only re-routed the implicit `hash(key)` sites would make a
          ## grown map hash differently from the one it grew out of.
          return str_hash(v)
        } else {
          return u64(v)
        }
      }
    }
  }
}

## FNV-1a over a `str`'s bytes — the single content-hash DECISION, so the concrete `hash(s : str)`
## override and the structural derive's `Str` arm can never drift apart (they must agree: a program
## may reach either, and a `HashMap(str, V)` that hashed a key one way on insert and the other way
## after a grow would lose it).
str_hash := fn(s : str) -> u64 {
  mut h : u64 = 1469598103934665603
  for c in bytes(s) {
    h = unchecked ((h ^ u64(c)) * 1099511628211)
  }
  h
}

## Content hash for `str` (FNV-1a over the bytes) — a concrete overload of `hash`,
## so a `str`-keyed container hashes by content, not by the {ptr,len} struct bits.
hash := fn(s : str) -> u64 {
  str_hash(s)
}
