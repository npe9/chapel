def foo() {
  var t = ("a", "b");
  def bar() {
    var x = t(1);
    t(1) = t(2);
    t(2) = x;
  }
  writeln(t);
  bar();
  writeln(t);
}

foo();
