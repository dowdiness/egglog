///|
fn run(db : @egglog.Database, rules : Array[@egglog.Rule]) -> Unit {
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(rules), 30))
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
/// True when two Values are in the same e-class.
fn same_class(
  db : @egglog.Database,
  a : @egglog.Value,
  b : @egglog.Value,
) -> Bool {
  db.find(unwrap_id(a)) == db.find(unwrap_id(b))
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
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
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
  inspect(same_class(db, result.unwrap(), bool_ty), content="true")
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
  inspect(same_class(db, result.unwrap(), unit_ty), content="true")
}

///|
test "var with TypeEnv synthesizes type" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let _ = db.set("TypeEnv", [env, @egglog.StrVal("x")], int_ty)
  let var_e = db.call("Var", [@egglog.StrVal("x")])
  let _ = db.set("Typing", [env, var_e], @egglog.IntVal(1))
  run(db, atom_rules())
  let result = db.lookup("HasType", [env, var_e])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
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
test "var with no TypeEnv entry produces no HasType" {
  // Exercises the failure path of type-var: Var("x") in a scope where
  // no TypeEnv(env, "x") fact exists. Different from the Unbound constructor
  // test above — this is a real Var node that type-var tries and fails to match.
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let var_e = db.call("Var", [@egglog.StrVal("x")])
  let _ = db.set("Typing", [env, var_e], @egglog.IntVal(1))
  run(db, atom_rules())
  inspect(db.lookup("HasType", [env, var_e]) is None, content="true")
}

///|
test "if: non-bool condition produces no HasType" {
  // type-if requires HasType(env, cond) ∈ BoolTy — an Int condition cannot fire it.
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let n3 = db.call("Num", [@egglog.IntVal(3)])
  let if_e = db.call("If", [n1, n2, n3])
  let _ = db.set("Typing", [env, if_e], @egglog.IntVal(1))
  run_arith_if(db)
  inspect(db.lookup("HasType", [env, if_e]) is None, content="true")
}

///|
test "add: non-int left operand produces no HasType" {
  // type-add requires both operands to have IntTy; BoolTy on the left blocks it.
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let bt = db.call("BoolLit", [@egglog.IntVal(1)])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let add_e = db.call("Add", [bt, n1])
  let _ = db.set("Typing", [env, add_e], @egglog.IntVal(1))
  run_arith(db)
  inspect(db.lookup("HasType", [env, add_e]) is None, content="true")
}

///|
test "app: non-arrow callee produces no HasType" {
  // type-app requires HasType(env, f) ∈ Arrow — an IntTy callee cannot fire it.
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let f_e = db.call("Var", [@egglog.StrVal("f")])
  let _ = db.set("TypeEnv", [env, @egglog.StrVal("f")], int_ty)
  let arg_e = db.call("Num", [@egglog.IntVal(42)])
  let app_e = db.call("App", [f_e, arg_e])
  let _ = db.set("Typing", [env, app_e], @egglog.IntVal(1))
  run(db, [..propagation_rules(), ..atom_rules(), ..app_rules()])
  inspect(db.lookup("HasType", [env, app_e]) is None, content="true")
}

///|
test "check-lam: codomain seeded enables nested lambda checking" {
  // (λx. λy. x + y) : Int -> Int -> Int
  // Requires fix: check-lam must seed HasType(ext_env, body) = b so the inner
  // lambda gets its expected type automatically. LambdaEnv is used here for
  // transitive TypeEnv seeding (outer var x visible in inner scope).
  let db = lambda_db()
  let int_ty = db.call("IntTy", [])
  let inner_arr = db.call("Arrow", [int_ty, int_ty]) // Int -> Int
  let outer_arr = db.call("Arrow", [int_ty, inner_arr]) // Int -> Int -> Int
  let env0 = LambdaEnv::make(db)
  let env_x = env0.extend(db, "x", int_ty)
  let env_xy = env_x.extend(db, "y", int_ty)
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let var_y = db.call("Var", [@egglog.StrVal("y")])
  let body = db.call("Add", [var_x, var_y])
  let inner_lam = db.call("Lam", [@egglog.StrVal("y"), body])
  let outer_lam = db.call("Lam", [@egglog.StrVal("x"), inner_lam])
  let _ = db.set("Typing", [env0.id, outer_lam], @egglog.IntVal(1))
  let _ = db.set("HasType", [env0.id, outer_lam], outer_arr)
  run(
    db,
    [..propagation_rules(), ..atom_rules(), ..arith_rules(), ..lam_rules()],
  )
  // body (x + y) should have type Int in env_xy
  let result = db.lookup("HasType", [env_xy.id, body])
  inspect(result is Some(_), content="true")
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}

