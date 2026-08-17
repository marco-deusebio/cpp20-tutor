#include <string>
#include <tuple>
int main() {
  std::tuple<int, double, std::string> row{1, 2.5, "three"};
  int first = std::get<0>(row);
  double second = std::get<1>(row);
  std::string third = std::get<2>(row);
  return first + int(second) + int(third.size());
}
