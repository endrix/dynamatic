//===- BDD.cpp - BDD Decomposition for Bool Expressions -----*----- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the functions for performing a BDD decomposition on
// boolean logic expression, following a specific order of variables.
//
//===----------------------------------------------------------------------===//

#include "experimental/Support/BooleanLogic/BDD.h"
#include "experimental/Support/BooleanLogic/BoolExpression.h"

#include <iterator>
#include <set>
#include <string>
#include <vector>

using namespace dynamatic::experimental::boolean;
using namespace llvm;

void dynamatic::experimental::boolean::restrict(BoolExpression *exp,
                                                const std::string &var,
                                                bool expressionValue) {

  // If the input is a variable only, then possibly substitute the value with
  // the provided one. If the expression is a binary one, recursively call
  // `restrict` over the two inputs
  if (exp->type == ExpressionType::Variable) {
    SingleCond *singleCond = static_cast<SingleCond *>(exp);
    if (singleCond->id == var) {
      // Invert the value if complemented
      if (singleCond->isNegated)
        exp->type =
            (expressionValue) ? ExpressionType::Zero : ExpressionType::One;
      else
        exp->type =
            (expressionValue) ? ExpressionType::One : ExpressionType::Zero;
    }

  } else if (exp->type == ExpressionType::And ||
             exp->type == ExpressionType::Or) {
    Operator *op = static_cast<Operator *>(exp);

    if (op->left)
      restrict(op->left, var, expressionValue);

    if (op->right)
      restrict(op->right, var, expressionValue);
  }
}

BDD *dynamatic::experimental::boolean::buildBDD(
    BoolExpression *exp, std::vector<std::string> variableList) {
  if (exp->type == ExpressionType::Variable ||
      exp->type == ExpressionType::Zero || exp->type == ExpressionType::One)
    return new BDD(exp);

  // Expand the next variable the expression depends on. A variable the
  // expression does not contain gets no node: its two cofactors would be the
  // same expression, and the node would be a decision taken on a condition the
  // function does not depend on, so that its path contexts, and the circuit
  // built from them, would carry a variable this path never evaluated.
  std::set<std::string> variables = exp->getVariables();
  size_t next = 0;
  while (next < variableList.size() && !variables.count(variableList[next]))
    ++next;
  if (next == variableList.size())
    return new BDD(exp);
  const std::string &var = variableList[next];

  // Get a boolean expression in which `var` is substituted with false
  BoolExpression *restrictedNegative = exp->deepCopy();
  restrict(restrictedNegative, var, false);
  restrictedNegative = restrictedNegative->boolMinimize();

  // Get a boolean expression in which `var` is substituted with true
  BoolExpression *restrictedPositive = exp->deepCopy();
  restrict(restrictedPositive, var, true);
  restrictedPositive = restrictedPositive->boolMinimize();

  // Get a list of the next variables to expand
  std::vector<std::string> subList(
      std::next(variableList.begin(), static_cast<long>(next) + 1),
      variableList.end());

  // Recursively build the left and right sub-trees
  BDD *negativeInput = buildBDD(restrictedNegative, subList);
  BDD *positiveInput = buildBDD(restrictedPositive, subList);
  auto *condition = new SingleCond(ExpressionType::Variable, var);

  return new BDD(negativeInput, positiveInput, condition);
}
