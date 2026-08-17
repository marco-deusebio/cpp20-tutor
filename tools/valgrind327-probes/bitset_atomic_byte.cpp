#include <atomic>
#include <bitset>
#include <cstddef>
int main() {
  std::bitset<8> flags(11);
  std::atomic<int> counter(5);
  std::byte raw{42};
  int total = int(flags.count()) + counter.load() + int(raw);
  return total;
}
