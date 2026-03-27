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

///|
/// Propagation rules: seed Typing(env, child) from a typed parent.
/// These run before synthesis rules so env is always known when typing fires.
pub fn propagation_rules() -> Array[@egglog.Rule] {
  [
    // propagate-add: Typing(env, e), Add(a, b, e) → Typing(env, a), Typing(env, b)
    {
      name: "propagate-add",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Add", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("a")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("b")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-minus
    {
      name: "propagate-minus",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Minus", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("a")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("b")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-iszero
    {
      name: "propagate-iszero",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("IsZero", [@egglog.Var("inner"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("inner")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-if
    {
      name: "propagate-if",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("If", [@egglog.Var("c"), @egglog.Var("t"), @egglog.Var("f"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("c")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("t")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("f")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-app
    {
      name: "propagate-app",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("App", [@egglog.Var("f"), @egglog.Var("a"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("f")], @egglog.Lit(@egglog.IntVal(1))),
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("a")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
    // propagate-let-val: seed Typing for val so type-num/etc fire before type-let-body
    {
      name: "propagate-let-val",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Let", [@egglog.Var("x"), @egglog.Var("v"), @egglog.Var("body"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("Typing", [@egglog.Var("env"), @egglog.Var("v")], @egglog.Lit(@egglog.IntVal(1))),
      ],
    },
  ]
}

///|
/// Atom typing rules: Num, BoolLit, Unit, Var.
pub fn atom_rules() -> Array[@egglog.Rule] {
  [
    // type-num
    {
      name: "type-num",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Num", [@egglog.Var("n"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("IntTy", [])),
      ],
    },
    // type-bool
    {
      name: "type-bool",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("BoolLit", [@egglog.Var("b"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("BoolTy", [])),
      ],
    },
    // type-unit
    {
      name: "type-unit",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Unit", [@egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("UnitTy", [])),
      ],
    },
    // type-var
    {
      name: "type-var",
      query: [
        @egglog.Fact("Typing", [@egglog.Var("env"), @egglog.Var("e"), @egglog.Var("_")]),
        @egglog.Fact("Var", [@egglog.Var("x"), @egglog.Var("e")]),
        @egglog.Fact("InEnv", [@egglog.Var("env"), @egglog.Var("x"), @egglog.Var("t")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Var("t")),
      ],
    },
  ]
}

///|
/// If typing rule: condition must be BoolTy, both branches must share type.
pub fn if_rules() -> Array[@egglog.Rule] {
  [
    {
      name: "type-if",
      query: [
        @egglog.Fact("If", [@egglog.Var("c"), @egglog.Var("t"), @egglog.Var("f"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("c"), @egglog.Var("tc")]),
        @egglog.Fact("BoolTy", [@egglog.Var("tc")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("t"), @egglog.Var("ty")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("f"), @egglog.Var("ty")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Var("ty")),
      ],
    },
  ]
}

///|
/// App typing rule: f : (ta -> tb), a : ta → App(f, a) : tb
pub fn app_rules() -> Array[@egglog.Rule] {
  [
    {
      name: "type-app",
      query: [
        @egglog.Fact("App", [@egglog.Var("f"), @egglog.Var("a"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("f"), @egglog.Var("arr")]),
        @egglog.Fact("Arrow", [@egglog.Var("ta"), @egglog.Var("tb"), @egglog.Var("arr")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("a"), @egglog.Var("ta")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Var("tb")),
      ],
    },
  ]
}

///|
/// Arithmetic and IsZero typing rules.
pub fn arith_rules() -> Array[@egglog.Rule] {
  [
    // type-add: Add(a, b, e), HasType(env, a)=IntTy, HasType(env, b)=IntTy → HasType(env, e)=IntTy
    {
      name: "type-add",
      query: [
        @egglog.Fact("Add", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("a"), @egglog.Var("ta")]),
        @egglog.Fact("IntTy", [@egglog.Var("ta")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("b"), @egglog.Var("tb")]),
        @egglog.Fact("IntTy", [@egglog.Var("tb")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("IntTy", [])),
      ],
    },
    // type-minus: identical structure to type-add
    {
      name: "type-minus",
      query: [
        @egglog.Fact("Minus", [@egglog.Var("a"), @egglog.Var("b"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("a"), @egglog.Var("ta")]),
        @egglog.Fact("IntTy", [@egglog.Var("ta")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("b"), @egglog.Var("tb")]),
        @egglog.Fact("IntTy", [@egglog.Var("tb")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("IntTy", [])),
      ],
    },
    // type-iszero: IsZero(inner, e), HasType(env, inner)=IntTy → HasType(env, e)=BoolTy
    {
      name: "type-iszero",
      query: [
        @egglog.Fact("IsZero", [@egglog.Var("inner"), @egglog.Var("e")]),
        @egglog.Fact("HasType", [@egglog.Var("env"), @egglog.Var("inner"), @egglog.Var("ti")]),
        @egglog.Fact("IntTy", [@egglog.Var("ti")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("env"), @egglog.Var("e")], @egglog.Call("BoolTy", [])),
      ],
    },
  ]
}
