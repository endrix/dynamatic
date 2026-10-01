# The C frontend's passes that read the original C source through libclang.
# Kept apart from DynamaticTransforms so that only the tools that run the C
# frontend (dynamatic-opt) depend on libclang.so.
add_dynamatic_library(DynamaticFrontend
  FuncSetArgNames.cpp

  DEPENDS
  DynamaticFrontendPassIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRFuncDialect
  MLIRSupport
  DynamaticSupport
  libclang
)
