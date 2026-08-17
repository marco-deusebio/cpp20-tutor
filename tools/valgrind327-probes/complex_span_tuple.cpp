#include <complex>
#include <span>
#include <tuple>
#include <vector>
int main() {
  std::complex<double> z(1.5, -2.25);
  std::vector<int> data{1, 2, 3};
  std::span<int> view(data);
  std::tuple<int, double> row{4, 5.5};
  int total = int(z.real()) + int(view.size()) + std::get<0>(row);
  return total;
}
