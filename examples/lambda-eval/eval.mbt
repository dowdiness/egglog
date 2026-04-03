///|
/// Create a database with lambda calculus constructors plus eval-specific tables.
///
/// Inherits all expression, type, and environment constructors from `lambda_db()`,
/// then adds evaluation tables: Demand, Eval, ValEnv, Closure, ValInt, ValUnit,
/// trigger tables (AddReady, MinusReady, IfReady, AppReady, LetReady),
/// bridge metadata (IfBranch, AppBodyEnv, AppBody, LetBodyEnv, LetBody),
/// and error/sentinel tables (EvalError, HoleNode, ErrorNode, UnboundNode).
pub fn lambda_eval_db() -> @egglog.Database {
  let db = @lambda.lambda_db()
  // Eval-specific tables
  db.register("Demand") // Demand(env, expr) -> IntVal(1)
  db.register("Eval") // Eval(env, expr) -> value_id
  db.register("ValEnv") // ValEnv(env, name) -> value_id
  db.register("Closure") // Closure(env, x, body) -> id
  db.register("ValInt") // ValInt(IntVal(n)) -> id
  db.register("ValUnit") // ValUnit() -> id
  // Trigger tables
  db.register("AddReady") // AddReady(env, expr) -> IntVal(1)
  db.register("MinusReady") // MinusReady(env, expr) -> IntVal(1)
  db.register("IfReady") // IfReady(env, expr) -> IntVal(1)
  db.register("AppReady") // AppReady(env, expr) -> IntVal(1)
  db.register("LetReady") // LetReady(env, expr) -> IntVal(1)
  // Bridge metadata
  db.register("IfBranch") // IfBranch(env, expr) -> branch_expr_id
  db.register("AppBodyEnv") // AppBodyEnv(env, expr) -> ext_env_id
  db.register("AppBody") // AppBody(env, expr) -> body_id
  db.register("LetBodyEnv") // LetBodyEnv(env, expr) -> ext_env_id
  db.register("LetBody") // LetBody(env, expr) -> body_id
  // Error and sentinel tables
  db.register("EvalError") // EvalError(env, expr) -> StrVal(msg)
  db.register("HoleNode") // HoleNode(IntVal(tag)) -> id
  db.register("ErrorNode") // ErrorNode(StrVal(msg)) -> id
  db.register("UnboundNode") // UnboundNode(StrVal(name)) -> id
  db
}

