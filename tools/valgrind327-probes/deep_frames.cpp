int level_three(int v) { int local_three = v * 3; return local_three; }
int level_two(int v) { int local_two = level_three(v) + 2; return local_two; }
int level_one(int v) { int local_one = level_two(v) + 1; return local_one; }
int main() {
  int result = level_one(5);
  return result;
}
