///|
/// Core runtime values shared by the whole package.
///
/// `IdVal` points at an e-class managed by union-find. Primitive cases are the
/// leaves that can appear in tables without introducing a new equivalence class.
/// A value in the egglog database. Either an e-class Id or a primitive.
pub(all) enum Value {
  IdVal(Id)
  IntVal(Int)
  StrVal(String)
} derive(Eq, Hash, Compare, Debug)

///|
pub impl Show for Value with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Column metadata for future schema-aware table definitions.
///
/// The current prototype does not enforce sorts yet, but keeping the concept in
/// the surface language makes later validation and optimization easier to add.
/// Sort (type) of a column in a function table.
pub(all) enum Sort {
  EqSort(String)
  PrimitiveSort(String)
} derive(Eq, Hash, Debug)

///|
pub extend Value with Eq::{not_equal, equal}

///|
pub extend Value with Hash::{hash, hash_combine}

///|
pub extend Value with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend Value with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Value with Show::{to_string, output}

///|
pub extend Sort with Eq::{not_equal, equal}

///|
pub extend Sort with Hash::{hash, hash_combine}

///|
pub extend Sort with @moonbitlang/core/debug.Debug::{to_repr}
