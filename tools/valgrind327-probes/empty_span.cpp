#include <span>
#include <vector>
int main() {
  std::vector<int> backing;
  std::span<int> empty_view(backing);
  std::vector<int> filled{1, 2, 3};
  std::span<int> full_view(filled);
  int total = int(empty_view.size()) + int(full_view.size());
  return total;
}
