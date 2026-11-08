/// Hybrid Logical Clock — `<device_id>:<unix_ms>:<counter>`
///
/// Garanti yon òdonnasman jenere pa anpil aparèy san bezwen yon orloj santral.
/// Itilize pou rezoud konfli (last-write-wins) nan sync.
class Hlc {
  Hlc({required this.deviceId});

  final String deviceId;
  int _lastMs = 0;
  int _counter = 0;

  String next() {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (now > _lastMs) {
      _lastMs = now;
      _counter = 0;
    } else {
      _counter++;
    }
    return '$deviceId:$_lastMs:$_counter';
  }

  static int compare(String a, String b) {
    final pa = a.split(':');
    final pb = b.split(':');
    final msA = int.tryParse(pa.length > 1 ? pa[1] : '0') ?? 0;
    final msB = int.tryParse(pb.length > 1 ? pb[1] : '0') ?? 0;
    if (msA != msB) return msA.compareTo(msB);
    final cA = int.tryParse(pa.length > 2 ? pa[2] : '0') ?? 0;
    final cB = int.tryParse(pb.length > 2 ? pb[2] : '0') ?? 0;
    if (cA != cB) return cA.compareTo(cB);
    return (pa.isNotEmpty ? pa[0] : '').compareTo(pb.isNotEmpty ? pb[0] : '');
  }
}
