#include <map>
#include <set>
#include <string>
int main() {
  std::map<int, int> counts;
  counts[1] = 10;
  counts[2] = 20;
  std::set<std::string> names;
  names.insert("alpha");
  int total = int(counts.size()) + int(names.size());
  return total;
}
