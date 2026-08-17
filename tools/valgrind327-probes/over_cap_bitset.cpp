#include <bitset>
int main() {
  std::bitset<300> wide;
  wide.set(0);
  wide.set(299);
  std::bitset<8> narrow(0b1010);
  int total = int(wide.count()) + int(narrow.count());
  return total;
}
