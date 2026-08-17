#include <array>
#include <string>
#include <vector>
int main() {
  std::vector<int> empty_vec;
  std::string empty_str;
  std::array<int, 0> empty_arr{};
  std::vector<std::string> empty_strs;
  int total = int(empty_vec.size() + empty_str.size() + empty_strs.size());
  return total;
}
