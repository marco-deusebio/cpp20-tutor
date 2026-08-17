#include <map>
#include <set>
int main() {
  std::map<int, int> ages;
  ages[1] = 10;
  ages[2] = 20;
  std::set<int> ids;
  ids.insert(7);
  int total = int(ages.size()) + int(ids.size());
  return total;
}
