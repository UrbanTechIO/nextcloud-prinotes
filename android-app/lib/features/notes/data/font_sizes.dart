/// The phone stores a font size as a bare number ("28"). Earlier web versions wrote "28px", which the phone
/// does not recognise (the size picker shows 15 and the text is not resized). Reads such a note's text
/// operations with the size in the phone's form; everything else is passed through unchanged.
List<Map<String, dynamic>> normalizeFontSizes(List<Map<String, dynamic>> ops) {
  return [
    for (final op in ops)
      if (op['attributes'] is Map && (op['attributes'] as Map)['size'] is String && ((op['attributes'] as Map)['size'] as String).toLowerCase().endsWith('px'))
        {
          ...op,
          'attributes': {
            ...Map<String, dynamic>.from(op['attributes'] as Map),
            'size': ((op['attributes'] as Map)['size'] as String).replaceFirst(RegExp(r'px$', caseSensitive: false), ''),
          },
        }
      else
        op,
  ];
}
