#include <string>
#include <string_view>
int main() {
  std::u16string wide = u"ab";
  std::u32string wider = U"cd";
  std::string plain = "ef";
  std::u16string_view wide_view(wide);
  int total = int(wide.size() + wider.size() + plain.size() + wide_view.size());
  return total;
}
