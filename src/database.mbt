///|
/// Mutable relational e-graph state.
///
/// The database is the bridge between relational storage and equality
/// reasoning: function tables hold rows, union-find holds equivalence classes,
/// and `pending` remembers unions that still need to be propagated.
/// The egglog database: function tables + union-find + incr runtime.
///
/// `rt` is the incr `Runtime` used for semi-naive fixpoint evaluation.
/// It is replaced with a fresh instance at the start of each `Saturate`
/// call to scope rules and deltas to that execution.
///
/// `registered_rules` tracks which rule variants have been registered
/// with the current `rt` to prevent duplicates within a Saturate scope.
pub struct Database {
  priv mut rt : @incr.Runtime
  priv uf : UnionFind
  priv tables : Map[String, FunctionTable]
  priv pending : Array[(Id, Id)]
  priv registered_rules : Map[String, Unit]

  fn new() -> Database
}

///|
pub fn Database::new() -> Database {
  {
    rt: @incr.Runtime::new(),
    uf: UnionFind(),
    tables: {},
    pending: [],
    registered_rules: {},
  }
}

///|
fn Database::alloc_id(self : Database) -> Id {
  self.uf.make_set()
}

///|
/// Canonical representative lookup for one e-class id.
pub fn Database::find(self : Database, id : Id) -> Id {
  self.uf.find(id)
}

///|
/// Register a functional table.
///
/// Tables are keyed by canonicalized arguments. Without a merge function, a
/// table behaves like a partial function: each canonical key may have at most
/// one canonical output. Provide `merge` only when conflicting primitive
/// outputs should be combined rather than rejected.
pub fn Database::register(
  self : Database,
  name : String,
  merge? : ((Value, Value) -> Value)? = None,
) -> Unit {
  self.tables[name] = FunctionTable(self.rt, merge)
}

///|
/// Rewrite one value through the current union-find state.
///
/// Primitive values are already canonical, while `IdVal` changes whenever the
/// underlying e-class has been merged.
fn Database::canonicalize_value(self : Database, v : Value) -> Value {
  match v {
    IdVal(id) => IdVal(self.uf.find(id))
    _ => v
  }
}

///|
/// Canonicalize an array of values through the union-find.
fn Database::canon_args(self : Database, args : Array[Value]) -> Array[Value] {
  args.map(fn(v) { self.canonicalize_value(v) })
}

///|
/// Get a table by name, aborting if not found.
fn Database::get_table(self : Database, name : String) -> FunctionTable {
  match self.tables.get(name) {
    Some(t) => t
    None => abort("unknown function: " + name)
  }
}

///|
/// Intern a constructor application.
///
/// `call` is the "make an e-node" operation: it returns an existing output if
/// the canonical input tuple was seen before, otherwise it allocates a fresh
/// e-class for this application.
pub fn Database::call(
  self : Database,
  name : String,
  args : Array[Value],
) -> Value {
  let table = self.get_table(name)
  let canon = self.canon_args(args)
  match table.lookup(canon) {
    Some(v) => self.canonicalize_value(v)
    None => {
      let output = IdVal(self.alloc_id())
      let _ = table.insert(canon, output)
      output
    }
  }
}

///|
/// Set the output for a functional table row.
///
/// Semantics:
/// - same canonical key + same canonical value: no-op
/// - same canonical key + two `IdVal`s: enqueue a union
/// - same canonical key + primitive conflict + merge fn: resolve with merge
/// - same canonical key + primitive conflict + no merge fn: abort
pub fn Database::set(
  self : Database,
  name : String,
  args : Array[Value],
  value : Value,
) -> Value {
  let table = self.get_table(name)
  let canon = self.canon_args(args)
  let canon_val = self.canonicalize_value(value)
  match table.lookup(canon) {
    Some(old) => {
      let canon_old = self.canonicalize_value(old)
      if canon_old == canon_val {
        canon_old
      } else {
        match (canon_old, canon_val) {
          (IdVal(a), IdVal(b)) => {
            self.pending.push((a, b))
            let (stored, _) = table.insert(canon, canon_val)
            stored
          }
          _ =>
            match table.merge {
              Some(_) => {
                let (stored, _) = table.insert(canon, canon_val)
                stored
              }
              None =>
                abort(
                  "conflicting outputs for " +
                  name +
                  " on " +
                  canon.to_string() +
                  ": " +
                  canon_old.to_string() +
                  " vs " +
                  canon_val.to_string(),
                )
            }
        }
      }
    }
    None => {
      let _ = table.insert(canon, canon_val)
      canon_val
    }
  }
}

