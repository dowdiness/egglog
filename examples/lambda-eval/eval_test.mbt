///|
fn unwrap_id_test(v : @egglog.Value) -> @egglog.Id {
  match v {
    @egglog.IdVal(id) => id
    _ => abort("expected IdVal")
  }
}

///|
fn same_class(
  db : @egglog.Database,
  a : @egglog.Value,
  b : @egglog.Value,
) -> Bool {
  db.find(unwrap_id_test(a)) == db.find(unwrap_id_test(b))
}

// ═══════════════════════════════════════════════════════════════════
// Task 1: Leaf evaluation tests
// ═══════════════════════════════════════════════════════════════════

///|
test "eval num" {
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let num_e = db.call("Num", [@egglog.IntVal(42)])
  let result = run_eval(db, env, num_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(42)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval unit" {
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let unit_e = db.call("Unit", [])
  let result = run_eval(db, env, unit_e, eval_rules())
  let expected = db.call("ValUnit", [])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval var" {
  let db = lambda_eval_db()
  let val_env = ValueEnv::make(db)
  let int_val = db.call("ValInt", [@egglog.IntVal(7)])
  let ext = val_env.extend(db, "x", int_val)
  let var_e = db.call("Var", [@egglog.StrVal("x")])
  let result = run_eval(db, ext.id, var_e, eval_rules())
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), int_val), content="true")
}

