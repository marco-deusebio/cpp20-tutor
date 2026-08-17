#include <memory>
int main() {
  std::unique_ptr<int> null_unique;
  std::shared_ptr<int> null_shared;
  std::weak_ptr<int> null_weak;
  int live = null_unique ? 1 : 0;
  int shared_count = int(null_shared.use_count());
  int weak_count = int(null_weak.use_count());
  return live + shared_count + weak_count;
}
