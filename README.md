# dowdiness/egglog

A relational e-graph engine (egglog) in MoonBit. Combines Datalog-style queries with equality saturation.

## Quick Start

```bash
cd egglog && moon check && moon test
```

## `@incr` Contract

egglog's rule engine is built on top of [`dowdiness/incr`](https://mooncakes.io/docs/dowdiness/incr) v0.4.1. The coupling is load-bearing — every rule fires through incr's reactive runtime, not as a standalone Datalog evaluator.

**Required surfaces** (any change in `@incr` to these is a breaking change for egglog):

| `@incr` API | Use in egglog |
|---|---|
| `Runtime` | One per `Saturate` scope. Owns the dependency graph that drives semi-naive evaluation. Created in `Database::new` (`src/database.mbt`) and rebound on each saturate (`src/function_table.mbt`). |
| `FunctionalRelation[K, V]` | Per-table delta-tracked storage. Each `FunctionTable` holds one (`src/function_table.mbt`). The optional `merge=` closure resolves conflicts during equality saturation. |
| `rt.fixpoint()` | Drives semi-naive evaluation to a fixed point. egglog's `Saturate` schedule wraps this; `Run` executes one iteration. |
| `delta_scan()` | Reads only rows that are new or changed since the last `fixpoint()` drain. The semi-naive seed atom of every rule reads via `delta_scan` (`src/database.mbt`); other atoms read full table state. |

**Fixpoint stabilization invariant.** At the start of each `Saturate` scope, egglog rebinds every table to a fresh `Runtime` and re-seeds all current rows into the new `FunctionalRelation`'s delta buffer (`FunctionTable::rebind_runtime`, `src/function_table.mbt`). This ensures the first fixpoint iteration sees every row as a delta, so rules that depend on pre-existing facts still fire. After `fixpoint()` returns, deltas are drained; rebuilt rows from union-find merges are observed on the next saturate, not the current one (see notes in `src/database.mbt`).

If an upstream change to `@incr` breaks any of these surfaces, egglog will not type-check or will silently lose deltas — both regimes are PR blockers, not soft warnings.

## Dependencies

- [`dowdiness/incr`](https://mooncakes.io/docs/dowdiness/incr) v0.4.1 — see contract above

## Documentation

- [Design](docs/plans/2026-03-08-egglog-design.md) — architecture, data model, rule engine, STLC example
- [Implementation Guide](src/README.mbt.md) — reading order and file tour
