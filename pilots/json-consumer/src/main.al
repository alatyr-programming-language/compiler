## Each check names what it expects. `run` returns 0 when all hold, else the first failing
## check's number.

## A parsed document rendered back must be `want`.
round_trip := fn(a : ptr(mut Arena), text : str, want : str) -> bool {
  match json::text::parse(a, text) {
    Ok(v) => {
      mut out := alloc::string::new(a)
      match json::text::render(out, v) {
        Ok(_) => {
          alloc::string::as_str(ptr(out)) == want
        }
        Err(_) => {
          false
        }
      }
    }
    Err(_) => {
      false
    }
  }
}

## `text` must fail to parse with `kind` at 1-based `line`:`column`.
fails_at := fn(a : ptr(mut Arena), text : str, kind : json::text::ErrorKind, line : usize, column : usize) -> bool {
  match json::text::parse(a, text) {
    Ok(_) => {
      false
    }
    Err(e) => {
      e.kind == kind and e.line == line and e.column == column
    }
  }
}

run := fn(a : ptr(mut Arena)) -> u64 {
  if round_trip(a, "42", "42") == false { return 1 }
  if round_trip(a, " -7 ", "-7") == false { return 2 }
  if round_trip(a, "true", "true") == false { return 3 }
  if round_trip(a, "null", "null") == false { return 4 }
  if round_trip(a, "\"a\\nb\\u0041\"", "\"a\\nbA\"") == false { return 5 }
  if round_trip(a, "[1, 2, 3]", "[1,2,3]") == false { return 6 }
  if round_trip(a, "{\"k\": [true, null], \"n\": -1}", "{\"k\":[true,null],\"n\":-1}") == false { return 7 }
  if round_trip(a, "2.5", "2.5") == false { return 8 }
  if fails_at(a, "[1,]", json::text::ErrorKind.UnexpectedByte, 1, 4) == false { return 9 }
  if fails_at(a, "{\n \"a\" 1}", json::text::ErrorKind.UnexpectedByte, 2, 6) == false { return 10 }
  if fails_at(a, "01", json::text::ErrorKind.BadNumber, 1, 2) == false { return 11 }
  if fails_at(a, "\"x", json::text::ErrorKind.UnexpectedEnd, 1, 3) == false { return 12 }
  if fails_at(a, "1 2", json::text::ErrorKind.TrailingData, 1, 3) == false { return 13 }
  0
}

main := fn() -> u64 {
  match std::os::arena(1048576) {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      rc := run(ptr(mut ar))
      std::os::free(osa)
      rc
    }
    Err(_) => {
      100
    }
  }
}
