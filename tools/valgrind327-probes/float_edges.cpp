#include <limits>
int main() {
  double nan_value = std::numeric_limits<double>::quiet_NaN();
  double pos_inf = std::numeric_limits<double>::infinity();
  double neg_inf = -pos_inf;
  double neg_zero = -0.0;
  double denormal = std::numeric_limits<double>::denorm_min();
  bool nan_is_nan = nan_value != nan_value;
  return int(nan_is_nan) + int(neg_zero == 0.0) + int(denormal > 0.0)
       + int(pos_inf > 0) + int(neg_inf < 0);
}
