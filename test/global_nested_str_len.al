## reading `.len` of a str field of a NESTED struct field of a mutable-global struct
## (`STATE.i.name.len`). global_place resolves the nested str field's .data place at any depth; .ptr/.len
## read LABEL+off*8 / +(off+1)*8. name "worldww" (len 7) + n(35) = 42.
Inner := struct { name : str, k : u64 }
Q := struct { i : Inner, n : u64 }
mut STATE := Q(i = Inner(name = "worldww", k = 0), n = 35)
main := fn() -> u64 { return STATE.i.name.len + STATE.n }
