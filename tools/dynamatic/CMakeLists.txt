set(LLVM_LINK_COMPONENTS
  Support
)

# The Polly-based pass plugins are only available when Dynamatic is built
# against an LLVM installation that includes Polly.
set(DYNAMATIC_POLLY_PLUGIN_DEPS "")
if (DYNAMATIC_ENABLE_POLLY)
  list(APPEND DYNAMATIC_POLLY_PLUGIN_DEPS MemDepAnalysis ArrayPartition)
endif()

add_llvm_tool(dynamatic
  dynamatic.cpp
  DEPENDS
  # Required by compile.sh
  dynamatic-opt opt clang ${DYNAMATIC_POLLY_PLUGIN_DEPS} translate-llvm-to-std
  export-dot export-cfg exp-frequency-profiler source-rewriter DynPragmasPlugin
  # Required by simulate.sh
  hls-verifier
  # Required by write-hdl.sh
  export-rtl rtl-constant-generator-verilog rtl-cmpi-generator rtl-cmpf-generator rtl-text-generator
)

llvm_update_compile_flags(dynamatic)
target_link_libraries(dynamatic
  PRIVATE
  DynamaticSupport
  DynamaticTransforms

  DynamaticHandshake

  MLIRIR
  MLIRParser
  MLIRSupport
  MLIRPass
  MLIRLLVMDialect
  MLIRArithDialect
  MLIRMemRefDialect
  readline
  )
