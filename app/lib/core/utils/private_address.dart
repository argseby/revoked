/// Whether [url] points at this machine or a private network: loopback,
/// `localhost`, the private IPv4 ranges, IPv6 unique-local, and the
/// `.local`/`.internal` names that resolve only inside one. A name that
/// resolves to such an address elsewhere can't be told from here; the server
/// still refuses it when it is saved.
bool isPrivateAddress(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal')) {
    return true;
  }
  if (host == '::1' || host.startsWith('fc') || host.startsWith('fd')) {
    return host.contains(':');
  }
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  return a == 127 ||
      a == 10 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31);
}
