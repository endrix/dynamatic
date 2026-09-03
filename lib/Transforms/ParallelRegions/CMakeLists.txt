add_dynamatic_library(DynamaticParallelRegions
  CfDetectParallelRegions.cpp
  HandshakeParallelizeRegions.cpp

  DEPENDS
  DynamaticTransformsPassIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
  MLIRAnalysis
  MLIRArithDialect
  MLIRControlFlowDialect
  MLIRControlFlowInterfaces
  MLIRFuncDialect
  MLIRMemRefDialect
  MLIRSideEffectInterfaces
  DynamaticHandshake
  DynamaticSupport
  DynamaticAnalysis
  DynamaticBufferPlacement
  DynamaticExperimentalSupport
  )
