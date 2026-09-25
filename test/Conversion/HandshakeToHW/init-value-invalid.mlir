// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file --verify-diagnostics

// An INIT_VALUE the channel's width cannot hold is refused, not cut to it.

handshake.func @too_wide(%a: !handshake.channel<i8>) -> !handshake.channel<i8>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  // expected-error @below {{INIT_VALUE 256 does not fit the channel's 8 bits}}
  // expected-error @below {{failed to legalize operation 'handshake.init'}}
  %i = init %a {hw.parameters = {INIT_VALUE = 256 : i64}} : <i8>
  end %i : <i8>
}

// -----

handshake.func @too_negative(%a: !handshake.channel<i8>) -> !handshake.channel<i8>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  // expected-error @below {{INIT_VALUE -129 does not fit the channel's 8 bits}}
  // expected-error @below {{failed to legalize operation 'handshake.init'}}
  %i = init %a {hw.parameters = {INIT_VALUE = -129 : i64}} : <i8>
  end %i : <i8>
}
