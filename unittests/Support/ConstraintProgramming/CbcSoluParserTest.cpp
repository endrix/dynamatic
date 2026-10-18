// The status the CBC back-end reads from the first line of the solution file
// Cbc writes (`solu`). The lines are Cbc 2.10's, from real runs. Stopped on
// its time limit, Cbc writes values either way: with an integer solution they
// are that solution (usable, not proved optimal); without one they are the
// continuous relaxation's, which are no solution to the MILP.

#include "dynamatic/Support/ConstraintProgramming/ConstraintProgramming.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include <gtest/gtest.h>

using namespace dynamatic;

namespace {

/// Parses `content` as a solution file written by Cbc.
detail::CbcSoluParser parse(llvm::StringRef content) {
  detail::CbcSoluParser parser;
  llvm::SmallString<128> path;
  int fd;
  if (llvm::sys::fs::createTemporaryFile("cbc_solution", "sol", fd, path)) {
    ADD_FAILURE() << "cannot create a temporary solution file";
    return parser;
  }
  {
    llvm::raw_fd_ostream os(fd, /*shouldClose=*/true);
    os << content;
  }
  EXPECT_TRUE(succeeded(parser.parseSolverOutput(path)));
  llvm::sys::fs::remove(path);
  return parser;
}

TEST(CbcSoluParser, Optimal) {
  auto sol =
      parse("Optimal - objective value 25.00000000\n"
            "      0 x                      8                       2\n"
            "      2 z                      3                       3\n");
  EXPECT_EQ(sol.status, CPSolver::OPTIMAL);
  EXPECT_DOUBLE_EQ(sol.objectiveValue, 25);
  EXPECT_DOUBLE_EQ(sol.results["x"], 8);
}

TEST(CbcSoluParser, StoppedOnTimeWithIntegerSolution) {
  auto sol = parse("Stopped on time - objective value -0.01540000\n"
                   "     40 bufNumSlots_addi610_result_trueValue_select1954"
                   "                          1                  -1e-05\n");
  EXPECT_EQ(sol.status, CPSolver::NONOPTIMAL);
  EXPECT_DOUBLE_EQ(sol.objectiveValue, -0.0154);
  EXPECT_DOUBLE_EQ(
      sol.results["bufNumSlots_addi610_result_trueValue_select1954"], 1);
}

TEST(CbcSoluParser, StoppedOnTimeWithoutIntegerSolution) {
  auto sol = parse("Stopped on time (no integer solution - continuous used)"
                   " - objective value -0.00281384\n"
                   "      7 bufNumSlots_addi577_result_ins_extui1"
                   "                            0.0150917"
                   "                      -0\n");
  EXPECT_EQ(sol.status, CPSolver::NOSOLUTION);
}

TEST(CbcSoluParser, Infeasible) {
  auto sol =
      parse("Infeasible - objective value 1.00000000\n"
            "      0 x                      1                      -0\n");
  EXPECT_EQ(sol.status, CPSolver::INFEASIBLE);
}

} // namespace
