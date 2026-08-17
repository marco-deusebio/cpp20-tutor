#include <memory>
int main() {
  std::unique_ptr<int> owned(new int(42));
  std::unique_ptr<int> empty;
  int value = *owned;
  owned.reset();
  bool now_empty = !owned;
  return value + int(now_empty) + int(bool(empty));
}
