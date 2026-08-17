#include <memory>
int main() {
  std::weak_ptr<int> observer;
  {
    auto owner = std::make_shared<int>(42);
    observer = owner;
    int alive_count = int(observer.use_count());
    (void)alive_count;
  }
  bool is_expired = observer.expired();
  int dead_count = int(observer.use_count());
  return int(is_expired) + dead_count;
}
