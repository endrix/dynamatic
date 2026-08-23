set(LLVM_OPTIONAL_SOURCES
  MemDepAnalysis.cpp
  ArrayPartition.cpp
  GuardLoadStore.cpp
)


# MemDepAnalysis and ArrayPartition are built on top of Polly's SCoP analysis;
# they are only built when Polly is part of the LLVM installation.
if (DYNAMATIC_ENABLE_POLLY)
  # Link to required LLVM and Polly libraries
  add_llvm_pass_plugin(MemDepAnalysis
    MemDepAnalysis.cpp
    DEPENDS
    LLVMCore
    LLVMSupport
    LLVMAnalysis
    Polly

    MLIRIR
    MLIRSupport
  )

  # Link to required LLVM and Polly libraries
  add_llvm_pass_plugin(ArrayPartition
    ArrayPartition.cpp
    DEPENDS
    LLVMCore
    LLVMSupport
    LLVMAnalysis
    Polly

    MLIRIR
    MLIRSupport
  )
endif()

# Link to required LLVM libraries
add_llvm_pass_plugin(GuardLoadStore
  GuardLoadStore.cpp
  DEPENDS
  LLVMCore
  LLVMSupport
  LLVMAnalysis

  MLIRIR
  MLIRSupport
)
