// RUN: dynamatic-opt --handshake-optimize-bitwidths --remove-operation-names %s --split-input-file | FileCheck %s

// A value carried round a loop through if-else diamonds that forward it
// unchanged is in a forwarding cycle, and takes the width of what enters
// the cycle: the loop's init, eight bits wide. Every diamond is two ways
// back from its merge to its branch, so a search that walks every path back
// takes 2^k walks for k diamonds; the cycles are found from the graph's
// strongly connected components instead, once per merge-like operation.

// CHECK-LABEL:   handshake.func @cycleThroughTwoDiamonds(
// CHECK-SAME:                                            %[[VAL_0:.*]]: !handshake.channel<i8>, %[[VAL_1:.*]]: !handshake.channel<i1>, %[[VAL_2:.*]]: !handshake.channel<i1>,
// CHECK:           %[[VAL_4:.*]] = mux %[[VAL_1]] {{\[}}%[[VAL_0]], %[[VAL_5:.*]]] : <i1>, [<i8>, <i8>] to <i8>
// CHECK:           %[[VAL_6:.*]], %[[VAL_7:.*]] = cond_br %[[VAL_2]], %[[VAL_4]] : <i1>, <i8>
// CHECK:           %[[VAL_8:.*]] = merge %[[VAL_6]], %[[VAL_7]] : <i8>
// CHECK:           %[[VAL_9:.*]], %[[VAL_10:.*]] = cond_br %[[VAL_2]], %[[VAL_8]] : <i1>, <i8>
// CHECK:           %[[VAL_11:.*]] = merge %[[VAL_9]], %[[VAL_10]] : <i8>
// CHECK:           %[[VAL_5]], %[[VAL_12:.*]] = cond_br %[[VAL_2]], %[[VAL_11]] : <i1>, <i8>
// CHECK:           %[[VAL_13:.*]] = extsi %[[VAL_12]] : <i8> to <i32>
// CHECK:           end %[[VAL_13]] : <i32>
// CHECK:         }
handshake.func @cycleThroughTwoDiamonds(%arg0: !handshake.channel<i8>, %index: !handshake.channel<i1>, %cond: !handshake.channel<i1>, %start: !handshake.control<>) -> !handshake.channel<i32> {
  %ext = extsi %arg0 : <i8> to <i32>
  %head = mux %index [%ext, %back] : <i1>, [<i32>, <i32>] to <i32>
  %t0, %f0 = cond_br %cond, %head : <i1>, <i32>
  %m0 = merge %t0, %f0 : <i32>
  %t1, %f1 = cond_br %cond, %m0 : <i1>, <i32>
  %m1 = merge %t1, %f1 : <i32>
  %back, %exit = cond_br %cond, %m1 : <i1>, <i32>
  end %exit : <i32>
}

// -----

// The same loop through 64 diamonds: 2^64 walks.