///|
/// Demand propagation rules: seed Demand for sub-expressions.
pub fn demand_rules() -> Array[@egglog.Rule] {
  [
    // demand-app: Demand(env, e), App(f, arg, e) => Demand(env, f), Demand(env, arg)
    {
      name: "demand-app",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("App", [
          @egglog.Var("f"),
          @egglog.Var("arg"),
          @egglog.Var("e"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Demand",
          [@egglog.Var("env"), @egglog.Var("f")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
        @egglog.Set(
          "Demand",
          [@egglog.Var("env"), @egglog.Var("arg")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
    // demand-add: Demand(env, e), Add(a, b, e) => Demand(env, a), Demand(env, b)
    {
      name: "demand-add",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Add", [
          @egglog.Var("a"),
          @egglog.Var("b"),
          @egglog.Var("e"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Demand",
          [@egglog.Var("env"), @egglog.Var("a")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
        @egglog.Set(
          "Demand",
          [@egglog.Var("env"), @egglog.Var("b")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
    // demand-minus: Demand(env, e), Minus(a, b, e) => Demand(env, a), Demand(env, b)
    {
      name: "demand-minus",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Minus", [
          @egglog.Var("a"),
          @egglog.Var("b"),
          @egglog.Var("e"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Demand",
          [@egglog.Var("env"), @egglog.Var("a")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
        @egglog.Set(
          "Demand",
          [@egglog.Var("env"), @egglog.Var("b")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
    // demand-if-cond: Demand(env, e), If(c, t, el, e) => Demand(env, c)
    {
      name: "demand-if-cond",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("If", [
          @egglog.Var("c"),
          @egglog.Var("t"),
          @egglog.Var("el"),
          @egglog.Var("e"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Demand",
          [@egglog.Var("env"), @egglog.Var("c")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
    // demand-let-val: Demand(env, e), Let(x, val, body, e) => Demand(env, val)
    {
      name: "demand-let-val",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Let", [
          @egglog.Var("x"),
          @egglog.Var("val"),
          @egglog.Var("body"),
          @egglog.Var("e"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Demand",
          [@egglog.Var("env"), @egglog.Var("val")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
  ]
}

///|
/// Leaf resolution rules: evaluate atoms that need no sub-evaluation.
pub fn leaf_rules() -> Array[@egglog.Rule] {
  [
    // resolve-num: Demand(env, e), Num(n, e) => Eval(env, e) = ValInt(n)
    {
      name: "resolve-num",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Num", [@egglog.Var("n"), @egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set(
          "Eval",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Call("ValInt", [@egglog.Var("n")]),
        ),
      ],
    },
    // resolve-var: Demand(env, e), Var(x, e), ValEnv(env, x, v) => Eval(env, e) = v
    {
      name: "resolve-var",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Var", [@egglog.Var("x"), @egglog.Var("e")]),
        @egglog.Fact("ValEnv", [
          @egglog.Var("env"),
          @egglog.Var("x"),
          @egglog.Var("v"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Eval",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Var("v"),
        ),
      ],
    },
    // resolve-lam: Demand(env, e), Lam(x, body, e) => Eval(env, e) = Closure(env, x, body)
    {
      name: "resolve-lam",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Lam", [
          @egglog.Var("x"),
          @egglog.Var("body"),
          @egglog.Var("e"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Eval",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Call("Closure", [
            @egglog.Var("env"),
            @egglog.Var("x"),
            @egglog.Var("body"),
          ]),
        ),
      ],
    },
    // resolve-unit: Demand(env, e), Unit(e) => Eval(env, e) = ValUnit()
    {
      name: "resolve-unit",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Unit", [@egglog.Var("e")]),
      ],
      actions: [
        @egglog.Set(
          "Eval",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Call("ValUnit", []),
        ),
      ],
    },
  ]
}

///|
/// Trigger detection rules: detect when sub-expressions are evaluated.
pub fn trigger_rules() -> Array[@egglog.Rule] {
  [
    // trigger-add: Demand(env, e), Add(a, b, e), Eval(env, a, va), Eval(env, b, vb) => AddReady(env, e) = IntVal(1)
    {
      name: "trigger-add",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Add", [
          @egglog.Var("a"),
          @egglog.Var("b"),
          @egglog.Var("e"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("a"),
          @egglog.Var("va"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("b"),
          @egglog.Var("vb"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "AddReady",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
    // trigger-minus
    {
      name: "trigger-minus",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Minus", [
          @egglog.Var("a"),
          @egglog.Var("b"),
          @egglog.Var("e"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("a"),
          @egglog.Var("va"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("b"),
          @egglog.Var("vb"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "MinusReady",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
    // trigger-if: condition is evaluated
    {
      name: "trigger-if",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("If", [
          @egglog.Var("c"),
          @egglog.Var("t"),
          @egglog.Var("el"),
          @egglog.Var("e"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("c"),
          @egglog.Var("vc"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "IfReady",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
    // trigger-app: function and argument are evaluated
    {
      name: "trigger-app",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("App", [
          @egglog.Var("f"),
          @egglog.Var("arg"),
          @egglog.Var("e"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("f"),
          @egglog.Var("clos"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("arg"),
          @egglog.Var("v"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "AppReady",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
    // trigger-let: value is evaluated
    {
      name: "trigger-let",
      query: [
        @egglog.Fact("Demand", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("_"),
        ]),
        @egglog.Fact("Let", [
          @egglog.Var("x"),
          @egglog.Var("val"),
          @egglog.Var("body"),
          @egglog.Var("e"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("val"),
          @egglog.Var("v"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "LetReady",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Lit(@egglog.IntVal(1)),
        ),
      ],
    },
  ]
}

///|
/// Result propagation rules: propagate results from bridge-created facts.
pub fn result_rules() -> Array[@egglog.Rule] {
  [
    // resolve-if: IfBranch(env, e, branch), Eval(env, branch, result) => Eval(env, e) = result
    {
      name: "resolve-if",
      query: [
        @egglog.Fact("IfBranch", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("branch"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("env"),
          @egglog.Var("branch"),
          @egglog.Var("result"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Eval",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Var("result"),
        ),
      ],
    },
    // resolve-app: AppBodyEnv(env, e, ext), AppBody(env, e, body), Eval(ext, body, result) => Eval(env, e) = result
    {
      name: "resolve-app",
      query: [
        @egglog.Fact("AppBodyEnv", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("ext"),
        ]),
        @egglog.Fact("AppBody", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("body"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("ext"),
          @egglog.Var("body"),
          @egglog.Var("result"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Eval",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Var("result"),
        ),
      ],
    },
    // resolve-let: LetBodyEnv(env, e, ext), LetBody(env, e, body), Eval(ext, body, result) => Eval(env, e) = result
    {
      name: "resolve-let",
      query: [
        @egglog.Fact("LetBodyEnv", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("ext"),
        ]),
        @egglog.Fact("LetBody", [
          @egglog.Var("env"),
          @egglog.Var("e"),
          @egglog.Var("body"),
        ]),
        @egglog.Fact("Eval", [
          @egglog.Var("ext"),
          @egglog.Var("body"),
          @egglog.Var("result"),
        ]),
      ],
      actions: [
        @egglog.Set(
          "Eval",
          [@egglog.Var("env"), @egglog.Var("e")],
          @egglog.Var("result"),
        ),
      ],
    },
  ]
}

///|
/// All 17 eval rules combined.
pub fn eval_rules() -> Array[@egglog.Rule] {
  [..demand_rules(), ..leaf_rules(), ..trigger_rules(), ..result_rules()]
}

///|
/// Host-side value environment tracker.
///
/// Mirrors the egglog environment structure on the host side so the bridge
/// can reconstruct bindings when creating extended environments for closures
/// and let-bindings.
pub struct ValueEnv {
  id : @egglog.Value
  bindings : Map[String, @egglog.Value]
}

///|
/// Create an empty value environment.
pub fn ValueEnv::make(db : @egglog.Database) -> ValueEnv {
  { id: db.call("EmptyEnv", []), bindings: {} }
}

///|
/// Extend the environment with a new binding.
///
/// Creates ExtendEnv in the database, copies all parent bindings plus the new
/// one, and seeds ValEnv for every visible binding in the extended environment.
pub fn ValueEnv::extend(
  self : ValueEnv,
  db : @egglog.Database,
  name : String,
  value : @egglog.Value,
) -> ValueEnv {
  let new_id = db.call("ExtendEnv", [self.id, @egglog.StrVal(name), value])
  let new_bindings : Map[String, @egglog.Value] = {}
  for k, v in self.bindings {
    new_bindings[k] = v
  }
  new_bindings[name] = value
  for bname, bval in new_bindings {
    let _ = db.set("ValEnv", [new_id, @egglog.StrVal(bname)], bval)
  }
  { id: new_id, bindings: new_bindings }
}

///|
/// Extract the integer value from a ValInt e-class.
///
/// Scans the ValInt table to find the entry whose result id matches
/// the given value's canonical id.
fn extract_int(db : @egglog.Database, val : @egglog.Value) -> Int? {
  let val_id = db.find(unwrap_id(val))
  for row in db.scan("ValInt") {
    let (args, result) = row
    if db.find(unwrap_id(result)) == val_id {
      match args[0] {
        @egglog.IntVal(n) => return Some(n)
        _ => ()
      }
    }
  }
  None
}

///|
/// Check if a value is a Closure, and if so return (clos_env, x_name, body).
fn extract_closure(
  db : @egglog.Database,
  val : @egglog.Value,
) -> (@egglog.Value, String, @egglog.Value)? {
  let val_id = db.find(unwrap_id(val))
  for row in db.scan("Closure") {
    let (args, result) = row
    if db.find(unwrap_id(result)) == val_id {
      let clos_env = args[0]
      let x_name = match args[1] {
        @egglog.StrVal(s) => s
        _ => continue
      }
      let body = args[2]
      return Some((clos_env, x_name, body))
    }
  }
  None
}

///|
/// Unwrap a Value to an Id, aborting on non-IdVal variants.
fn unwrap_id(v : @egglog.Value) -> @egglog.Id {
  match v {
    @egglog.IdVal(id) => id
    _ => abort("expected IdVal, got " + v.to_string())
  }
}

///|
/// Reconstruct a ValueEnv from existing ValEnv facts in the database.
///
/// Used when the bridge encounters an env id not tracked in env_map —
/// e.g., closure envs created outside run_eval, or envs whose canonical
/// id changed after rebuild(). Scans the ValEnv table for all bindings
/// associated with the given env id.
fn reconstruct_val_env(
  db : @egglog.Database,
  env_val : @egglog.Value,
) -> ValueEnv {
  let env_id = db.find(unwrap_id(env_val))
  let bindings : Map[String, @egglog.Value] = {}
  for row in db.scan("ValEnv") {
    let (args, result) = row
    if db.find(unwrap_id(args[0])) == env_id {
      match args[1] {
        @egglog.StrVal(name) => bindings[name] = result
        _ => ()
      }
    }
  }
  { id: env_val, bindings }
}

///|
/// Look up or reconstruct the ValueEnv for a given env id.
///
/// First checks env_map by canonical id. If not found, reconstructs
/// from ValEnv facts in the database. This handles two cases:
/// 1. Environments created outside run_eval (externally seeded ValEnv)
/// 2. Environments whose canonical id changed after rebuild()
fn get_or_reconstruct_env(
  db : @egglog.Database,
  env_val : @egglog.Value,
  env_map : Map[@egglog.Id, ValueEnv],
) -> ValueEnv {
  let env_id = db.find(unwrap_id(env_val))
  match env_map.get(env_id) {
    Some(ve) => ve
    None => {
      let ve = reconstruct_val_env(db, env_val)
      env_map[env_id] = ve
      ve
    }
  }
}

///|
/// Create an extended value environment for a closure application or let binding.
fn create_eval_env(
  val_env : ValueEnv,
  db : @egglog.Database,
  name : String,
  value : @egglog.Value,
) -> ValueEnv {
  val_env.extend(db, name, value)
}

///|
/// Composite key for tracking processed triggers.
struct TriggerKey {
  env_id : @egglog.Id
  expr_id : @egglog.Id
} derive(Eq, Hash)

///|
/// MoonBit evaluation bridge: handles operations that cannot be expressed
/// in pure Datalog (integer arithmetic, branch selection, environment extension).
///
/// Returns true if any new facts were produced, false if nothing changed.
fn evaluation_bridge(
  db : @egglog.Database,
  processed : Map[String, Map[TriggerKey, Bool]],
  env_map : Map[@egglog.Id, ValueEnv],
) -> Bool {
  // Check fact count limit
  if db.row_count("Eval") > 10000 {
    return false
  }
  let mut changed = false
  // Process AddReady triggers
  changed = process_add_ready(db, processed, changed)
  // Process MinusReady triggers
  changed = process_minus_ready(db, processed, changed)
  // Process IfReady triggers
  changed = process_if_ready(db, processed, changed)
  // Process AppReady triggers
  changed = process_app_ready(db, processed, env_map, changed)
  // Process LetReady triggers
  changed = process_let_ready(db, processed, env_map, changed)
  changed
}

///|
fn get_processed(
  processed : Map[String, Map[TriggerKey, Bool]],
  table_name : String,
) -> Map[TriggerKey, Bool] {
  match processed.get(table_name) {
    Some(m) => m
    None => {
      let m : Map[TriggerKey, Bool] = {}
      processed[table_name] = m
      m
    }
  }
}

///|
fn process_add_ready(
  db : @egglog.Database,
  processed : Map[String, Map[TriggerKey, Bool]],
  changed : Bool,
) -> Bool {
  let mut changed = changed
  let proc = get_processed(processed, "AddReady")
  for row in db.scan("AddReady") {
    let (args, _) = row
    let env = args[0]
    let expr = args[1]
    let key = {
      env_id: db.find(unwrap_id(env)),
      expr_id: db.find(unwrap_id(expr)),
    }
    if proc.contains(key) {
      continue
    }
    proc[key] = true
    // Find Add(a, b, expr)
    let add_info = find_add(db, expr)
    match add_info {
      None => continue
      Some((a, b)) => {
        let va = db.lookup("Eval", [env, a])
        let vb = db.lookup("Eval", [env, b])
        match (va, vb) {
          (Some(va_val), Some(vb_val)) => {
            let ia = extract_int(db, va_val)
            let ib = extract_int(db, vb_val)
            match (ia, ib) {
              (Some(na), Some(nb)) => {
                let result = db.call("ValInt", [@egglog.IntVal(na + nb)])
                let _ = db.set("Eval", [env, expr], result)
                changed = true
              }
              _ => {
                let _ = db.set(
                  "EvalError",
                  [env, expr],
                  @egglog.StrVal("type error: Add requires integers"),
                )
                changed = true
              }
            }
          }
          _ => ()
        }
      }
    }
  }
  changed
}

///|
fn process_minus_ready(
  db : @egglog.Database,
  processed : Map[String, Map[TriggerKey, Bool]],
  changed : Bool,
) -> Bool {
  let mut changed = changed
  let proc = get_processed(processed, "MinusReady")
  for row in db.scan("MinusReady") {
    let (args, _) = row
    let env = args[0]
    let expr = args[1]
    let key = {
      env_id: db.find(unwrap_id(env)),
      expr_id: db.find(unwrap_id(expr)),
    }
    if proc.contains(key) {
      continue
    }
    proc[key] = true
    let minus_info = find_minus(db, expr)
    match minus_info {
      None => continue
      Some((a, b)) => {
        let va = db.lookup("Eval", [env, a])
        let vb = db.lookup("Eval", [env, b])
        match (va, vb) {
          (Some(va_val), Some(vb_val)) => {
            let ia = extract_int(db, va_val)
            let ib = extract_int(db, vb_val)
            match (ia, ib) {
              (Some(na), Some(nb)) => {
                let result = db.call("ValInt", [@egglog.IntVal(na - nb)])
                let _ = db.set("Eval", [env, expr], result)
                changed = true
              }
              _ => {
                let _ = db.set(
                  "EvalError",
                  [env, expr],
                  @egglog.StrVal("type error: Minus requires integers"),
                )
                changed = true
              }
            }
          }
          _ => ()
        }
      }
    }
  }
  changed
}

///|
fn process_if_ready(
  db : @egglog.Database,
  processed : Map[String, Map[TriggerKey, Bool]],
  changed : Bool,
) -> Bool {
  let mut changed = changed
  let proc = get_processed(processed, "IfReady")
  for row in db.scan("IfReady") {
    let (args, _) = row
    let env = args[0]
    let expr = args[1]
    let key = {
      env_id: db.find(unwrap_id(env)),
      expr_id: db.find(unwrap_id(expr)),
    }
    if proc.contains(key) {
      continue
    }
    proc[key] = true
    let if_info = find_if(db, expr)
    match if_info {
      None => continue
      Some((c, t, el)) => {
        let vc = db.lookup("Eval", [env, c])
        match vc {
          None => continue
          Some(vc_val) => {
            let ic = extract_int(db, vc_val)
            match ic {
              Some(n) => {
                let branch = if n != 0 { t } else { el }
                let _ = db.set("IfBranch", [env, expr], branch)
                let _ = db.set("Demand", [env, branch], @egglog.IntVal(1))
                changed = true
              }
              None => {
                let _ = db.set(
                  "EvalError",
                  [env, expr],
                  @egglog.StrVal("type error: If requires integer condition"),
                )
                changed = true
              }
            }
          }
        }
      }
    }
  }
  changed
}

///|
fn process_app_ready(
  db : @egglog.Database,
  processed : Map[String, Map[TriggerKey, Bool]],
  env_map : Map[@egglog.Id, ValueEnv],
  changed : Bool,
) -> Bool {
  let mut changed = changed
  let proc = get_processed(processed, "AppReady")
  for row in db.scan("AppReady") {
    let (args, _) = row
    let env = args[0]
    let expr = args[1]
    let key = {
      env_id: db.find(unwrap_id(env)),
      expr_id: db.find(unwrap_id(expr)),
    }
    if proc.contains(key) {
      continue
    }
    proc[key] = true
    let app_info = find_app(db, expr)
    match app_info {
      None => continue
      Some((f, arg)) => {
        let closure_val = db.lookup("Eval", [env, f])
        let arg_val = db.lookup("Eval", [env, arg])
        match (closure_val, arg_val) {
          (Some(clos), Some(av)) => {
            let clos_info = extract_closure(db, clos)
            match clos_info {
              Some((clos_env, x_name, body)) => {
                // Find or reconstruct ValueEnv for closure env
                let val_env = get_or_reconstruct_env(db, clos_env, env_map)
                let ext = create_eval_env(val_env, db, x_name, av)
                let ext_id = db.find(unwrap_id(ext.id))
                env_map[ext_id] = ext
                let _ = db.set("AppBodyEnv", [env, expr], ext.id)
                let _ = db.set("AppBody", [env, expr], body)
                let _ = db.set("Demand", [ext.id, body], @egglog.IntVal(1))
                changed = true
              }
              None => {
                let _ = db.set(
                  "EvalError",
                  [env, expr],
                  @egglog.StrVal("type error: App requires function"),
                )
                changed = true
              }
            }
          }
          _ => ()
        }
      }
    }
  }
  changed
}

///|
fn process_let_ready(
  db : @egglog.Database,
  processed : Map[String, Map[TriggerKey, Bool]],
  env_map : Map[@egglog.Id, ValueEnv],
  changed : Bool,
) -> Bool {
  let mut changed = changed
  let proc = get_processed(processed, "LetReady")
  for row in db.scan("LetReady") {
    let (args, _) = row
    let env = args[0]
    let expr = args[1]
    let key = {
      env_id: db.find(unwrap_id(env)),
      expr_id: db.find(unwrap_id(expr)),
    }
    if proc.contains(key) {
      continue
    }
    proc[key] = true
    let let_info = find_let(db, expr)
    match let_info {
      None => continue
      Some((x_name, val_expr, body)) => {
        // Let(x, val, body, e): LetReady fires when Eval(env, val) is available
        let val_result = db.lookup("Eval", [env, val_expr])
        match val_result {
          None => continue
          Some(val_result) => {
            let val_env = get_or_reconstruct_env(db, env, env_map)
            let ext = create_eval_env(val_env, db, x_name, val_result)
            let ext_id = db.find(unwrap_id(ext.id))
            env_map[ext_id] = ext
            let _ = db.set("LetBodyEnv", [env, expr], ext.id)
            let _ = db.set("LetBody", [env, expr], body)
            let _ = db.set("Demand", [ext.id, body], @egglog.IntVal(1))
            changed = true
          }
        }
      }
    }
  }
  changed
}

///|
/// Find Add(a, b, expr) in the Add table.
fn find_add(
  db : @egglog.Database,
  expr : @egglog.Value,
) -> (@egglog.Value, @egglog.Value)? {
  let expr_id = db.find(unwrap_id(expr))
  for row in db.scan("Add") {
    let (args, result) = row
    if db.find(unwrap_id(result)) == expr_id {
      return Some((args[0], args[1]))
    }
  }
  None
}

///|
/// Find Minus(a, b, expr) in the Minus table.
fn find_minus(
  db : @egglog.Database,
  expr : @egglog.Value,
) -> (@egglog.Value, @egglog.Value)? {
  let expr_id = db.find(unwrap_id(expr))
  for row in db.scan("Minus") {
    let (args, result) = row
    if db.find(unwrap_id(result)) == expr_id {
      return Some((args[0], args[1]))
    }
  }
  None
}

///|
/// Find If(c, t, el, expr) in the If table.
fn find_if(
  db : @egglog.Database,
  expr : @egglog.Value,
) -> (@egglog.Value, @egglog.Value, @egglog.Value)? {
  let expr_id = db.find(unwrap_id(expr))
  for row in db.scan("If") {
    let (args, result) = row
    if db.find(unwrap_id(result)) == expr_id {
      return Some((args[0], args[1], args[2]))
    }
  }
  None
}

///|
/// Find App(f, arg, expr) in the App table.
fn find_app(
  db : @egglog.Database,
  expr : @egglog.Value,
) -> (@egglog.Value, @egglog.Value)? {
  let expr_id = db.find(unwrap_id(expr))
  for row in db.scan("App") {
    let (args, result) = row
    if db.find(unwrap_id(result)) == expr_id {
      return Some((args[0], args[1]))
    }
  }
  None
}

///|
/// Find Let(x, val, body, expr) in the Let table.
fn find_let(
  db : @egglog.Database,
  expr : @egglog.Value,
) -> (String, @egglog.Value, @egglog.Value)? {
  let expr_id = db.find(unwrap_id(expr))
  for row in db.scan("Let") {
    let (args, result) = row
    if db.find(unwrap_id(result)) == expr_id {
      let x_name = match args[0] {
        @egglog.StrVal(s) => s
        _ => continue
      }
      return Some((x_name, args[1], args[2]))
    }
  }
  None
}

///|
/// Run demand-driven evaluation to completion.
///
/// Seeds Demand(env, expr), then alternates between Datalog rule saturation
/// and MoonBit bridge execution until no new facts are produced or the
/// iteration limit is reached.
pub fn run_eval(
  db : @egglog.Database,
  env_id : @egglog.Value,
  expr_id : @egglog.Value,
  rules : Array[@egglog.Rule],
  max_iters? : Int = 100,
) -> @egglog.Value? {
  // env_map caches host-side ValueEnv structs for tracked environments.
  // Untracked envs (externally seeded or stale after rebuild) are
  // reconstructed from ValEnv facts by get_or_reconstruct_env().
  let env_map : Map[@egglog.Id, ValueEnv] = {}
  let _ = db.set("Demand", [env_id, expr_id], @egglog.IntVal(1))
  let processed : Map[String, Map[TriggerKey, Bool]] = {}
  for i = 0; i < max_iters; i = i + 1 {
    let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(rules), 10))
    if !evaluation_bridge(db, processed, env_map) {
      break
    }
  }
  db.lookup("Eval", [env_id, expr_id])
}
