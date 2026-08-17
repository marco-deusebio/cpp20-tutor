int main() {
  int never_set;
  int copied = never_set;
  int used = copied + 1;
  return used & 1;
}
