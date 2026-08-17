#include <complex>
int main() {
  std::complex<double> z(1.5, -2.25);
  std::complex<float> w(0.5f, 3.5f);
  double r = z.real() + w.real();
  return int(r);
}
