int main() {
  int value = 10;
  int& ref = value;
  const int& const_ref = value;
  const int constant = 99;
  ref = 20;
  int total = value + const_ref + constant;
  return total;
}
