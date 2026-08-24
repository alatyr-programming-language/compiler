## A grandchild: the same bare name resolved TWO steps up. Written so the DECOY's answer is a wrong
## VALUE rather than a trap (`0 / 2 + 7` = 7, not an underflow), because a silent wrong value is the
## outcome this fixture exists to forbid.
pub run := fn() -> u64 { return helper() / 2 + 7 }
