///|
/// Create a database with all lambda calculus constructors and relations.
///
/// Tables:
///   Expressions: Num, BoolLit, Var, Add, Minus, IsZero, If,
///                Lam, App, Let, Unit, Unbound, Error
///   Types:       IntTy, BoolTy, UnitTy, Arrow
///   Envs:        EmptyEnv, ExtendEnv
///   Relations:   HasType(env, expr)->type, InEnv(env, name)->type,
///                Typing(env, expr)->IntVal(1)
pub fn lambda_db() -> @egglog.Database {
  let db = @egglog.Database::new()
  db.register("Num") // Num(IntVal n) -> expr_id
  db.register("BoolLit") // BoolLit(IntVal b) -> expr_id  (1=true, 0=false)
  db.register("Var") // Var(StrVal name) -> expr_id
  db.register("Add") // Add(left, right) -> expr_id
  db.register("Minus") // Minus(left, right) -> expr_id
  db.register("IsZero") // IsZero(expr) -> expr_id
  db.register("If") // If(cond, then, else_) -> expr_id
  db.register("Lam") // Lam(StrVal name, body) -> expr_id
  db.register("App") // App(func, arg) -> expr_id
  db.register("Let") // Let(StrVal name, val, body) -> expr_id
  db.register("Unit") // Unit() -> expr_id
  db.register("Unbound") // Unbound(StrVal name) -> expr_id  (never typed)
  db.register("Error") // Error(StrVal msg) -> expr_id     (never typed)
  db.register("IntTy") // IntTy() -> type_id
  db.register("BoolTy") // BoolTy() -> type_id
  db.register("UnitTy") // UnitTy() -> type_id
  db.register("Arrow") // Arrow(domain, codomain) -> type_id
  db.register("EmptyEnv") // EmptyEnv() -> env_id
  db.register("ExtendEnv") // ExtendEnv(parent, StrVal name, type) -> env_id
  db.register("HasType") // HasType(env_id, expr_id) -> type_id
  db.register("InEnv") // InEnv(env_id, StrVal name) -> type_id
  db.register("Typing") // Typing(env_id, expr_id) -> IntVal(1)  (trigger)
  db
}

///|
/// Host-language environment tracker.
///
/// Calling `extend` creates a new `ExtendEnv` e-class and pre-seeds
/// `InEnv(new_env, name) = ty` for **all** currently visible bindings —
/// including those inherited from outer scopes. Inner bindings shadow outer
/// ones because `Map` overwrite happens in MoonBit before seeding.
pub struct LambdaEnv {
  id : @egglog.Value
  bindings : Map[String, @egglog.Value]
}

///|
pub fn LambdaEnv::make(db : @egglog.Database) -> LambdaEnv {
  { id: db.call("EmptyEnv", []), bindings: {} }
}

///|
pub fn LambdaEnv::extend(
  self : LambdaEnv,
  db : @egglog.Database,
  name : String,
  ty : @egglog.Value,
) -> LambdaEnv {
  let new_id = db.call("ExtendEnv", [self.id, @egglog.StrVal(name), ty])
  let new_bindings : Map[String, @egglog.Value] = {}
  for k, v in self.bindings {
    new_bindings[k] = v
  }
  new_bindings[name] = ty // shadow: innermost binding wins
  // Seed InEnv for every visible binding (transitive closure)
  for bname, btype in new_bindings {
    let _ = db.set("InEnv", [new_id, @egglog.StrVal(bname)], btype)
  }
  { id: new_id, bindings: new_bindings }
}
