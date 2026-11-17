import 'package:senicare/models/models.dart';

/// Intervalo horario flexible con inicio y fin exactos.
class TimeInterval {
  final DateTime start;
  final DateTime end;

  const TimeInterval({required this.start, required this.end});

  int get durationMinutes => end.difference(start).inMinutes;

  double get exactHours => durationMinutes / 60.0;

  String get startFormatted => formatHm(start);

  String get endFormatted => formatHm(end);

  String get formattedRange => '$startFormatted - $endFormatted';

  String get formattedDuration {
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  static String formatHm(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

/// Utilidades compartidas de disponibilidad flexible y cálculo exacto por minutos.
class FlexibleScheduleHelper {
  /// Calcula los intervalos libres reales de un día a partir de los [slots],
  /// excluyendo tramos bloqueados (`isAvailable == false`) y anteriores a `now + minLead`.
  static List<TimeInterval> computeAvailableIntervals({
    required DateTime day,
    required List<TimeSlot> slots,
    DateTime? now,
    Duration minLead = Duration.zero,
    int minBookableMinutes = 30,
  }) {
    final ref = (now ?? DateTime.now()).add(minLead);
    final dayStart = DateTime(day.year, day.month, day.day);
    final isPastDay = dayStart.isBefore(DateTime(ref.year, ref.month, ref.day));
    if (isPastDay) return const [];

    final openIntervals = <TimeInterval>[];
    final blockedIntervals = <TimeInterval>[];

    for (final s in slots) {
      final sStart = s.dateTime;
      final sEnd = s.effectiveEndTime;
      if (!sEnd.isAfter(sStart)) continue;

      if (s.isAvailable) {
        final effectiveStart = sStart.isBefore(ref) ? ref : sStart;
        if (sEnd.difference(effectiveStart).inMinutes >= minBookableMinutes) {
          openIntervals.add(TimeInterval(start: effectiveStart, end: sEnd));
        }
      } else {
        blockedIntervals.add(TimeInterval(start: sStart, end: sEnd));
      }
    }

    if (openIntervals.isEmpty) return const [];

    // 1. Fusionar intervalos abiertos contiguos o solapados
    openIntervals.sort((a, b) => a.start.compareTo(b.start));
    final merged = <TimeInterval>[];
    for (final item in openIntervals) {
      if (merged.isEmpty) {
        merged.add(item);
      } else {
        final last = merged.last;
        if (!item.start.isAfter(last.end)) {
          final maxEnd = item.end.isAfter(last.end) ? item.end : last.end;
          merged[merged.length - 1] = TimeInterval(start: last.start, end: maxEnd);
        } else {
          merged.add(item);
        }
      }
    }

    // 2. Restar intervalos bloqueados / ya reservados
    var result = merged;
    for (final blk in blockedIntervals) {
      final next = <TimeInterval>[];
      for (final cur in result) {
        if (!blk.end.isAfter(cur.start) || !blk.start.isBefore(cur.end)) {
          next.add(cur);
          continue;
        }
        if (blk.start.isAfter(cur.start)) {
          final left = TimeInterval(start: cur.start, end: blk.start);
          if (left.durationMinutes >= minBookableMinutes) next.add(left);
        }
        if (blk.end.isBefore(cur.end)) {
          final right = TimeInterval(start: blk.end, end: cur.end);
          if (right.durationMinutes >= minBookableMinutes) next.add(right);
        }
      }
      result = next;
    }

    return result;
  }

  /// Calcula el importe base exacto según tarifa/hora y duración en minutos.
  static double computeExactCost({
    required double pricePerHour,
    required int durationMinutes,
    bool applyFourHourDiscount = true,
  }) {
    if (pricePerHour <= 0 || durationMinutes <= 0) return 0.0;
    final hours = durationMinutes / 60.0;
    final multiplier = (applyFourHourDiscount && hours >= 4.0) ? 0.95 : 1.0;
    return ((pricePerHour * hours * multiplier) * 100).roundToDouble() / 100.0;
  }

  /// Divide una franja flexible al reservar `[bookStart, bookEnd)` en modo mock/local,
  /// devolviendo las nuevas franjas libres restantes y el tramo bloqueado.
  static List<TimeSlot> splitSlotByBooking({
    required TimeSlot slot,
    required DateTime bookStart,
    required DateTime bookEnd,
    required String dateStr,
  }) {
    final sStart = slot.dateTime;
    final sEnd = slot.effectiveEndTime;
    if (!bookEnd.isAfter(sStart) || !bookStart.isBefore(sEnd)) {
      return [slot];
    }

    final output = <TimeSlot>[];
    String tag(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';

    if (bookStart.isAfter(sStart) &&
        bookStart.difference(sStart).inMinutes >= 30) {
      output.add(TimeSlot(
        id: 'flex_${dateStr}_${tag(sStart)}_${tag(bookStart)}',
        dateTime: sStart,
        endTime: bookStart,
        isAvailable: true,
      ));
    }

    final clippedStart = bookStart.isAfter(sStart) ? bookStart : sStart;
    final clippedEnd = bookEnd.isBefore(sEnd) ? bookEnd : sEnd;
    output.add(TimeSlot(
      id: 'booked_${dateStr}_${tag(clippedStart)}_${tag(clippedEnd)}',
      dateTime: clippedStart,
      endTime: clippedEnd,
      isAvailable: false,
    ));

    if (sEnd.isAfter(bookEnd) && sEnd.difference(bookEnd).inMinutes >= 30) {
      output.add(TimeSlot(
        id: 'flex_${dateStr}_${tag(bookEnd)}_${tag(sEnd)}',
        dateTime: bookEnd,
        endTime: sEnd,
        isAvailable: true,
      ));
    }

    return output;
  }
}
