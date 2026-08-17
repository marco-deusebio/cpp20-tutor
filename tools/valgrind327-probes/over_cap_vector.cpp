#include <vector>
int main() {
  std::vector<int> big;
  for (int i = 0; i < 300; ++i) big.push_back(i);
  int first = big.front();
  int last = big.back();
  return first + last;
}
