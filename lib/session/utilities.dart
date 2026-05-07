/// Returns true if a string is empty or starts with placeholder text.
bool _isBlank(String s) =>
    s.isEmpty || s.startsWith('_Not') || s.startsWith('_Nothing');
