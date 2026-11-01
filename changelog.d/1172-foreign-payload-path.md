- **An enum payload whose type is declared in another module is sized as that type (#1172, in part).**
  `Arr(m::S)` and `Arr(m::G(u64))` kept only the path head `m` as the payload type, so the payload
  got one word and a `match` binding read neighbouring words (4 where 42 was due). The payload type
  is now the whole path. `Arr(alloc::vec::Vec(u64))` is still wrong and stays open on #1172.
