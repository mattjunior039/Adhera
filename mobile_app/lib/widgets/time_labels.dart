String relativeTime(DateTime time, {bool compact = false, DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  final (value, unit) = elapsed.inMinutes < 60
      ? (elapsed.inMinutes, compact ? 'm' : ' min')
      : elapsed.inHours < 24
      ? (elapsed.inHours, compact ? 'h' : ' hr')
      : (elapsed.inDays, compact ? 'd' : ' day(s)');
  return '$value$unit ago';
}
