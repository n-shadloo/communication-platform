/// Immutable domain value with structural equality.
abstract class ValueObject {
  const ValueObject();

  List<Object?> get equalityComponents;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is ValueObject &&
          _componentsEqual(equalityComponents, other.equalityComponents);

  @override
  int get hashCode => Object.hashAll(equalityComponents);
}

bool _componentsEqual(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}
