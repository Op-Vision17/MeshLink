int fastHash(String string) {
  var hash = 0xcbf29ce484222325;
  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i);
    hash ^= codeUnit;
    hash *= 0x100000001b3;
    i++;
  }
  return hash & 0x7fffffffffffffff;
}
