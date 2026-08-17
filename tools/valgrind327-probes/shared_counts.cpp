#include <memory>
int main() {
  auto first = std::make_shared<int>(5);
  auto second = first;
  auto third = first;
  int count_now = int(first.use_count());
  second.reset();
  int count_after = int(first.use_count());
  return count_now + count_after;
}
