#include <chrono>
int main() {
  std::chrono::milliseconds ms(250);
  std::chrono::seconds sec(3);
  std::chrono::steady_clock::time_point tp{};
  long total = ms.count() + sec.count() + tp.time_since_epoch().count();
  return int(total);
}
