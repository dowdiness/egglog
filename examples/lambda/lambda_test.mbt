///|
fn run(db : @egglog.Database, rules : Array[@egglog.Rule]) -> Unit {
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(rules), 20))

}

///|
/// Extract the Id out of an @egglog.IdVal. Aborts on other variants.
/// Used throughout tests because db.lookup/db.call return @egglog.Value.
fn unwrap_id(v : @egglog.Value) -> @egglog.Id {
  match v {
    @egglog.IdVal(id) => id
    _ => abort("expected IdVal")
  }
}

///|
test "num synthesizes IntTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let num_e = db.call("Num", [@egglog.IntVal(42)])
  let _ = db.set("Typing", [env, num_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, num_e])
  inspect(result is Some(_), content="true")
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "boollit synthesizes BoolTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let b_e = db.call("BoolLit", [@egglog.IntVal(1)])
  let _ = db.set("Typing", [env, b_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let bool_ty = db.call("BoolTy", [])
  let result = db.lookup("HasType", [env, b_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(bool_ty)), content="true")
}

///|
test "unit synthesizes UnitTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let unit_e = db.call("Unit", [])
  let _ = db.set("Typing", [env, unit_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let unit_ty = db.call("UnitTy", [])
  let result = db.lookup("HasType", [env, unit_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(unit_ty)), content="true")
}

///|
test "var with InEnv synthesizes type" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let _ = db.set("InEnv", [env, @egglog.StrVal("x")], int_ty)
  let var_e = db.call("Var", [@egglog.StrVal("x")])
  let _ = db.set("Typing", [env, var_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let result = db.lookup("HasType", [env, var_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "unbound var produces no HasType" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let unbound_e = db.call("Unbound", [@egglog.StrVal("x")])
  let _ = db.set("Typing", [env, unbound_e], @egglog.IntVal(1))
  run(db, atom_rules())
  inspect(db.lookup("HasType", [env, unbound_e]) is None, content="true")
}

///|
fn run_all(db : @egglog.Database) -> Unit {
  run(db, [..propagation_rules(), ..atom_rules(), ..arith_rules()])
}

///|
fn run_full(db : @egglog.Database) -> Unit {
  run(db, [..propagation_rules(), ..atom_rules(), ..arith_rules(), ..if_rules()])
}

///|
test "add synthesizes IntTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let add_e = db.call("Add", [n1, n2])
  let _ = db.set("Typing", [env, add_e], @egglog.IntVal(1))
  run_all(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, add_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "minus synthesizes IntTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n1 = db.call("Num", [@egglog.IntVal(5)])
  let n2 = db.call("Num", [@egglog.IntVal(3)])
  let sub_e = db.call("Minus", [n1, n2])
  let _ = db.set("Typing", [env, sub_e], @egglog.IntVal(1))
  run_all(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, sub_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "iszero synthesizes BoolTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n = db.call("Num", [@egglog.IntVal(0)])
  let iz_e = db.call("IsZero", [n])
  let _ = db.set("Typing", [env, iz_e], @egglog.IntVal(1))
  run_all(db)
  let bool_ty = db.call("BoolTy", [])
  let result = db.lookup("HasType", [env, iz_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(bool_ty)), content="true")
}

///|
test "if with matching branch types synthesizes branch type" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("BoolLit", [@egglog.IntVal(1)])
  let t = db.call("Num", [@egglog.IntVal(1)])
  let f = db.call("Num", [@egglog.IntVal(2)])
  let if_e = db.call("If", [cond, t, f])
  let _ = db.set("Typing", [env, if_e], @egglog.IntVal(1))
  run_full(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, if_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}

///|
test "if with mismatched branch types unions the type classes" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("BoolLit", [@egglog.IntVal(1)])
  let t = db.call("Num", [@egglog.IntVal(1)])      // IntTy
  let f = db.call("BoolLit", [@egglog.IntVal(0)])  // BoolTy
  let if_e = db.call("If", [cond, t, f])
  let _ = db.set("Typing", [env, if_e], @egglog.IntVal(1))
  run_full(db)
  let int_ty = db.call("IntTy", [])
  let bool_ty = db.call("BoolTy", [])
  // Both branches typed, but no shared type → HasType is not set
  // (type-if requires both branches to have the SAME type class)
  inspect(db.lookup("HasType", [env, if_e]) is None, content="true")
  // int_ty and bool_ty are NOT merged (no union happened)
  inspect(db.find(unwrap_id(int_ty)) != db.find(unwrap_id(bool_ty)), content="true")
}

///|
test "app synthesizes return type from Arrow" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // Build: f applied to 42, where f : Int -> Int
  let f_e = db.call("Var", [@egglog.StrVal("f")])
  let _ = db.set("InEnv", [env, @egglog.StrVal("f")], arr_ty)
  let arg_e = db.call("Num", [@egglog.IntVal(42)])
  let app_e = db.call("App", [f_e, arg_e])
  let _ = db.set("Typing", [env, app_e], @egglog.IntVal(1))
  run(db, [..propagation_rules(), ..atom_rules(), ..app_rules()])
  let result = db.lookup("HasType", [env, app_e])
  inspect(db.find(unwrap_id(result.unwrap())) == db.find(unwrap_id(int_ty)), content="true")
}