///|
fn run_arith(db : @egglog.Database) -> Unit {
  run(db, [..propagation_rules(), ..atom_rules(), ..arith_rules()])
}

///|
fn run_arith_if(db : @egglog.Database) -> Unit {
  run(
    db,
    [..propagation_rules(), ..atom_rules(), ..arith_rules(), ..if_rules()],
  )
}

///|
test "add synthesizes IntTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let add_e = db.call("Add", [n1, n2])
  let _ = db.set("Typing", [env, add_e], @egglog.IntVal(1))
  run_arith(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, add_e])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}

///|
test "minus synthesizes IntTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n1 = db.call("Num", [@egglog.IntVal(5)])
  let n2 = db.call("Num", [@egglog.IntVal(3)])
  let sub_e = db.call("Minus", [n1, n2])
  let _ = db.set("Typing", [env, sub_e], @egglog.IntVal(1))
  run_arith(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, sub_e])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}

///|
test "iszero synthesizes BoolTy" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let n = db.call("Num", [@egglog.IntVal(0)])
  let iz_e = db.call("IsZero", [n])
  let _ = db.set("Typing", [env, iz_e], @egglog.IntVal(1))
  run_arith(db)
  let bool_ty = db.call("BoolTy", [])
  let result = db.lookup("HasType", [env, iz_e])
  inspect(same_class(db, result.unwrap(), bool_ty), content="true")
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
  run_arith_if(db)
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, if_e])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}

///|
test "if with mismatched branch types unions the type classes" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let cond = db.call("BoolLit", [@egglog.IntVal(1)])
  let t = db.call("Num", [@egglog.IntVal(1)]) // IntTy
  let f = db.call("BoolLit", [@egglog.IntVal(0)]) // BoolTy
  let if_e = db.call("If", [cond, t, f])
  let _ = db.set("Typing", [env, if_e], @egglog.IntVal(1))
  run_arith_if(db)
  let int_ty = db.call("IntTy", [])
  let bool_ty = db.call("BoolTy", [])
  // Both branches typed, but no shared type → HasType is not set
  // (type-if requires both branches to have the SAME type class)
  inspect(db.lookup("HasType", [env, if_e]) is None, content="true")
  // int_ty and bool_ty are NOT merged (no union happened)
  inspect(!same_class(db, int_ty, bool_ty), content="true")
}

///|
test "app synthesizes return type from Arrow" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // Build: f applied to 42, where f : Int -> Int
  let f_e = db.call("Var", [@egglog.StrVal("f")])
  let _ = db.set("TypeEnv", [env, @egglog.StrVal("f")], arr_ty)
  let arg_e = db.call("Num", [@egglog.IntVal(42)])
  let app_e = db.call("App", [f_e, arg_e])
  let _ = db.set("Typing", [env, app_e], @egglog.IntVal(1))
  run(db, [..propagation_rules(), ..atom_rules(), ..app_rules()])
  let result = db.lookup("HasType", [env, app_e])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}

///|
test "let binding synthesizes body type" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  // let x = 42 in x + 1
  let num_42 = db.call("Num", [@egglog.IntVal(42)])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let let_e = db.call("Let", [@egglog.StrVal("x"), num_42, body])
  let _ = db.set("Typing", [env, let_e], @egglog.IntVal(1))
  run(
    db,
    [..propagation_rules(), ..atom_rules(), ..arith_rules(), ..let_rules()],
  )
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, let_e])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}

