- **A type named by a path of three or more segments is sized as that type (#1172).**
  `alloc::vec::Vec(u64)` as an enum payload, as a payload struct's field or as a struct field passed
  by value got one word, because the layout cut the name at its first `::` and looked up `vec::Vec`,
  which names nothing. A `match` then read the length as 1, or `ys.len()` as 83, or crashed. The
  layout now looks such a type up by its last segment before the type arguments, so
  `Arr(alloc::vec::Vec(u64))` reads back its three elements. Name resolution in the checker is
  unchanged: only the size and field lookup take the narrower name.
