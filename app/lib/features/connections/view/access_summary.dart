/// What a connected tool or an API key may do, and where in the vault, in one
/// line: "3 permissions · 2 sections". Tools and keys say it the same way, so
/// the two lists read alike.
String accessSummary({
  required int permissions,
  int sections = 0,
  bool wholeVault = false,
}) => [
  permissions == 0
      ? 'No permissions'
      : '$permissions ${permissions == 1 ? 'permission' : 'permissions'}',
  if (wholeVault)
    'whole vault'
  else if (sections > 0)
    '$sections ${sections == 1 ? 'section' : 'sections'}',
].join(' · ');
