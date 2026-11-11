import 'dart:io';

/// The IPv4 addresses of this device's interfaces (none when they cannot
/// be listed).
Future<List<String>> localIpv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses) address.address,
    ];
  } on Object {
    return const [];
  }
}

/// The best of [ips] for a phone on the same network to reach (3.x's
/// device sync): no loopback or link-local, private networks first, 192.168
/// over 10 over 172.16/12; empty when there is none.
String bestLanAddress(List<String> ips) {
  final usable = [
    for (final ip in ips)
      if (_ipv4(ip) case final parts? when parts[0] != 127 && !(parts[0] == 169 && parts[1] == 254)) ip,
  ]..sort((a, b) => _priority(b).compareTo(_priority(a)));
  return usable.firstOrNull ?? '';
}

/// Whether [ip] is a dotted IPv4 address.
bool isIpv4(String ip) => _ipv4(ip) != null;

List<int>? _ipv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  final values = [for (final part in parts) int.tryParse(part) ?? -1];
  return values.every((value) => value >= 0 && value <= 255) ? values : null;
}

int _priority(String ip) {
  final parts = _ipv4(ip)!;
  if (parts[0] == 192 && parts[1] == 168) return 3;
  if (parts[0] == 10) return 2;
  if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return 1;
  return 0;
}
