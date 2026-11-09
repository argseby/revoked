/// Reads an item's audience kind (VISIBILITY.md): `private`, `workspace` or
/// `groups`, with anything else, or nothing, read as `private`.
String audienceKindFrom(Object? value) =>
    value == 'workspace' || value == 'groups' ? value as String : 'private';
