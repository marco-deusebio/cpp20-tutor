#include <deque>
#include <forward_list>
#include <list>
#include <queue>
#include <stack>
int main() {
  std::deque<int> dq{1, 2};
  std::list<int> lst{3, 4};
  std::forward_list<int> flist{5};
  std::stack<int> stk;
  stk.push(6);
  std::queue<int> q;
  q.push(7);
  int total = int(dq.size() + lst.size() + stk.size() + q.size());
  return total & 1;
}
