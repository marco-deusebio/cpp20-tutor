#include <vector>
int main() {
  std::vector<std::vector<int>> grid;
  grid.push_back({1, 2});
  grid.push_back({3, 4, 5});
  int total = int(grid.size()) + int(grid[1].size());
  return total;
}
