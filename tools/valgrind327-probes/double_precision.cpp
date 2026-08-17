#include <limits>
int main() {
  double tiny = 1e-10;
  double precise = 0.123456789012345;
  double huge_val = 1e300;
  double third = 1.0 / 3.0;
  double nan_v = std::numeric_limits<double>::quiet_NaN();
  double inf_v = std::numeric_limits<double>::infinity();
  double neg_zero = -0.0;
  float single = 2.5f;
  return int(tiny + precise + third + single);
}