///|
/// Request that two e-classes become equal on the next rebuild.
///
/// Union is batched so several rule firings can accumulate before tables are
/// re-canonicalized.
pub fn Database::union(self : Database, a : Id, b : Id) -> Unit {
  let ra = self.uf.find(a)
  let rb = self.uf.find(b)
  if ra == rb {
    return
  }
  self.pending.push((ra, rb))
}

///|
/// Rebuild all tables after pending unions.
///
/// Rebuild re-canonicalizes every stored row. If two rows collapse to the same
/// canonical key, the same functional-table semantics used by `set` apply
/// again: `IdVal` outputs unify, merge tables resolve conflicts, and non-merge
/// primitive conflicts abort.
pub fn Database::rebuild(self : Database) -> Unit {
  while self.pending.length() > 0 {
    let batch = self.pending.copy()
    self.pending.clear()
    for pair in batch {
      let (a, b) = pair
      let _ = self.uf.union(a, b)
    }
    self.tables.each(fn(name, table) { self.rebuild_table(name, table) })
  }
}

///|
/// Reinsert a table under current canonical representatives.
///
/// This is where equality collapse can turn previously distinct rows into a
/// conflict on the same canonical key.
///
/// Note: `table.insert` writes to both `rows` and `fr`. After rebuild, `fr`
/// may contain stale entries under old (pre-canonicalization) key strings.
/// These are harmless: `delta_scan` drops them via `raw_keys.get()` returning
/// None. The next `fixpoint()` will re-process all rebuilt rows as new deltas,
/// which is correct but slightly wasteful. This trade-off is acceptable since
/// rebuild only runs when unions cause congruence (relatively rare).
fn Database::rebuild_table(
  self : Database,
  name : String,
  table : FunctionTable,
) -> Unit {
  let old_rows = table.scan()
  table.rows.clear()
  table.raw_keys.clear()
  for pair in old_rows {
    let (key, value) = pair
    let canon_key = self.canon_args(key)
    let canon_val = self.canonicalize_value(value)
    match table.lookup(canon_key) {
      Some(existing) => {
        let canon_existing = self.canonicalize_value(existing)
        if canon_existing != canon_val {
          match (canon_existing, canon_val) {
            (IdVal(a), IdVal(b)) => {
              self.pending.push((a, b))
              let _ = table.insert(canon_key, canon_val)
            }
            _ =>
              match table.merge {
                Some(_) => {
                  let _ = table.insert(canon_key, canon_val)
                }
                None =>
                  abort(
                    "conflicting outputs for " +
                    name +
                    " on " +
                    canon_key.to_string() +
                    ": " +
                    canon_existing.to_string() +
                    " vs " +
                    canon_val.to_string(),
                  )
              }
          }
        }
      }
      None => {
        let _ = table.insert(canon_key, canon_val)
      }
    }
  }
}

///|
/// Register one semi-naive variant of an egglog Rule with the incr Runtime.
///
/// `seed_index` selects which Fact atom reads `delta_scan()` (new rows
/// only); all other atoms read `scan()` (all rows). One variant per
/// Fact atom is registered by `register_schedule_rules` so that deltas
/// from any input relation can seed the join.
///
/// Input/output table dependencies are collected by recursively walking
/// all Term trees in query atoms and actions, including nested `Call`
/// nodes inside `Equal` atoms and `Union`/`LetAction` actions.
fn Database::register_incr_rule(
  self : Database,
  rule : Rule,
  seed_index : Int,
) -> Unit {
  // Guard: abort on duplicate rule names within the same Saturate scope.
  // Semi-naive variants use name#index to distinguish.
  let variant_name = rule.name + "#" + seed_index.to_string()
  if self.registered_rules.contains(variant_name) {
    abort("duplicate rule name: " + variant_name)
  }
  self.registered_rules[variant_name] = ()
  // Collect input table IDs by walking all terms in query atoms.
  let input_names : Map[String, Unit] = {}
  for atom in rule.query {
    match atom {
      Fact(name, terms) => {
        input_names[name] = ()
        for t in terms {
          collect_table_names(t, input_names)
        }
      }
      Equal(lhs, rhs) => {
        collect_table_names(lhs, input_names)
        collect_table_names(rhs, input_names)
      }
    }
  }
  let input_ids : Array[@incr.CellId] = []
  input_names.each(fn(name, _) {
    match self.tables.get(name) {
      Some(t) => input_ids.push(t.id())
      None => ()
    }
  })
  // Collect output table IDs by walking all terms in actions.
  let output_names : Map[String, Unit] = {}
  for action in rule.actions {
    match action {
      Set(name, args, val) => {
        output_names[name] = ()
        for t in args {
          collect_table_names(t, output_names)
        }
        collect_table_names(val, output_names)
      }
      Union(lhs, rhs) => {
        collect_table_names(lhs, output_names)
        collect_table_names(rhs, output_names)
      }
      LetAction(_, term) => collect_table_names(term, output_names)
    }
  }
  let output_ids : Array[@incr.CellId] = []
  output_names.each(fn(name, _) {
    match self.tables.get(name) {
      Some(t) => output_ids.push(t.id())
      None => ()
    }
  })
  let _ = self.rt.new_rule(
    input_ids,
    output_ids,
    fn() {
      let substs = execute_query_with(self, rule.query, fn(table, i) {
        if i == seed_index {
          table.delta_scan()
        } else {
          table.scan()
        }
      })
      for s in substs {
        let _ = execute_actions(self, s, rule.actions)
      }
    },
    label=variant_name,
  )
}

