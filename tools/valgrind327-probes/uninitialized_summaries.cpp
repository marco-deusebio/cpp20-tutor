#include <any>
#include <array>
#include <atomic>
#include <bitset>
#include <complex>
#include <compare>
#include <chrono>
#include <cstddef>
#include <filesystem>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <ranges>
#include <set>
#include <span>
#include <string>
#include <string_view>
#include <system_error>
#include <tuple>
#include <utility>
#include <variant>
#include <vector>
int main() {
  int backing = 1;
  std::array<int, 3> arr{1, 2, 3};
  std::array<int, 0> arr0{};
  std::unique_ptr<int> uniq(new int(1));
  std::shared_ptr<int> shrd = std::make_shared<int>(2);
  std::weak_ptr<int> weak = shrd;
  std::vector<int> vec{1, 2};
  std::span<int> spn(vec);
  std::reference_wrapper<int> refw(backing);
  std::filesystem::path pth("/tmp/x");
  std::complex<double> cpx(1.5, 2.5);
  std::error_code ec = std::make_error_code(std::errc::invalid_argument);
  std::strong_ordering ord = 1 <=> 2;
  std::any anyv = 42;
  std::string str = "abc";
  std::u16string wstr = u"de";
  std::string_view sv(str);
  std::chrono::milliseconds ms(5);
  std::chrono::steady_clock::time_point tp{};
  std::bitset<8> bits(3);
  std::atomic<int> atm(7);
  std::optional<int> opt = 3;
  std::variant<int, double> var = 1;
  std::tuple<int, double> tup{1, 2.0};
  std::pair<int, int> pr{4, 5};
  std::map<int, int> mp;
  std::set<int> st;
  std::byte by{9};
  std::initializer_list<int> il{1, 2, 3};
  std::variant<std::monostate, int> mono;
  auto iota = std::views::iota(1, 4);
  auto iotait = iota.begin();
  int total = backing + arr[0] + int(vec.size()) + int(str.size());
  return total & 1;
}
