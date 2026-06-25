import '../models/academic.dart';

/// Canonical Monday–Sunday order, used to sort and lay out timetable grids.
const kWeekOrder = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _coreWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
const _weekendDays = ['Saturday', 'Sunday'];

/// Which day columns a grid should show: the Monday–Friday skeleton is always
/// shown; Saturday and Sunday appear only when the given slots actually use
/// them, so a normal week stays uncluttered but weekend slots are never hidden.
List<String> displayWeekDays(Iterable<TimeSlot> slots) => [
      ..._coreWeek,
      ..._weekendDays.where((d) => slots.any((s) => s.dayOfWeek == d)),
    ];
