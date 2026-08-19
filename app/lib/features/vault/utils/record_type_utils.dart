class RecordTypeUtils {
  static const List<String> supportedTypes = [
    'text',
    'number',
    'url',
    'boolean',
    'datetime',
  ];

  static String detectType(String value) {
    if (value.isEmpty) return 'text';

    // boolean
    final lower = value.toLowerCase().trim();
    if (lower == 'true' || lower == 'false') {
      return 'boolean';
    }

    // number
    if (num.tryParse(value) != null) {
      return 'number';
    }

    // url
    final uri = Uri.tryParse(value.trim());
    if (uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      return 'url';
    }

    // datetime
    if (DateTime.tryParse(value.trim()) != null) {
      return 'datetime';
    }

    return 'text';
  }

  static String? validateValue(String type, String value) {
    if (value.isEmpty) return null;

    switch (type) {
      case 'number':
        if (num.tryParse(value) == null) {
          return 'Value must be a valid number';
        }
        break;
      case 'boolean':
        final lower = value.toLowerCase().trim();
        if (lower != 'true' && lower != 'false') {
          return 'Value must be true or false';
        }
        break;
      case 'datetime':
        if (DateTime.tryParse(value.trim()) == null) {
          return 'Value must be a valid date/time';
        }
        break;
      case 'url':
        final uri = Uri.tryParse(value.trim());
        if (uri == null ||
            !uri.isAbsolute ||
            (uri.scheme != 'http' && uri.scheme != 'https')) {
          return 'Value must be a valid HTTP/HTTPS URL';
        }
        break;
      case 'text':
      default:
        return null;
    }
    return null;
  }
}
