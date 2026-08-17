#include <string>
int main() {
  std::string small = "tiny";
  std::string large = "this string is definitely longer than the sso buffer limit";
  int total = int(small.size() + large.size());
  return total;
}
