// REQUIRES: nusmv
// RUN: rm -rf %t && mkdir %t
// RUN: cd %t && G="python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/smv-unit-generator.py" && \
// RUN:   $G -n extui_1_4 -o extui_1_4.smv -t extui -p latency=0 input_bitwidth=1 output_bitwidth=4 && \
// RUN:   $G -n extsi_1_4 -o extsi_1_4.smv -t extsi -p latency=0 input_bitwidth=1 output_bitwidth=4 && \
// RUN:   $G -n extsi_4_8 -o extsi_4_8.smv -t extsi -p latency=0 input_bitwidth=4 output_bitwidth=8 && \
// RUN:   $G -n trunci_4_1 -o trunci_4_1.smv -t trunci -p latency=0 input_bitwidth=4 output_bitwidth=1 && \
// RUN:   $G -n trunci_4_2 -o trunci_4_2.smv -t trunci -p latency=0 input_bitwidth=4 output_bitwidth=2 && \
// RUN:   cat extui_1_4.smv extsi_1_4.smv extsi_4_8.smv trunci_4_1.smv trunci_4_2.smv %S/Inputs/casts-main.smv > casts.smv && \
// RUN:   NuSMV casts.smv | FileCheck %s

// The casts' values, every input: a one-bit extui is 0 or 1, a one-bit extsi
// 0 or all ones, a 4-to-8 extsi keeps the sign, a truncation the low bits.
// (Before the fix the one-bit extui was a type error, the extsi zero-filled
// and the truncations sliced a bit too many: NuSMV refused the model.)

// CHECK: invariant {{.*}} is true
// CHECK: invariant {{.*}} is true
// CHECK: invariant {{.*}} is true
// CHECK: invariant {{.*}} is true
// CHECK: invariant {{.*}} is true
// CHECK-NOT: is false
