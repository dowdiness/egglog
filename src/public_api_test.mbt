///|
/// Black-box smoke test showing the public API is sufficient for a tiny use
/// case without white-box helpers.
test "public database api is usable from blackbox tests" {
  let db = Database::new()
  db.register("Num")
  let value = db.call("Num", [IntVal(7)])
  db.rebuild()
  inspect(db.lookup("Num", [IntVal(7)]) is Some(_), content="true")
  inspect(db.run_schedule(Run([])), content="Saturated")
  match value {
    IdVal(id) => {
      let (cost, expr) = db.extract(id, ast_size)
      inspect(cost, content="1")
      inspect(expr, content="(Num IntVal(7))")
    }
    _ => abort("expected IdVal")
  }
}

///|
test "Database::scan returns all rows" {
  let db = Database::new()
  db.register("Foo")
  let _ = db.call("Foo", [IntVal(1)])
  let _ = db.call("Foo", [IntVal(2)])
  let _ = db.call("Foo", [IntVal(3)])
  let rows = db.scan("Foo")
  inspect(rows.length(), content="3")
}

///|
test "Database::scan on empty table returns empty array" {
  let db = Database::new()
  db.register("Empty")
  inspect(db.scan("Empty").length(), content="0")
}

///|
test "Database::row_count tracks table size" {
  let db = Database::new()
  db.register("Bar")
  inspect(db.row_count("Bar"), content="0")
  let _ = db.call("Bar", [IntVal(10)])
  inspect(db.row_count("Bar"), content="1")
  let _ = db.call("Bar", [IntVal(20)])
  inspect(db.row_count("Bar"), content="2")
  // Functional table: same canonical key returns existing output, no new row
  let _ = db.call("Bar", [IntVal(10)])
  inspect(db.row_count("Bar"), content="2")
}

///|
test "Database::scan and row_count after rules" {
  let db = Database::new()
  db.register("Num")
  db.register("HasType")
  db.register("IntTy")
  // db.call interns each application as a new e-node, returning its e-class Id
  let n3 = db.call("Num", [IntVal(3)])
  let n7 = db.call("Num", [IntVal(7)])
  // Fact("Num", [Var("n"), Var("e")]) matches every row in the Num table,
  // binding n to the argument and e to the output e-class (the last term in a
  // Fact pattern is always the output column). Set("HasType", ...) then writes
  // HasType(e) = intty_id. Saturate runs until no new facts are derived.
  let rule : Rule = {
    name: "num-has-int-type",
    query: [Fact("Num", [Var("n"), Var("e")])],
    actions: [Set("HasType", [Var("e")], Call("IntTy", []))],
  }
  let _ = db.run_schedule(Saturate(Run([rule]), 10))
  inspect(db.row_count("HasType"), content="2")
  let rows = db.scan("HasType")
  inspect(rows.length(), content="2")
  inspect(db.lookup("HasType", [n3]) is Some(_), content="true")
  inspect(db.lookup("HasType", [n7]) is Some(_), content="true")
}

///|
test "Database::scan after union and rebuild" {
  let db = Database::new()
  db.register("F")
  let a = db.call("F", [IntVal(1)])
  let b = db.call("F", [IntVal(2)])
  // Union the two output e-classes so they share a canonical representative.
  // After rebuild, rows keep their distinct keys but output IdVals may be stale.
  match (a, b) {
    (IdVal(ia), IdVal(ib)) => db.union(ia, ib)
    _ => abort("expected IdVal")
  }
  db.rebuild()
  // Both rows survive (distinct canonical keys), but scan returns as-stored values
  let rows = db.scan("F")
  inspect(rows.length(), content="2")
  inspect(db.row_count("F"), content="2")
}
