/// Parse a datetime string from the backend as UTC and convert to local time.
/// PostgreSQL sends timestamps without timezone info — we treat them as UTC.
DateTime? parseUtcToLocal(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return null;
  try {
    DateTime dt = DateTime.parse(dateStr);
    // If the backend didn't include timezone info, treat as UTC
    if (!dateStr.contains('Z') && !dateStr.contains('+') && !dateStr.contains('-', 10)) {
      dt = DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, dt.millisecond);
    }
    return dt.toLocal();
  } catch (_) {
    return null;
  }
}
