// A call to a function that is not a placeholder module -- its arguments are
// not named input_*, output_* or parameter_* -- is an error at the call, not
// an assertion. The callee comes after the caller so that the call is
// converted while the callee is still a func.func.
//
// RUN: not dynamatic-opt --lower-cf-to-handshake %s 2>&1 | FileCheck %s

// CHECK: error: call to 'plain': argument 0 has no 'handshake.arg_name' attribute; only a function whose arguments are named input_*, output_* or parameter_* can be called as an instance
func.func @caller(%arg0: i32) -> i32 {
  %0 = call @plain(%arg0) : (i32) -> i32
  return %0 : i32
}

func.func @plain(%arg0: i32) -> i32 {
  return %arg0 : i32
}
