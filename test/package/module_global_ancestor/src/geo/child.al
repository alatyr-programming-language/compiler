## A direct child: every reference is a BARE name resolved one step up the ancestor chain.
pub run := fn() -> u64 {
  COUNT = 6
  COUNT += 1
  TAB[2] = 12
  return COUNT + TAB[2] + u64(MSG.len) + LIMIT + VALUES[1]
}
