set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name Frontend)
add_public_tablegen_target(DynamaticFrontendPassIncGen)
add_dependencies(dynamatic-headers DynamaticFrontendPassIncGen)
