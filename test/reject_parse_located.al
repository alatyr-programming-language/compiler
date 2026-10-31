## §5: a PARSE failure must carry a source location into the diagnostic
## ("alatyr: parse: ... at line N"), not a bare rc 9. The garbage tokens below break on line 3:
@@@ not a declaration
## expect: reject "at line 3" "expected a name" "at line 3 in reject_parse_located"
