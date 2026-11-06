// The BDD of an expression over an ordered variable list gives a node only to
// a variable the expression depends on at that point. The FTD suppression
// lowers every node to a mux selected by that variable's token and looks each
// leaf up under the decisions above it (FtdSuppression.cpp, bddToCircuit and
// SignalRegistry::lookup), so a node on a variable the cofactor does not
// contain is a mux waiting for a token that path never produces, and the leaves
// under it are looked up under a path no distribution branch registered: they
// fall back to a copy shared with the sibling subtree, and one token is left
// per evaluation.

#include "experimental/Support/BooleanLogic/BDD.h"
#include "experimental/Support/BooleanLogic/BoolExpression.h"
#include <gtest/gtest.h>

using namespace dynamatic::experimental::boolean;

namespace {

/// The variable a node decides on, or the leaf's expression.
std::string label(BDD *node) { return node->boolVariable->toString(); }

TEST(BDD, SkipsVariablesTheCofactorDoesNotContain) {
  // c0 ? c2 . ~c5 : c4 . ~c5, expanded in the order c0, c4, c2, c5 (c4's
  // block before c2's in the topological order, though on the other side of
  // c0): under c0 the function has no c4, under ~c0 no c2.
  BoolExpression *f =
      BoolExpression::parseSop("c0 . c2 . ~c5 + ~c0 . c4 . ~c5");
  ASSERT_NE(f, nullptr);
  BDD *bdd = buildBDD(f, {"c0", "c4", "c2", "c5"});

  ASSERT_TRUE(bdd->successors.has_value());
  EXPECT_EQ(label(bdd), "c0");
  BDD *negative = bdd->successors->first;
  BDD *positive = bdd->successors->second;

  ASSERT_TRUE(negative->successors.has_value());
  EXPECT_EQ(label(negative), "c4");
  ASSERT_TRUE(positive->successors.has_value());
  EXPECT_EQ(label(positive), "c2");

  // Under c0 . c2 the function is ~c5 itself: a leaf, not a node on c5.
  BDD *underC2 = positive->successors->second;
  EXPECT_FALSE(underC2->successors.has_value());
  EXPECT_EQ(label(underC2), "~c5");
  // Under c0 . ~c2 it is zero.
  EXPECT_EQ(positive->successors->first->boolVariable->type,
            ExpressionType::Zero);
}

TEST(BDD, ExpandsEveryVariableTheCofactorContains) {
  BoolExpression *f = BoolExpression::parseSop("c0 . c1 + ~c0 . ~c1");
  ASSERT_NE(f, nullptr);
  BDD *bdd = buildBDD(f, {"c0", "c1"});
  ASSERT_TRUE(bdd->successors.has_value());
  EXPECT_EQ(label(bdd), "c0");
  EXPECT_EQ(label(bdd->successors->first), "~c1");
  EXPECT_EQ(label(bdd->successors->second), "c1");
}

TEST(BDD, KeepsTheExpressionWhenNoListedVariableRemains) {
  BoolExpression *f = BoolExpression::parseSop("c2 . ~c5");
  ASSERT_NE(f, nullptr);
  BDD *bdd = buildBDD(f, {"c0"});
  EXPECT_FALSE(bdd->successors.has_value());
  EXPECT_EQ(label(bdd), f->toString());
}

} // namespace
