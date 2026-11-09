add_dynamatic_library(DynamaticExperimentalTestTransforms
  TestFtdExitMerges.cpp
  TestHandshakeSimulator.cpp

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRMemRefDialect
  MLIRFuncDialect
  MLIRSupport
  MLIRTransformUtils
  DynamaticSupport
  DynamaticHandshake
  DynamaticExperimentalSupport
  DynamaticExperimentalConversion
)
