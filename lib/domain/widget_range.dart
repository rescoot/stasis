/// Nominal estimate: 45 km per fully charged battery.
/// This is a last-known estimate, not a measured remaining distance.
int? estimatedWidgetRangeKm(int? primarySOC, int? secondarySOC) {
  int? valid(int? soc) => soc == null || soc < 0 ? null : soc.clamp(0, 100);
  final primary = valid(primarySOC);
  final secondary = valid(secondarySOC);
  if (primary == null && secondary == null) return null;
  return (((primary ?? 0) + (secondary ?? 0)) * 0.45).round();
}
