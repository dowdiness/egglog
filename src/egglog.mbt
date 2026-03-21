// ════════════════════════════════════════════════════════════════════
// Egglog: Relational E-Graph Engine
// ════════════════════════════════════════════════════════════════════
//
// A relational e-graph engine that unifies Datalog and equality
// saturation. Functions are stored as database tables, e-matching
// uses relational joins, and rules are Datalog queries with actions.
//
// Semi-naive evaluation is powered by `dowdiness/incr`'s
// `FunctionalRelation[K, V]`: each table tracks which rows are new
// (delta) vs already processed (current). During `Saturate`, rules
// are registered with `incr`'s `Runtime` and driven by `fixpoint()`,
// which drains deltas, applies rules, and promotes staged results
// until convergence. One rule variant is registered per Fact atom
// so deltas from any input relation seed the join.
//
// References:
//   - egglog paper: https://arxiv.org/abs/2304.04332
//   - egg paper: https://arxiv.org/abs/2004.03082
//
// Package tour:
//   - `types.mbt`           runtime value and sort types
//   - `union_find.mbt`      e-class equivalence (path compression)
//   - `function_table.mbt`  dual storage: `rows` (lookup) + `fr` (deltas)
//   - `database.mbt`        tables + union-find + incr Runtime + rebuild
//   - `join.mbt`            query execution (full scan and semi-naive)
//   - `rule.mbt`            rule language and action semantics
//   - `schedule.mbt`        Run (one-shot) and Saturate (fixpoint)
//   - `extract.mbt`         cheapest tree-shaped representative
// ════════════════════════════════════════════════════════════════════
