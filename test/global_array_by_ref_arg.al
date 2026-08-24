## e2e — a mutable ARRAY global passed BY REFERENCE to a function. Like a struct global, the ascending
## .data must be materialized into a down-growing agg-temp first; and the agg-temp is sized to the
## widest mutable-global aggregate (a 3-word array otherwise overran a struct-sized block and the
## `call` return address clobbered its last element). sum3(TABLE) = 40 + 1 + 1 = 42.
mut TABLE := [40, 1, 1]
sum3 := fn(a : [u64; 3]) -> u64 { a[0] + a[1] + a[2] }
main := fn() -> u64 { sum3(TABLE) }
