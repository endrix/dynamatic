if (GUROBI_FOUND)
add_executable(
  test-constraint-programming
  CPTest.cpp
)

target_link_libraries(
  test-constraint-programming
  PUBLIC
  GTest::gtest_main
  ${GUROBI_CXX_LIBRARY}
  ${GUROBI_LIBRARY}

  LLVMSupport
  DynamaticConstraintProgramming
)

enable_testing()

include(GoogleTest)

gtest_discover_tests(
  test-constraint-programming
  XML_OUTPUT_DIR ${CMAKE_BINARY_DIR}/unittests/Support/ConstraintProgramming/results
)

# To run this unit test:
# ```
# ninja run-constraint-programming-test
# ```
add_custom_target(
  run-constraint-programming-test
  COMMAND ${CMAKE_CTEST_COMMAND} -C $<CONFIG> --parallel 8 --timeout 1500 --output-on-failure
  DEPENDS test-constraint-programming
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/unittests/Support/ConstraintProgramming
  COMMENT "Run unit tests on constraint programming api."
  VERBATIM
  USES_TERMINAL
)



endif()

# The status read from Cbc's solution file. It needs neither Gurobi nor the
# cbc executable, so it is part of check-dynamatic.
if (DYNAMATIC_ENABLE_CBC)
add_executable(
  test-cbc-solution-parser
  CbcSoluParserTest.cpp
)

target_link_libraries(
  test-cbc-solution-parser
  PUBLIC
  GTest::gtest_main

  LLVMSupport
  DynamaticConstraintProgramming
)

enable_testing()

include(GoogleTest)

gtest_discover_tests(
  test-cbc-solution-parser
)

add_custom_target(
  run-cbc-solution-parser-test
  COMMAND ${CMAKE_CTEST_COMMAND} -C $<CONFIG> -R CbcSoluParser --output-on-failure
  DEPENDS test-cbc-solution-parser
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  COMMENT "Run unit tests on Cbc's solution parser."
  VERBATIM
  USES_TERMINAL
)
add_to_unit_testing(run-cbc-solution-parser-test)
endif()
