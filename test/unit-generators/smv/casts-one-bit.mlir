// RUN: rm -rf %t && mkdir %t
// RUN: cd %t && G="python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/smv-unit-generator.py" && \
// RUN:   $G -n extui_1_4 -o extui_1_4.smv -t extui -p latency=0 input_bitwidth=1 output_bitwidth=4 && \
// RUN:   $G -n extsi_1_4 -o extsi_1_4.smv -t extsi -p latency=0 input_bitwidth=1 output_bitwidth=4 && \
// RUN:   $G -n extsi_4_8 -o extsi_4_8.smv -t extsi -p latency=0 input_bitwidth=4 output_bitwidth=8 && \
// RUN:   $G -n trunci_4_1 -o trunci_4_1.smv -t trunci -p latency=0 input_bitwidth=4 output_bitwidth=1 && \
// RUN:   $G -n trunci_4_2 -o trunci_4_2.smv -t trunci -p latency=0 input_bitwidth=4 output_bitwidth=2 && \
// RUN:   cat extui_1_4.smv extsi_1_4.smv extsi_4_8.smv trunci_4_1.smv trunci_4_2.smv | FileCheck %s

// The casts' models at and around one bit, where a channel is a boolean and
// every other width an unsigned word. A one-bit extui makes the boolean a
// word before extending it (extend of a boolean is a type error); extsi
// extends the SIGNED word, so TRUE becomes all ones and -1 stays -1 (extend of
// an unsigned word fills with zeros); trunci keeps bits N-1..0 (it sliced
// N+1), and a one-bit result is a boolean. casts-one-bit-values.mlir checks
// the values with NuSMV.

// CHECK: DEFINE outs := extend(word1(ins), 3);
// CHECK: DEFINE outs := unsigned(extend(signed(word1(ins)), 3));
// CHECK: DEFINE outs := unsigned(extend(signed(ins), 4));
// CHECK: DEFINE outs := bool(ins[0:0]);
// CHECK: DEFINE outs := ins[1:0];
