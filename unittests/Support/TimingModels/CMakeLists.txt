# The commit's kill delays (VK, RK) read from a model file. It needs no
# solver and no environment, so it is part of check-dynamatic.
add_executable(
  test-timing-models
  TimingModelsTest.cpp
)

target_link_libraries(
  test-timing-models
  PUBLIC
  GTest::gtest_main

  LLVMSupport
  DynamaticSupport
)

enable_testing()

include(GoogleTest)

gtest_discover_tests(
  test-timing-models
)

add_custom_target(
  run-timing-models-test
  COMMAND ${CMAKE_CTEST_COMMAND} -C $<CONFIG> -R TimingModel --output-on-failure
  DEPENDS test-timing-models
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  COMMENT "Run unit tests on the timing models' deserialization."
  VERBATIM
  USES_TERMINAL
)
add_to_unit_testing(run-timing-models-test)
