import 'package:flutter/material.dart';
import 'cloud.dart';

/// Monthly/weekly calendar. Personal appointments can be edited; group
/// appointments are displayed read-only until group editing is implemented.
class CatchItCalendar extends StatefulWidget {
  const CatchItCalendar({super.key, required this.personal, required this.groups,
    required this.onCreate, required this.onEdit,
    required this.personalTasks, required this.groupTasks, required this.onEditTask});
  final List<Map<String, dynamic>> personal;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> personalTasks;
  final List<Map<String, dynamic>> groupTasks;
  final Future<void> Function(Map<String, dynamic> task, bool isGroup) onEditTask;
  final Future<void> Function(DateTime day, bool isGroup) onCreate;
  final Future<void> Function(Map<String, dynamic> appointment, bool isGroup) onEdit;
  @override
  State<CatchItCalendar> createState() => _CatchItCalendarState();
}

class _CatchItCalendarState extends State<CatchItCalendar> {
  final api = CloudApi();
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  bool weekly = false;
  bool showGroupAppointments = false;
  bool fetching = false;
  String? groupError;
  List<Map<String, dynamic>> groupAppointments = [];
  static const burgundy = Color(0xFF812A46);
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const months = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  void initState() { super.initState(); loadGroups(); }

  @override
  void didUpdateWidget(covariant CatchItCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_groupIds(oldWidget.groups) != _groupIds(widget.groups)) loadGroups();
  }

  String _groupIds(List<Map<String, dynamic>> groups) =>
      (groups.map((g) => g['id'].toString()).toList()..sort()).join('|');

  Future<void> loadGroups() async {
    if (!mounted) return;
    setState(() { fetching = true; groupError = null; });
    final collected = <Map<String, dynamic>>[];
    final errors = <String>[];
    for (final group in widget.groups) {
      try {
        final id = group['id'].toString();
        final response = await api.request('GET', 'groups/$id/work');
        final work = Map<String, dynamic>.from(response as Map);
        for (final raw in (work['appointments'] as List? ?? [])) {
          collected.add({...Map<String, dynamic>.from(raw as Map),
            '_groupName': group['name']?.toString() ?? 'Group'});
        }
      } catch (e) { errors.add(group['name']?.toString() ?? 'Group'); }
    }
    if (!mounted) return;
    setState(() {
      groupAppointments = collected;
      fetching = false;
      groupError = errors.isEmpty ? null : 'Could not load appointments for: ${errors.join(', ')}';
    });
  }

  DateTime? _start(Map<String, dynamic> a) =>
      DateTime.tryParse(a[a['_task'] == true ? 'dueUtc' : 'startsUtc']?.toString() ?? '')?.toLocal();
  bool _sameDay(DateTime a, DateTime b) => DateUtils.isSameDay(a, b);
  List<Map<String, dynamic>> _onDay(DateTime day) {
    final all = <Map<String, dynamic>>[
      if (!showGroupAppointments) ...widget.personal.map((a) => {...a, '_personal': true}),
      if (showGroupAppointments) ...groupAppointments.map((a) => {...a, '_personal': false}),
      ...(showGroupAppointments ? widget.groupTasks : widget.personalTasks)
          .map((task) => {...task, '_task': true, '_personal': !showGroupAppointments}),
    ];
    return all.where((a) { final d = _start(a); return d != null && _sameDay(d, day); })
        .toList()..sort((a, b) => _start(a)!.compareTo(_start(b)!));
  }

  DateTime get _weekStart => selected.subtract(Duration(days: selected.weekday - 1));
  void _navigate(int direction) => setState(() {
    if (weekly) {
      selected = selected.add(Duration(days: 7 * direction));
    } else {
      final next = DateTime(selected.year, selected.month + direction, 1);
      final lastDay = DateTime(next.year, next.month + 1, 0).day;
      selected = DateTime(next.year, next.month, selected.day.clamp(1, lastDay));
    }
  });

  Widget _dayCell(DateTime day, {bool outside = false}) {
    final chosen = _sameDay(day, selected);
    final today = _sameDay(day, DateTime.now());
    final items = _onDay(day);
    final hasPersonal = items.any((a) => a['_personal'] == true);
    final hasGroup = items.any((a) => a['_personal'] == false);
    return InkWell(
      onTap: () => setState(() => selected = day),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: chosen ? burgundy : null,
          borderRadius: BorderRadius.circular(12),
          border: today && !chosen ? Border.all(color: burgundy) : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${day.day}', style: TextStyle(
            color: chosen ? Colors.white : outside ? Colors.grey : Colors.black87,
            fontWeight: today || chosen ? FontWeight.bold : FontWeight.normal)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (hasPersonal) _dot(chosen ? Colors.white : burgundy),
            if (hasGroup) ...[const SizedBox(width: 3), _dot(chosen ? Colors.white70 : Colors.teal)],
            if (!hasPersonal && !hasGroup) const SizedBox(height: 6),
          ]),
        ]),
      ),
    );
  }

  Widget _dot(Color color) => Container(width: 6, height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  Widget _calendarGrid() {
    final first = weekly ? _weekStart : DateTime(selected.year, selected.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final count = weekly ? 7 :
      ((DateTime(selected.year, selected.month + 1, 0).day + first.weekday - 2) ~/ 7 + 1) * 7;
    return Column(children: [
      Row(children: [for (final d in weekdays) Expanded(child: Center(child: Text(d,
        style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))))]),
      const SizedBox(height: 7),
      for (int i = 0; i < count; i += 7)
        Row(children: [for (int j = 0; j < 7; j++)
          Expanded(child: _dayCell(gridStart.add(Duration(days: i + j)),
            outside: !weekly && gridStart.add(Duration(days: i + j)).month != selected.month))]),
    ]);
  }

  String _time(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$hour:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _onDay(selected);
    final heading = weekly
        ? '${months[_weekStart.month - 1]} ${_weekStart.day} – ${months[_weekStart.add(const Duration(days: 6)).month - 1]} ${_weekStart.add(const Duration(days: 6)).day}'
        : '${months[selected.month - 1]} ${selected.year}';
    return RefreshIndicator(
      onRefresh: loadGroups,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Personal')),
            ButtonSegment(value: true, label: Text('Group')),
          ],
          selected: {showGroupAppointments},
          onSelectionChanged: (values) =>
              setState(() => showGroupAppointments = values.first),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Month'), icon: Icon(Icons.calendar_month)),
            ButtonSegment(value: true, label: Text('Week'), icon: Icon(Icons.view_week))],
          selected: {weekly}, onSelectionChanged: (values) => setState(() => weekly = values.first)),
        const SizedBox(height: 12),
        Row(children: [
          IconButton(onPressed: () => _navigate(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(heading, textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
          IconButton(onPressed: () => _navigate(1), icon: const Icon(Icons.chevron_right)),
          TextButton(onPressed: () => setState(() => selected = DateUtils.dateOnly(DateTime.now())),
            child: const Text('Today')),
        ]),
        Card(child: Padding(padding: const EdgeInsets.all(10), child: _calendarGrid())),
        const SizedBox(height: 8),
        Row(children: [
          _dot(burgundy), const SizedBox(width: 5), const Text('Personal', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 14), _dot(Colors.teal), const SizedBox(width: 5),
          const Text('Group', style: TextStyle(fontSize: 12)),
          const Spacer(),
          IconButton(tooltip: 'Refresh group appointments', onPressed: fetching ? null : loadGroups,
            icon: const Icon(Icons.refresh)),
        ]),
        if (fetching) const LinearProgressIndicator(),
        if (groupError != null) Padding(padding: const EdgeInsets.all(8),
          child: Text(groupError!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('${weekdays[selected.weekday - 1]}, ${months[selected.month - 1]} ${selected.day}',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          FilledButton.icon(onPressed: () => widget.onCreate(selected, showGroupAppointments),
            icon: const Icon(Icons.add), label: const Text('New')),
        ]),
        if (entries.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No appointments or tasks due'))),
        for (final a in entries)
          Card(child: ListTile(
            leading: Icon(a['_task'] == true ? Icons.check_circle_outline : a['_personal'] == true ? Icons.event : Icons.groups,
              color: a['_personal'] == true ? burgundy : Colors.teal),
            title: Text(a['title']?.toString() ?? (a['_task'] == true ? 'Task' : 'Appointment')),
            subtitle: Text('${a['_task'] == true ? 'Task due' : _time(_start(a)!)}${a['_personal'] == true ? ' · Personal' : ' · ${a['_groupName']}'}'),
            trailing: a['_personal'] == true ? const Icon(Icons.edit_outlined, size: 18) : null,
            onTap: () => a['_task'] == true
                ? widget.onEditTask(a, a['_personal'] != true)
                : widget.onEdit(a, a['_personal'] != true),
          )),
      ]),
    );
  }
}







