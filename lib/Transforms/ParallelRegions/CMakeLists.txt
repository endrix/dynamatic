add_dynamatic_library(DynamaticParallelRegions
  HandshakeParallelizeRegions.cpp

  DEPENDS
  DynamaticTransformsPassIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
  DynamaticHandshake
  DynamaticSupport
  DynamaticAnalysis
  DynamaticBufferPlacement
  DynamaticExperimentalSupport
  )
