///|
/// Control language for rule execution.
///
/// `Run` is a single pass, `Saturate` keeps repeating until the database stops
/// changing or a limit is hit, and `Repeat`/`Seq` provide simple composition.
/// A schedule controls how rules are applied.
pub(all) enum Schedule {
  Run(Array[Rule])
  Saturate(Schedule, Int)
  Repeat(Int, Schedule)
  Seq(Array[Schedule])
} derive(Show, Debug)

///|
/// Coarse status returned by schedule execution.
pub(all) enum StopReason {
  Saturated
  IterLimit
} derive(Eq, Show, Debug)

///|
/// Fire one rule against the current database snapshot.
///
/// Rebuild is intentionally delayed so several matches can enqueue unions
/// before the tables are canonicalized again.
fn Database::apply_rule(self : Database, rule : Rule) -> Int {
  let substs = execute_query(self, rule.query)
  let mut total_unions = 0
  for s in substs {
    total_unions = total_unions + execute_actions(self, s, rule.actions)
  }
  total_unions
}

///|
/// Execute a schedule tree.
///
/// The important mental model is: `Run` performs one wave of rule firing,
/// `rebuild` makes equalities visible, and `Saturate` watches pending unions
/// and row counts to see whether another wave is needed.
pub fn Database::run_schedule(
  self : Database,
  schedule : Schedule,
) -> StopReason {
  match schedule {
    Run(rules) => {
      for rule in rules {
        let _ = self.apply_rule(rule)
      }
      self.rebuild()
      Saturated
    }
    Saturate(inner, max_iters) => {
      // Register rules from the inner schedule as incr rules so fixpoint()
      // can drive semi-naive evaluation.
      self.register_schedule_rules(inner)
      // Process any pending unions before fixpoint.
      if self.pending.length() > 0 {
        self.rebuild()
      }
      for i = 0; i < max_iters; i = i + 1 {
        // Run one fixpoint pass (drains deltas, applies rules, converges).
        self.rt.fixpoint()
        // Process any unions generated during fixpoint (congruence).
        if self.pending.length() > 0 {
          self.rebuild()
        } else {
          return Saturated
        }
      }
      IterLimit
    }
    Repeat(n, inner) => {
      let mut last_reason = Saturated
      for i = 0; i < n; i = i + 1 {
        last_reason = self.run_schedule(inner)
      }
      last_reason
    }
    Seq(schedules) => {
      let mut last_reason = Saturated
      for s in schedules {
        last_reason = self.run_schedule(s)
      }
      last_reason
    }
  }
}
