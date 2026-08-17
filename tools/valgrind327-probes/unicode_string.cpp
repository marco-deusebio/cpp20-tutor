#include <string>
int main() {
  std::string euro = "€";
  std::string emoji = "\U0001F600";
  std::string mixed = "aéb";
  int total = int(euro.size() + emoji.size() + mixed.size());
  return total;
}
