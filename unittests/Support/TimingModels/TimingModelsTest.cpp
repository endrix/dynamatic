// The commit's kill delays in a timing model (`handshake.commit`): "VK" (its
// valid in to its kill) and "RK" (the ready of its output to its kill), keys
// beside "VR".."VD" that only a commit's entry has. They are optional -- no
// other unit has a kill out -- and a model without them leaves both at zero.
// Nothing in Dynamatic reads them yet: a consumer that times a kill domain's
// reset does (StreamBlocks' esa-cut-to-period), so their deserialization is
// pinned here rather than through a pass.

#include "dynamatic/Support/TimingModels.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include <gtest/gtest.h>

using namespace dynamatic;

namespace {

/// One entry's body: the keys a TimingModel needs, with `delays` inserted
/// among its delays (the kill's, or nothing).
std::string entry(llvm::StringRef delays) {
  std::string ports = R"("delay": {"data": {"64": 0.0}, "valid": {"1": 0.0},
         "ready": {"1": 0.0}, "VR": 0.0, "CV": 0.0, "CR": 0.0, "VC": 0.0,
         "VD": 0.0})";
  return std::string(R"({
      "latency": {"0": {"64": {"0.0": 0.0}}},
      "delay": {"data": {"32": 0.1, "64": 0.1}, "valid": {"1": 0.022},
                "ready": {"1": 0.028}, "VR": 0.0, "CV": 0.0, "CR": 0.0,
                "VC": 0.0, "VD": 0.0)") +
         delays.str() + "},\n      \"inport\": {" + ports +
         "},\n      \"outport\": {" + ports + "}\n    }";
}

/// Reads a model file holding `content` and leaves it in `db`.
void read(llvm::StringRef content, TimingDatabase &db) {
  llvm::SmallString<128> path;
  int fd;
  if (llvm::sys::fs::createTemporaryFile("timing_models", "json", fd, path)) {
    ADD_FAILURE() << "cannot create a temporary model file";
    return;
  }
  {
    llvm::raw_fd_ostream os(fd, /*shouldClose=*/true);
    os << content;
  }
  std::string jsonPath(path);
  EXPECT_TRUE(succeeded(TimingDatabase::readFromJSON(jsonPath, db)));
  llvm::sys::fs::remove(path);
}

TEST(TimingModelKill, ReadWhereThePairIsThere) {
  TimingDatabase db;
  read("{\n    \"handshake.commit\": " +
           entry(", \"VK\": 0.0096, \"RK\": 0.0091") + "\n  }",
       db);
  const TimingModel *model = db.getModel(llvm::StringRef("handshake.commit"));
  ASSERT_NE(model, nullptr);
  EXPECT_DOUBLE_EQ(model->validToKill, 0.0096);
  EXPECT_DOUBLE_EQ(model->readyToKill, 0.0091);
}

TEST(TimingModelKill, AtValidHasNoReadyToKill) {
  // the kill of a commit with `kill_at_valid` is its valid ANDed with a
  // flip-flop: the ready ends in that flip-flop, so RK is 0 and written
  TimingDatabase db;
  read("{\n    \"handshake.commit.at_valid\": " +
           entry(", \"VK\": 0.009077, \"RK\": 0") + "\n  }",
       db);
  const TimingModel *model =
      db.getModel(llvm::StringRef("handshake.commit.at_valid"));
  ASSERT_NE(model, nullptr);
  EXPECT_DOUBLE_EQ(model->validToKill, 0.009077);
  EXPECT_DOUBLE_EQ(model->readyToKill, 0.0);
}

TEST(TimingModelKill, AbsentLeavesZero) {
  // every other unit's entry, which has no kill out at all
  TimingDatabase db;
  read("{\n    \"handshake.fork\": " + entry("") + "\n  }", db);
  const TimingModel *model = db.getModel(llvm::StringRef("handshake.fork"));
  ASSERT_NE(model, nullptr);
  EXPECT_DOUBLE_EQ(model->validToKill, 0.0);
  EXPECT_DOUBLE_EQ(model->readyToKill, 0.0);
}

} // namespace
