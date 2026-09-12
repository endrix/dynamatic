// A call to a function that is not a placeholder module -- its arguments are
// not named input_*, output_* or parameter_* -- is an error at the call, not
// an assertion, whether the callee is lowered after the call (first module:
// the callee is still a func.func when the call converts) or before it
// (second module: the callee is a handshake.func already, and its argument
// names carry no role).
//
// RUN: not dynamatic-opt --lower-cf-to-handshake --split-input-file %s 2>&1 | FileCheck %s

// CHECK: error: call to 'plain': argument 0 has no 'handshake.arg_name' attribute; only a function whose arguments are named input_*, output_* or parameter_* can be called as an instance
func.func @caller(%arg0: i32) -> i32 {
  %0 = call @plain(%arg0) : (i32) -> i32
  return %0 : i32
}

func.func @plain(%arg0: i32) -> i32 {
  return %arg0 : i32
}

// -----

// CHECK: error: call to 'plain_first': lowered before the call and not a placeholder module; only a function whose arguments are named input_*, output_* or parameter_* can be called as an instance
func.func @plain_first(%arg0: i32) -> i32 {
  return %arg0 : i32
}

func.func @caller(%arg0: i32) -> i32 {
  %0 = call @plain_first(%arg0) : (i32) -> i32
  return %0 : i32
}
