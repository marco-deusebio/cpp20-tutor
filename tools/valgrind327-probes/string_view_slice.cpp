#include <string>
#include <string_view>
int main() {
  std::string source = "abcdefghij";
  std::string_view whole(source);
  std::string_view middle = whole.substr(2, 3);
  std::string_view empty_view;
  int total = int(whole.size() + middle.size() + empty_view.size());
  return total;
}