///|
test "check-lam: lambda body typed in extended env" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // λx. x + 1, seeded with expected type Int -> Int
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let _ = db.set("Typing", [env, lam_e], @egglog.IntVal(1))
  let _ = db.set("HasType", [env, lam_e], arr_ty) // seed expected type
  run(
    db,
    [..propagation_rules(), ..atom_rules(), ..arith_rules(), ..lam_rules()],
  )
  // body should be typed as Int in the extended env
  let ext_env = db.call("ExtendEnv", [env, @egglog.StrVal("x"), int_ty])
  let result = db.lookup("HasType", [ext_env, body])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}

///|
test "let shadowing: inner x shadows outer x" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  // let x = 1 in let x = true in x
  // outer x : Int, inner x : Bool → result should be BoolTy
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let bool_true = db.call("BoolLit", [@egglog.IntVal(1)])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let inner_let = db.call("Let", [@egglog.StrVal("x"), bool_true, var_x])
  let outer_let = db.call("Let", [@egglog.StrVal("x"), num_1, inner_let])
  let _ = db.set("Typing", [env, outer_let], @egglog.IntVal(1))
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(all_rules()), 30))
  let bool_ty = db.call("BoolTy", [])
  let int_ty = db.call("IntTy", [])
  let result = db.lookup("HasType", [env, outer_let])
  // inner x is BoolTy, so outer_let : BoolTy
  inspect(same_class(db, result.unwrap(), bool_ty), content="true")
  // IntTy and BoolTy are NOT unioned (no type error occurred)
  inspect(!same_class(db, int_ty, bool_ty), content="true")
}

///|
test "app + lam full round-trip" {
  let db = lambda_db()
  let env = db.call("EmptyEnv", [])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // (λx. x + 1) 42
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let num_42 = db.call("Num", [@egglog.IntVal(42)])
  let app_e = db.call("App", [lam_e, num_42])
  let _ = db.set("Typing", [env, app_e], @egglog.IntVal(1))
  let _ = db.set("HasType", [env, lam_e], arr_ty) // seed lam type
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(all_rules()), 30))
  let result = db.lookup("HasType", [env, app_e])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}

///|
test "LambdaEnv inherited bindings: let x=1 in let y=2 in x+y" {
  // Exercises LambdaEnv::extend transitive seeding.
  // When typing the body `x+y` in env2 (x:Int, y:Int), both x and y must be
  // visible. LambdaEnv::extend copies ALL outer bindings into the new env,
  // so TypeEnv(env2, "x") = IntTy is seeded even though only y is the new binding.
  // Without transitive seeding, the `type-var` rule for x would find no TypeEnv
  // entry in env2 and x+y would not type-check.
  let db = lambda_db()
  let int_ty = db.call("IntTy", [])
  let env0 = LambdaEnv::make(db)
  // env1 = {x: IntTy}
  let env1 = env0.extend(db, "x", int_ty)
  // env2 = {x: IntTy, y: IntTy}  (transitive: x is inherited from env1)
  let env2 = env1.extend(db, "y", int_ty)
  // Build: let x = 1 in let y = 2 in x + y
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let num_2 = db.call("Num", [@egglog.IntVal(2)])
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let var_y = db.call("Var", [@egglog.StrVal("y")])
  let body = db.call("Add", [var_x, var_y])
  // Seed Typing for each sub-expression in the appropriate env
  let _ = db.set("Typing", [env2.id, body], @egglog.IntVal(1))
  let _ = db.set("Typing", [env1.id, num_2], @egglog.IntVal(1))
  let _ = db.set("Typing", [env0.id, num_1], @egglog.IntVal(1))
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(all_rules()), 30))
  // body (x + y) : Int in env2 — requires both x and y visible via TypeEnv
  let result = db.lookup("HasType", [env2.id, body])
  inspect(same_class(db, result.unwrap(), int_ty), content="true")
}
