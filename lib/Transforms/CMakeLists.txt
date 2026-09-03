# See DYNAMATIC_ENABLE_LIBCLANG in the top-level CMakeLists.
set(DYNAMATIC_TRANSFORMS_LIBCLANG)
if (DYNAMATIC_ENABLE_LIBCLANG)
  set(DYNAMATIC_TRANSFORMS_LIBCLANG libclang)
endif()

add_dynamatic_library(DynamaticTransforms
  ArithReduceStrength.cpp
  BackAnnotate.cpp
  FlattenMemRefRowMajor.cpp
  ForceMemoryInterface.cpp
  FuncMaximizeSSA.cpp
  FuncSetArgNames.cpp
  ConsumeProducerOutputAttrMarker.cpp
  HandshakeCanonicalize.cpp
  HandshakeDeactivateMemDependencies.cpp
  HandshakeHoistExtInstances.cpp
  HandshakeMaterialize.cpp
  HandshakeOptimizeBitwidths.cpp
  HandshakeInferBasicBlocks.cpp
  HandshakeReplaceMemoryInterfaces.cpp
  HandshakeRemoveUnusedMemRefs.cpp
  HandshakeMarkBLIFImpl.cpp
  HWFlatten.cpp
  MarkMemoryInterfaces.cpp
  OperationNames.cpp
  PushConstants.cpp
  RemovePolygeistAttributes.cpp
  ScfRotateForLoops.cpp
  ScfSimpleIfToSelect.cpp
  DropUnlistedFunctions.cpp
  HandshakeTreeHeightReduction.cpp
  HandshakeSetUnitImplAttributes.cpp

  DEPENDS
  DynamaticTransformsPassIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRMemRefDialect
  MLIRFuncDialect
  MLIRSupport
  MLIRTransformUtils
  DynamaticSupport
  DynamaticAnalysis
  ${DYNAMATIC_TRANSFORMS_LIBCLANG}
)

add_subdirectory(BufferPlacement)
add_subdirectory(ResourceSharing)
add_subdirectory(LLVMIR)