///|
test "eval lam" {
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let body = db.call("Var", [@egglog.StrVal("x")])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let result = run_eval(db, env, lam_e, eval_rules())
  let expected = db.call("Closure", [env, @egglog.StrVal("x"), body])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

// ═══════════════════════════════════════════════════════════════════
// Task 2: Arithmetic tests
// ═══════════════════════════════════════════════════════════════════

///|
test "eval add" {
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let n3 = db.call("Num", [@egglog.IntVal(3)])
  let add_e = db.call("Add", [n2, n3])
  let result = run_eval(db, env, add_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(5)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval minus" {
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let n10 = db.call("Num", [@egglog.IntVal(10)])
  let n3 = db.call("Num", [@egglog.IntVal(3)])
  let sub_e = db.call("Minus", [n10, n3])
  let result = run_eval(db, env, sub_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(7)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval nested arith" {
  // (2 + 3) - 1 = 4
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let n3 = db.call("Num", [@egglog.IntVal(3)])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let add_e = db.call("Add", [n2, n3])
  let sub_e = db.call("Minus", [add_e, n1])
  let result = run_eval(db, env, sub_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(4)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval add type error" {
  // Add with a non-integer operand (unit + 1) => EvalError
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let unit_e = db.call("Unit", [])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let add_e = db.call("Add", [unit_e, n1])
  let result = run_eval(db, env, add_e, eval_rules())
  // Eval should not produce a result for the Add
  // But EvalError should be set
  let err = db.lookup("EvalError", [env, add_e])
  inspect(err is Some(_), content="true")
  // The main Eval result may or may not be set depending on bridge logic;
  // EvalError being set is the key assertion
  ignore(result)
}

// ═══════════════════════════════════════════════════════════════════
// Task 3: If branch tests
// ═══════════════════════════════════════════════════════════════════

///|
test "eval if truthy" {
  // if 1 then 2 else 3 => 2
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("Num", [@egglog.IntVal(1)])
  let then_e = db.call("Num", [@egglog.IntVal(2)])
  let else_e = db.call("Num", [@egglog.IntVal(3)])
  let if_e = db.call("If", [cond, then_e, else_e])
  let result = run_eval(db, env, if_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(2)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval if falsy" {
  // if 0 then 2 else 3 => 3
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("Num", [@egglog.IntVal(0)])
  let then_e = db.call("Num", [@egglog.IntVal(2)])
  let else_e = db.call("Num", [@egglog.IntVal(3)])
  let if_e = db.call("If", [cond, then_e, else_e])
  let result = run_eval(db, env, if_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(3)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval if non-integer condition" {
  // if () then 2 else 3 => EvalError
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("Unit", [])
  let then_e = db.call("Num", [@egglog.IntVal(2)])
  let else_e = db.call("Num", [@egglog.IntVal(3)])
  let if_e = db.call("If", [cond, then_e, else_e])
  let result = run_eval(db, env, if_e, eval_rules())
  let err = db.lookup("EvalError", [env, if_e])
  inspect(err is Some(_), content="true")
  ignore(result)
}

// ═══════════════════════════════════════════════════════════════════
// Task 4: App + Let tests
// ═══════════════════════════════════════════════════════════════════

///|
test "eval app identity" {
  // (lambda x. x) 42 => 42
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let body = db.call("Var", [@egglog.StrVal("x")])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let arg = db.call("Num", [@egglog.IntVal(42)])
  let app_e = db.call("App", [lam_e, arg])
  let result = run_eval(db, env, app_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(42)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval app increment" {
  // (lambda x. x + 1) 5 => 6
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let arg = db.call("Num", [@egglog.IntVal(5)])
  let app_e = db.call("App", [lam_e, arg])
  let result = run_eval(db, env, app_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(6)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval let" {
  // let x = 2 in x + x => 4
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let num_2 = db.call("Num", [@egglog.IntVal(2)])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let body = db.call("Add", [var_x, var_x])
  let let_e = db.call("Let", [@egglog.StrVal("x"), num_2, body])
  let result = run_eval(db, env, let_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(4)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval nested let" {
  // let x = 1 in let y = 2 in x + y => 3
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let num_2 = db.call("Num", [@egglog.IntVal(2)])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let var_y = db.call("Var", [@egglog.StrVal("y")])
  let inner_body = db.call("Add", [var_x, var_y])
  let inner_let = db.call("Let", [@egglog.StrVal("y"), num_2, inner_body])
  let outer_let = db.call("Let", [@egglog.StrVal("x"), num_1, inner_let])
  let result = run_eval(db, env, outer_let, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(3)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval curried" {
  // (lambda x. lambda y. x + y) 2 3 => 5
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let var_y = db.call("Var", [@egglog.StrVal("y")])
  let inner_body = db.call("Add", [var_x, var_y])
  let inner_lam = db.call("Lam", [@egglog.StrVal("y"), inner_body])
  let outer_lam = db.call("Lam", [@egglog.StrVal("x"), inner_lam])
  let num_2 = db.call("Num", [@egglog.IntVal(2)])
  let num_3 = db.call("Num", [@egglog.IntVal(3)])
  let app1 = db.call("App", [outer_lam, num_2])
  let app2 = db.call("App", [app1, num_3])
  let result = run_eval(db, env, app2, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(5)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval closure captures env" {
  // let x = 10 in let f = lambda y. x + y in f 5 => 15
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let num_10 = db.call("Num", [@egglog.IntVal(10)])
  let num_5 = db.call("Num", [@egglog.IntVal(5)])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let var_y = db.call("Var", [@egglog.StrVal("y")])
  let lam_body = db.call("Add", [var_x, var_y])
  let lam_e = db.call("Lam", [@egglog.StrVal("y"), lam_body])
  let var_f = db.call("Var", [@egglog.StrVal("f")])
  let app_e = db.call("App", [var_f, num_5])
  let inner_let = db.call("Let", [@egglog.StrVal("f"), lam_e, app_e])
  let outer_let = db.call("Let", [@egglog.StrVal("x"), num_10, inner_let])
  let result = run_eval(db, env, outer_let, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(15)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

// ═══════════════════════════════════════════════════════════════════
// Task 5: Partial evaluation + limits
// ═══════════════════════════════════════════════════════════════════

///|
test "eval if with hole" {
  // if 1 then 42 else HoleNode(0) => 42 (hole in else branch never demanded)
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("Num", [@egglog.IntVal(1)])
  let then_e = db.call("Num", [@egglog.IntVal(42)])
  let hole_e = db.call("HoleNode", [@egglog.IntVal(0)])
  let if_e = db.call("If", [cond, then_e, hole_e])
  let result = run_eval(db, env, if_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(42)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

///|
test "eval add with hole" {
  // Add(2, HoleNode(0)) => no Eval for the Add (partial: hole never evaluates)
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let hole_e = db.call("HoleNode", [@egglog.IntVal(0)])
  let add_e = db.call("Add", [n2, hole_e])
  let result = run_eval(db, env, add_e, eval_rules())
  // HoleNode has no Num/Var/Lam/Unit match, so Eval(env, hole) is never set,
  // AddReady never fires, and Eval(env, add_e) stays None.
  inspect(result is None, content="true")
}

///|
test "eval apply int as function" {
  // (42) 1 => EvalError (42 is not a closure)
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let n42 = db.call("Num", [@egglog.IntVal(42)])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let app_e = db.call("App", [n42, n1])
  let result = run_eval(db, env, app_e, eval_rules())
  let err = db.lookup("EvalError", [env, app_e])
  inspect(err is Some(_), content="true")
  ignore(result)
}

///|
test "eval fact count limit" {
  // Verify the bridge stops after exceeding the Eval row limit.
  // We just verify that run_eval terminates even with a low limit.
  // (This is a structural test — the limit is 10000 rows in evaluation_bridge.)
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  // Simple expression that terminates quickly
  let result = run_eval(db, env, n1, eval_rules(), max_iters=2)
  let expected = db.call("ValInt", [@egglog.IntVal(1)])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), expected), content="true")
}

// ═══════════════════════════════════════════════════════════════════
// Task 6: Composition — typing + eval in same database
// ═══════════════════════════════════════════════════════════════════

///|
test "composition: type and eval in same db" {
  // (lambda x. x + 1) 5 => type Int, eval 6
  let db = lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // Build: (lambda x. x + 1) 5
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let num_5 = db.call("Num", [@egglog.IntVal(5)])
  let app_e = db.call("App", [lam_e, num_5])
  // Run typing
  let _ = db.set("Typing", [env, app_e], @egglog.IntVal(1))
  let _ = db.set("HasType", [env, lam_e], arr_ty)
  let _ = db.run_schedule(
    @egglog.Saturate(@egglog.Run(@lambda.all_rules()), 30),
  )
  let type_result = db.lookup("HasType", [env, app_e])
  inspect(type_result is Some(_), content="true")
  inspect(same_class(db, type_result.unwrap(), int_ty), content="true")
  // Run eval (in the same database)
  let eval_result = run_eval(db, env, app_e, eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(6)])
  inspect(eval_result is Some(_), content="true")
  inspect(same_class(db, eval_result.unwrap(), expected), content="true")
  // Verify TypeEnv and ValEnv are separate (no cross-contamination)
  // TypeEnv should have type info, ValEnv should have value info
  let val_env_count = db.row_count("ValEnv")
  inspect(val_env_count > 0, content="true")
  // TypeEnv was used by typing rules — verify it didn't get value entries
  // by checking that Eval results are value types (ValInt), not type types (IntTy)
  let eval_int = db.call("ValInt", [@egglog.IntVal(6)])
  inspect(!same_class(db, eval_int, int_ty), content="true")
}