// CHECK-LABEL:   handshake.func @cycleThroughSixtyFourDiamonds(
// CHECK:           mux %{{.*}} {{\[}}%{{.*}}, %{{.*}}] : <i1>, [<i8>, <i8>] to <i8>
// CHECK-COUNT-64:  merge %{{.*}}, %{{.*}} : <i8>
// CHECK:           cond_br %{{.*}}, %{{.*}} : <i1>, <i8>
// CHECK-NEXT:      %[[EXT:.*]] = extsi %{{.*}} : <i8> to <i32>
// CHECK-NEXT:      end %[[EXT]] : <i32>
handshake.func @cycleThroughSixtyFourDiamonds(%arg0: !handshake.channel<i8>, %index: !handshake.channel<i1>, %cond: !handshake.channel<i1>, %start: !handshake.control<>) -> !handshake.channel<i32> {
  %ext = extsi %arg0 : <i8> to <i32>
  %head = mux %index [%ext, %back] : <i1>, [<i32>, <i32>] to <i32>
  %t0, %f0 = cond_br %cond, %head : <i1>, <i32>
  %m0 = merge %t0, %f0 : <i32>
  %t1, %f1 = cond_br %cond, %m0 : <i1>, <i32>
  %m1 = merge %t1, %f1 : <i32>
  %t2, %f2 = cond_br %cond, %m1 : <i1>, <i32>
  %m2 = merge %t2, %f2 : <i32>
  %t3, %f3 = cond_br %cond, %m2 : <i1>, <i32>
  %m3 = merge %t3, %f3 : <i32>
  %t4, %f4 = cond_br %cond, %m3 : <i1>, <i32>
  %m4 = merge %t4, %f4 : <i32>
  %t5, %f5 = cond_br %cond, %m4 : <i1>, <i32>
  %m5 = merge %t5, %f5 : <i32>
  %t6, %f6 = cond_br %cond, %m5 : <i1>, <i32>
  %m6 = merge %t6, %f6 : <i32>
  %t7, %f7 = cond_br %cond, %m6 : <i1>, <i32>
  %m7 = merge %t7, %f7 : <i32>
  %t8, %f8 = cond_br %cond, %m7 : <i1>, <i32>
  %m8 = merge %t8, %f8 : <i32>
  %t9, %f9 = cond_br %cond, %m8 : <i1>, <i32>
  %m9 = merge %t9, %f9 : <i32>
  %t10, %f10 = cond_br %cond, %m9 : <i1>, <i32>
  %m10 = merge %t10, %f10 : <i32>
  %t11, %f11 = cond_br %cond, %m10 : <i1>, <i32>
  %m11 = merge %t11, %f11 : <i32>
  %t12, %f12 = cond_br %cond, %m11 : <i1>, <i32>
  %m12 = merge %t12, %f12 : <i32>
  %t13, %f13 = cond_br %cond, %m12 : <i1>, <i32>
  %m13 = merge %t13, %f13 : <i32>
  %t14, %f14 = cond_br %cond, %m13 : <i1>, <i32>
  %m14 = merge %t14, %f14 : <i32>
  %t15, %f15 = cond_br %cond, %m14 : <i1>, <i32>
  %m15 = merge %t15, %f15 : <i32>
  %t16, %f16 = cond_br %cond, %m15 : <i1>, <i32>
  %m16 = merge %t16, %f16 : <i32>
  %t17, %f17 = cond_br %cond, %m16 : <i1>, <i32>
  %m17 = merge %t17, %f17 : <i32>
  %t18, %f18 = cond_br %cond, %m17 : <i1>, <i32>
  %m18 = merge %t18, %f18 : <i32>
  %t19, %f19 = cond_br %cond, %m18 : <i1>, <i32>
  %m19 = merge %t19, %f19 : <i32>
  %t20, %f20 = cond_br %cond, %m19 : <i1>, <i32>
  %m20 = merge %t20, %f20 : <i32>
  %t21, %f21 = cond_br %cond, %m20 : <i1>, <i32>
  %m21 = merge %t21, %f21 : <i32>
  %t22, %f22 = cond_br %cond, %m21 : <i1>, <i32>
  %m22 = merge %t22, %f22 : <i32>
  %t23, %f23 = cond_br %cond, %m22 : <i1>, <i32>
  %m23 = merge %t23, %f23 : <i32>
  %t24, %f24 = cond_br %cond, %m23 : <i1>, <i32>
  %m24 = merge %t24, %f24 : <i32>
  %t25, %f25 = cond_br %cond, %m24 : <i1>, <i32>
  %m25 = merge %t25, %f25 : <i32>
  %t26, %f26 = cond_br %cond, %m25 : <i1>, <i32>
  %m26 = merge %t26, %f26 : <i32>
  %t27, %f27 = cond_br %cond, %m26 : <i1>, <i32>
  %m27 = merge %t27, %f27 : <i32>
  %t28, %f28 = cond_br %cond, %m27 : <i1>, <i32>
  %m28 = merge %t28, %f28 : <i32>
  %t29, %f29 = cond_br %cond, %m28 : <i1>, <i32>
  %m29 = merge %t29, %f29 : <i32>
  %t30, %f30 = cond_br %cond, %m29 : <i1>, <i32>
  %m30 = merge %t30, %f30 : <i32>
  %t31, %f31 = cond_br %cond, %m30 : <i1>, <i32>
  %m31 = merge %t31, %f31 : <i32>
  %t32, %f32 = cond_br %cond, %m31 : <i1>, <i32>
  %m32 = merge %t32, %f32 : <i32>
  %t33, %f33 = cond_br %cond, %m32 : <i1>, <i32>
  %m33 = merge %t33, %f33 : <i32>
  %t34, %f34 = cond_br %cond, %m33 : <i1>, <i32>
  %m34 = merge %t34, %f34 : <i32>
  %t35, %f35 = cond_br %cond, %m34 : <i1>, <i32>
  %m35 = merge %t35, %f35 : <i32>
  %t36, %f36 = cond_br %cond, %m35 : <i1>, <i32>
  %m36 = merge %t36, %f36 : <i32>
  %t37, %f37 = cond_br %cond, %m36 : <i1>, <i32>
  %m37 = merge %t37, %f37 : <i32>
  %t38, %f38 = cond_br %cond, %m37 : <i1>, <i32>
  %m38 = merge %t38, %f38 : <i32>
  %t39, %f39 = cond_br %cond, %m38 : <i1>, <i32>
  %m39 = merge %t39, %f39 : <i32>
  %t40, %f40 = cond_br %cond, %m39 : <i1>, <i32>
  %m40 = merge %t40, %f40 : <i32>
  %t41, %f41 = cond_br %cond, %m40 : <i1>, <i32>
  %m41 = merge %t41, %f41 : <i32>
  %t42, %f42 = cond_br %cond, %m41 : <i1>, <i32>
  %m42 = merge %t42, %f42 : <i32>
  %t43, %f43 = cond_br %cond, %m42 : <i1>, <i32>
  %m43 = merge %t43, %f43 : <i32>
  %t44, %f44 = cond_br %cond, %m43 : <i1>, <i32>
  %m44 = merge %t44, %f44 : <i32>
  %t45, %f45 = cond_br %cond, %m44 : <i1>, <i32>
  %m45 = merge %t45, %f45 : <i32>
  %t46, %f46 = cond_br %cond, %m45 : <i1>, <i32>
  %m46 = merge %t46, %f46 : <i32>
  %t47, %f47 = cond_br %cond, %m46 : <i1>, <i32>
  %m47 = merge %t47, %f47 : <i32>
  %t48, %f48 = cond_br %cond, %m47 : <i1>, <i32>
  %m48 = merge %t48, %f48 : <i32>
  %t49, %f49 = cond_br %cond, %m48 : <i1>, <i32>
  %m49 = merge %t49, %f49 : <i32>
  %t50, %f50 = cond_br %cond, %m49 : <i1>, <i32>
  %m50 = merge %t50, %f50 : <i32>
  %t51, %f51 = cond_br %cond, %m50 : <i1>, <i32>
  %m51 = merge %t51, %f51 : <i32>
  %t52, %f52 = cond_br %cond, %m51 : <i1>, <i32>
  %m52 = merge %t52, %f52 : <i32>
  %t53, %f53 = cond_br %cond, %m52 : <i1>, <i32>
  %m53 = merge %t53, %f53 : <i32>
  %t54, %f54 = cond_br %cond, %m53 : <i1>, <i32>
  %m54 = merge %t54, %f54 : <i32>
  %t55, %f55 = cond_br %cond, %m54 : <i1>, <i32>
  %m55 = merge %t55, %f55 : <i32>
  %t56, %f56 = cond_br %cond, %m55 : <i1>, <i32>
  %m56 = merge %t56, %f56 : <i32>
  %t57, %f57 = cond_br %cond, %m56 : <i1>, <i32>
  %m57 = merge %t57, %f57 : <i32>
  %t58, %f58 = cond_br %cond, %m57 : <i1>, <i32>
  %m58 = merge %t58, %f58 : <i32>
  %t59, %f59 = cond_br %cond, %m58 : <i1>, <i32>
  %m59 = merge %t59, %f59 : <i32>
  %t60, %f60 = cond_br %cond, %m59 : <i1>, <i32>
  %m60 = merge %t60, %f60 : <i32>
  %t61, %f61 = cond_br %cond, %m60 : <i1>, <i32>
  %m61 = merge %t61, %f61 : <i32>
  %t62, %f62 = cond_br %cond, %m61 : <i1>, <i32>
  %m62 = merge %t62, %f62 : <i32>
  %t63, %f63 = cond_br %cond, %m62 : <i1>, <i32>
  %m63 = merge %t63, %f63 : <i32>
  %back, %exit = cond_br %cond, %m63 : <i1>, <i32>
  end %exit : <i32>
}

