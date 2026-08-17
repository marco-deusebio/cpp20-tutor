#include <any>
#include <filesystem>
#include <functional>
#include <system_error>
int main() {
  std::any boxed = 42;
  std::any empty_any;
  std::filesystem::path p("/tmp/demo.txt");
  std::error_code ec = std::make_error_code(std::errc::invalid_argument);
  int backing = 7;
  std::reference_wrapper<int> ref(backing);
  int total = int(boxed.has_value()) + int(empty_any.has_value()) + ref.get();
  return total;
}
