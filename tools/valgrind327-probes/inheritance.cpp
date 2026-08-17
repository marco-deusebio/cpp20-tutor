struct Base { int base_field; };
struct Derived : Base { int derived_field; };
int main() {
  Derived d;
  d.base_field = 1;
  d.derived_field = 2;
  Base& as_base = d;
  int total = d.base_field + d.derived_field + as_base.base_field;
  return total;
}