// -----

// A 32-bit argument enters the loop inside the cycle, through the mux. An
// argument is not in the cycle -- it has no defining operation to walk -- but
// a value merged into it, so the loop keeps the argument's 32 bits; only the
// merge before the loop narrows. Reading an argument as in the cycle would
// drop %w from the merged values and narrow the loop to 9 bits.

// CHECK-LABEL:   handshake.func @wideArgumentEntersTheCycle(
// CHECK:           %[[PRE:.*]] = merge %{{.*}}, %{{.*}} : <i9>
// CHECK:           %[[EXT:.*]] = extsi %[[PRE]] : <i9> to <i32>
// CHECK:           %[[HEAD:.*]], %{{.*}} = control_merge {{\[}}%[[EXT]], %[[BACK:.*]]]  : {{\[}}<i32>, <i32>] to <i32>, <i1>
// CHECK:           %[[T:.*]], %{{.*}} = cond_br %{{.*}}, %[[HEAD]] : <i1>, <i32>
// CHECK:           %[[MUX:.*]] = mux %{{.*}} {{\[}}%[[T]], %{{.*}}] : <i1>, {{\[}}<i32>, <i32>] to <i32>
// CHECK:           %[[BACK]], %[[EXIT:.*]] = cond_br %{{.*}}, %[[MUX]] : <i1>, <i32>
// CHECK:           end %[[EXIT]] : <i32>
handshake.func @wideArgumentEntersTheCycle(%a8: !handshake.channel<i8>, %b8: !handshake.channel<i8>, %w: !handshake.channel<i32>, %index: !handshake.channel<i1>, %cond: !handshake.channel<i1>, %start: !handshake.control<>) -> !handshake.channel<i32> {
  %e8 = extsi %a8 : <i8> to <i32>
  %f8 = extui %b8 : <i8> to <i32>
  %pre = merge %e8, %f8 : <i32>
  %head, %hidx = control_merge [%pre, %back] : [<i32>, <i32>] to <i32>, <i1>
  %t0, %f0 = cond_br %cond, %head : <i1>, <i32>
  %m0 = mux %index [%t0, %w] : <i1>, [<i32>, <i32>] to <i32>
  %back, %exit = cond_br %cond, %m0 : <i1>, <i32>
  end %exit : <i32>
}
