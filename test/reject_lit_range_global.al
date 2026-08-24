## e2e — the MODULE-SCOPE mirror. A module binding carries no dedicated type field, so its `: T` is
## recovered from source exactly as the local form's is; without this `G : u8 = 300` stayed accepted
## even after the local form rejected. Located at the binding (line 4).
G : u8 = 300

main := fn() -> i64 {
  return i64(G)
}
