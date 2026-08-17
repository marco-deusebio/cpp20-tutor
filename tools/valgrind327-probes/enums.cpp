enum class Color { Red, Green, Blue };
enum Plain { One = 1, Two = 2 };
int main() {
  Color c = Color::Green;
  Plain p = Two;
  int total = int(c) + int(p);
  return total;
}
