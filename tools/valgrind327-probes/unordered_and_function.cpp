#include <functional>
#include <source_location>
#include <unordered_map>
#include <unordered_set>
int main() {
  std::source_location where = std::source_location::current();
  std::unordered_map<int, int> umap;
  umap[1] = 10;
  std::unordered_set<int> uset;
  uset.insert(7);
  std::function<int(int)> fn = [](int v) { return v + 1; };
  int total = int(umap.size()) + int(uset.size()) + fn(1) + int(where.line());
  return total & 1;
}
