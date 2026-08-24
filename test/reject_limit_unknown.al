## An @limits(...) naming an UNKNOWN limit (not one of the six FND-10 limits) is a typo that would
## silently do nothing — an I3 (nothing-hidden) violation. check must reject (rc 1).
@limits(totally_bogus_limit)
main := fn() -> u64 { 42 }
