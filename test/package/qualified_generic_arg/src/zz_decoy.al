## The same tail name in another module must not capture `codec::Error`'s identity or layout.
pub Error := enum {
  Wrong(u64, u64, u64),
}
