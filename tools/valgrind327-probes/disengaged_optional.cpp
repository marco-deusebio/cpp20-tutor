#include <optional>
#include <string>
int main() {
  std::optional<int> no_int;
  std::optional<std::string> no_str;
  std::optional<int> has_int = 7;
  int total = has_int.value_or(0) + no_int.value_or(0);
  bool both_empty = !no_int.has_value() && !no_str.has_value();
  return total + int(both_empty);
}