///|
/// Collect all table names referenced by Call nodes in a term tree.
fn collect_table_names(term : Term, names : Map[String, Unit]) -> Unit {
  match term {
    Var(_) | Lit(_) => ()
    Call(name, args) => {
      names[name] = ()
      for t in args {
        collect_table_names(t, names)
      }
    }
  }
}

///|
/// Count the number of Fact atoms in a query (determines how many
/// semi-naive variants to register per rule).
fn count_facts(query : Array[Atom]) -> Int {
  let mut count = 0
  for atom in query {
    match atom {
      Fact(_, _) => count = count + 1
      _ => ()
    }
  }
  count
}

///|
/// Register all rules from a schedule tree, one variant per Fact atom
/// for semi-naive evaluation.
///
/// Only `Run` leaves are supported inside `Saturate`. Nested `Repeat`
/// and `Seq` are rejected — use them outside `Saturate` instead.
fn Database::register_schedule_rules(
  self : Database,
  schedule : Schedule,
) -> Unit {
  match schedule {
    Run(rules) =>
      for rule in rules {
        let n_facts = count_facts(rule.query)
        // Register one variant per fact atom position so that deltas
        // from any input relation seed the join.
        for seed = 0; seed < n_facts; seed = seed + 1 {
          self.register_incr_rule(rule, seed)
        }
      }
    Saturate(inner, _) => self.register_schedule_rules(inner)
    Repeat(_, _) =>
      abort(
        "register_schedule_rules: Repeat inside Saturate is not supported; use Repeat outside Saturate",
      )
    Seq(schedules) =>
      for s in schedules {
        self.register_schedule_rules(s)
      }
  }
}

///|
/// Returns every row as `(key_tuple, value)`.
///
/// The internal store serializes keys as strings for O(log n) lookup; `scan`
/// recovers the original `Array[Value]` tuples via a parallel `raw_keys` map.
/// Reads from the authoritative store, not the delta buffer — returns all
/// materialized rows regardless of fixpoint state.
///
/// Keys and values are returned as stored; after `union` + `rebuild`, callers
/// should canonicalize `IdVal`s via `find()` before using them as lookup keys.
///
/// Aborts if the table has not been registered via `register()`.
pub fn Database::scan(
  self : Database,
  name : String,
) -> Array[(Array[Value], Value)] {
  let table = self.get_table(name)
  table.scan()
}

///|
/// Number of distinct canonical key tuples in a table.
///
/// Because egglog tables are functional (at most one output per canonical key),
/// this equals the number of distinct function applications materialized so far.
///
/// Aborts if the table has not been registered via `register()`.
pub fn Database::row_count(self : Database, name : String) -> Int {
  let table = self.get_table(name)
  table.row_count()
}

///|
/// Look up a row after canonicalizing the arguments first.
///
/// This gives callers the logical answer for the current e-graph state rather
/// than the answer for some stale pre-rebuild representative.
pub fn Database::lookup(
  self : Database,
  name : String,
  args : Array[Value],
) -> Value? {
  let table = match self.tables.get(name) {
    Some(t) => t
    None => return None
  }
  let canon = self.canon_args(args)
  match table.lookup(canon) {
    Some(v) => Some(self.canonicalize_value(v))
    None => None
  }
}
