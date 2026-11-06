# The BDD builder's variable skipping, which the FTD suppression's mux trees
# and their path contexts rely on. It needs no environment, so it is part of
# check-dynamatic.
add_executable(
  test-boolean-logic
  BDDTest.cpp
)

target_link_libraries(
  test-boolean-logic
  PUBLIC
  GTest::gtest_main

  LLVMSupport
  DynamaticExperimentalSupportBooleanLogic
)

enable_testing()

include(GoogleTest)

gtest_discover_tests(
  test-boolean-logic
)

add_custom_target(
  run-boolean-logic-test
  COMMAND ${CMAKE_CTEST_COMMAND} -C $<CONFIG> -R BDD --output-on-failure
  DEPENDS test-boolean-logic
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  COMMENT "Run unit tests on the Boolean logic (BDD construction)."
  VERBATIM
  USES_TERMINAL
)
add_to_unit_testing(run-boolean-logic-test)
