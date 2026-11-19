import 'group_task_dialog.dart';
import 'task_stages.dart';
import 'task_reminders.dart';
import 'notification_center.dart';
import 'chat.dart';
import 'group_workspace.dart';
import 'calendar_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'auth.dart';
import 'cloud.dart';
import 'dart:typed_data';

void main() => runApp(const CatchItProApp());
const burgundy = Color(0xFF812A46);
const background = Color(0xFFF8F6F5);

class CatchItProApp extends StatelessWidget {
  const CatchItProApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CatchIt Pro', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(seedColor: burgundy),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
    home: const AuthGate(),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.account, required this.onSignOut});
  final Map<String, dynamic> account;
  final VoidCallback onSignOut;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final api = CloudApi();
    Uint8List? avatarBytes;
  bool avatarUploading = false;
  int selected = 0;
  bool showingAccount = false;
  late final appVersion = const MethodChannel('catchit/app_version').invokeMethod<String>('get');
  bool redeemingBeta = false;
  Map<String, dynamic>? updatedAccount;
  Map<String, dynamic> get account => updatedAccount ?? widget.account;

  Future<void> revokeBetaAccess() async {
    String email = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke beta access'),
        content: TextField(
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Account email'),
          onChanged: (value) => email = value.trim(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Revoke')),
        ],
      ),
    );
    if (confirmed != true || !mounted || email.isEmpty) return;
    try {
      await api.request('POST', 'admin/beta-access/revoke', {'email': email});
      final result = await api.request('GET', 'account/me');
      if (!mounted) return;
      setState(() => updatedAccount = Map<String, dynamic>.from(result as Map));
      notify('Beta access revoked for $email.');
    } catch (error) {
      notify(error.toString());
    }
  }

  Future<void> enterBetaCode() async {
    if (redeemingBeta) return;
    String code = '';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter a Beta Code'),
        content: TextField(
          autofocus: true,
          maxLength: 128,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Beta code'),
          onChanged: (value) => code = value.trim(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Redeem')),
        ],
      ),
    );
    if (submitted != true || !mounted || redeemingBeta) return;
    if (code.isEmpty) {
      notify('Enter your beta code.');
      return;
    }
    setState(() => redeemingBeta = true);
    try {
      final result = await api.request('POST', 'account/beta-code', {'code': code});
      if (!mounted) return;
      setState(() => updatedAccount = Map<String, dynamic>.from(result as Map));
      notify('Premium access activated.');
    } catch (error) {
      notify(error.toString());
    } finally {
      if (mounted) setState(() => redeemingBeta = false);
    }
  }
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> tasks = [], appointments = [], groups = [], statuses = [];
  List<Map<String, dynamic>> groupTasks = [];
    int taskView = 0; // 0 = My Tasks, 1 = Group Tasks, 2 = All Tasks
    Future<void> loadAvatar() async {
    try {
      final bytes = await api.downloadAvatar();
      if (mounted) {
        setState(() => avatarBytes = bytes);
      }
    } catch (e) {
      debugPrint('Profile picture unavailable: $e');
      if (mounted) {
        setState(() => avatarBytes = null);
      }
    }
  }
  @override
  void initState() {
    super.initState();
    refresh();
    loadAvatar();
  }

  Future<void> changeAvatar() async {
    if (avatarUploading) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;

      if (bytes == null) {
        throw Exception('Unable to read the selected picture.');
      }

      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        throw Exception('Picture must be smaller than 5 MB.');
      }

      if (!mounted) return;
      setState(() => avatarUploading = true);

      await api.uploadAvatar(file.name, bytes);
      await loadAvatar();

      if (mounted) {
        notify('Profile picture updated successfully.');
      }
    } catch (e) {
      if (mounted) {
        notify('Could not update profile picture: $e');
      }
    } finally {
      if (mounted) {
        setState(() => avatarUploading = false);
      }
    }
  }

  List<Map<String, dynamic>> groupActivityAppointments = [];

  Future<void> refresh() async {
    setState(() { loading = true; error = null; });
    try {
      final data = await Future.wait([api.list('tasks'), api.list('appointments'), api.list('groups/shared'), api.list('statuses')]);
      final loadedGroupTasks = <Map<String, dynamic>>[];
      final loadedGroupAppointments = <Map<String, dynamic>>[];
      for (final group in data[2]) {
        final groupId = group['id'].toString();
        try {
          final work = Map<String, dynamic>.from(await api.request('GET', 'groups/$groupId/work') as Map);
          for (final item in work['tasks'] as List) {
            loadedGroupTasks.add({...Map<String, dynamic>.from(item as Map), '_groupName': group['name'], '_groupId': groupId});
          }
          for (final item in work['appointments'] as List) {
            loadedGroupAppointments.add({...Map<String, dynamic>.from(item as Map), '_groupId': groupId});
          }
        } catch (e) {
          debugPrint('Could not load tasks for group $groupId: $e');
        }
      }
      if (mounted) setState(() { tasks = data[0]; appointments = data[1]; groups = data[2]; statuses = data[3]; groupTasks = loadedGroupTasks; groupActivityAppointments = loadedGroupAppointments; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> editGroupTask(Map<String, dynamic> task) async {
    final groupId = task['_groupId']?.toString() ?? task['groupId']?.toString();
    if (groupId == null || groupId.isEmpty) { notify('Group information is missing.'); return; }
    List<Map<String, dynamic>> members;
    try {
      members = (await api.list('groups/$groupId/members'))
          .where((member) => member['state'] == 'accepted').toList();
    } catch (error) {
      notify(error.toString());
      return;
    }
    if (!mounted) return;
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => GroupTaskDialog(
        task: task,
        members: members,
        insets: taskDialogInsets,
        constraints: taskDialogConstraints,
      ),
    );
    if (!mounted || changes == null) return;
    try {
      await api.update('groups/$groupId/tasks', task['id'].toString(), changes);
      await refresh();
    } catch (error) {
      notify(error.toString());
    }
  }
  Future<void> createGroupTask() async {
    if (groups.isEmpty) { notify('Join or create a group first.'); return; }
    String? selectedGroupId = groups.first['id'].toString();
    final chosenGroupId = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Select task group'), content: DropdownButtonFormField<String>(initialValue: selectedGroupId, isExpanded: true, items: groups.map((g) => DropdownMenuItem<String>(value: g['id'].toString(), child: Text(g['name'].toString()))).toList(), onChanged: (v) => selectedGroupId = v), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, selectedGroupId), child: const Text('Continue'))]));
    if (chosenGroupId == null) return;
    List<Map<String, dynamic>> taskGroupMembers;
    try { taskGroupMembers = (await api.list('groups/$chosenGroupId/members')).where((m) => m['state'] == 'accepted').toList(); } catch (e) { notify(e.toString()); return; }
    if (!mounted) return;
    final taskTitleController = TextEditingController();
    final taskDescriptionController = TextEditingController();
    DateTime? taskDueDate;
    String? taskAssigneeId;
    final taskDetails = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(insetPadding: taskDialogInsets, constraints: taskDialogConstraints, title: const Text('New group task'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: taskTitleController, maxLength: 200, decoration: const InputDecoration(labelText: 'Task title')), TextField(controller: taskDescriptionController, minLines: 5, maxLines: 5, maxLength: 4000, decoration: const InputDecoration(labelText: 'Notes')), OutlinedButton(onPressed: () async { final picked = await showDatePicker(context: ctx, initialDate: taskDueDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100)); if (picked != null) update(() => taskDueDate = picked); }, child: Text(taskDueDate == null ? 'Set due date (optional)' : 'Due: '+taskDueDate!.month.toString()+'/'+taskDueDate!.day.toString()+'/'+taskDueDate!.year.toString())) , DropdownButtonFormField<String>(initialValue: taskAssigneeId, isExpanded: true, decoration: const InputDecoration(labelText: 'Assign to (optional)'), items: [const DropdownMenuItem<String>(value: null, child: Text('Unassigned')), ...taskGroupMembers.map((m) => DropdownMenuItem<String>(value: m['userId'].toString(), child: Text(m['name'].toString())))], onChanged: (v) => update(() => taskAssigneeId = v))])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue'))])));
    final newTaskTitle = taskTitleController.text.trim();
    final newTaskDescription = taskDescriptionController.text.trim();
    taskTitleController.dispose();
    taskDescriptionController.dispose();
    if (taskDetails != true) return;
    if (newTaskTitle.isEmpty) { notify('Task title is required.'); return; }
    try { await api.add('groups/$chosenGroupId/tasks', {'title': newTaskTitle, 'description': newTaskDescription, 'dueUtc': taskDueDate?.toUtc().toIso8601String(), 'assigneeId': taskAssigneeId, 'isDone': false}); await refresh(); } catch (e) { notify(e.toString()); }
  }

  Future<void> editGroupAppointment(Map<String, dynamic> appointment) async {
    final groupId = appointment['groupId']?.toString() ?? appointment['_groupId']?.toString();
    if (groupId == null || groupId.isEmpty) { notify('Group information is missing.'); return; }
    final editTitleController = TextEditingController(text: appointment['title']?.toString() ?? '');
    final editStart = DateTime.tryParse(appointment['startsUtc']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    DateTime editDate = editStart;
    TimeOfDay editTime = TimeOfDay.fromDateTime(editStart);
    String? editAssigneeId = appointment['assigneeId']?.toString();
    List<Map<String, dynamic>> editMembers;
    try { editMembers = (await api.list('groups/$groupId/members')).where((m) => m['state'] == 'accepted').toList(); } catch (e) { editTitleController.dispose(); notify(e.toString()); return; }
    if (!mounted) { editTitleController.dispose(); return; }
    final editResult = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(title: const Text('Edit group appointment'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: editTitleController, maxLength: 200, decoration: const InputDecoration(labelText: 'Appointment title')), OutlinedButton(onPressed: () async { final picked = await showDatePicker(context: ctx, initialDate: editDate, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (picked != null) update(() => editDate = picked); }, child: Text('Change date')), OutlinedButton(onPressed: () async { final picked = await showTimePicker(context: ctx, initialTime: editTime); if (picked != null) update(() => editTime = picked); }, child: Text('Change time')), DropdownButtonFormField<String>(initialValue: editAssigneeId, isExpanded: true, decoration: const InputDecoration(labelText: 'Assigned member'), items: [const DropdownMenuItem<String>(value: null, child: Text('Unassigned')), ...editMembers.map((m) => DropdownMenuItem<String>(value: m['userId'].toString(), child: Text(m['name'].toString())))], onChanged: (v) => update(() => editAssigneeId = v))])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))])));
    if (editResult != true) { editTitleController.dispose(); return; }
    final updatedTitle = editTitleController.text.trim();
    editTitleController.dispose();
    if (updatedTitle.isEmpty) { notify('Appointment title is required.'); return; }
    final updatedStart = DateTime(editDate.year, editDate.month, editDate.day, editTime.hour, editTime.minute).toUtc();
    final originalEnd = DateTime.tryParse(appointment['endsUtc']?.toString() ?? '');
    final duration = originalEnd == null ? const Duration(hours: 1) : originalEnd.difference(editStart.toUtc());
    final updatedEnd = updatedStart.add(duration > Duration.zero ? duration : const Duration(hours: 1));
    try { await api.update('groups/$groupId/appointments', appointment['id'].toString(), {'title': updatedTitle, 'assigneeId': editAssigneeId, 'startsUtc': updatedStart.toIso8601String(), 'endsUtc': updatedEnd.toIso8601String()}); await refresh(); } catch (e) { notify(e.toString()); }
  }

  Future<void> createGroupAppointment(DateTime day) async {
    if (groups.isEmpty) { notify('Join or create a group first.'); return; }
    String? groupId = groups.first['id'].toString();
    final chosen = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Select appointment group'), content: DropdownButtonFormField<String>(initialValue: groupId, isExpanded: true, items: groups.map((g) => DropdownMenuItem<String>(value: g['id'].toString(), child: Text(g['name'].toString()))).toList(), onChanged: (v) => groupId = v), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, groupId), child: const Text('Continue'))]));
    if (chosen == null) return;
    List<Map<String, dynamic>> groupMembers;
    try { groupMembers = (await api.list('groups/$chosen/members')).where((m) => m['state'] == 'accepted').toList(); } catch (e) { notify(e.toString()); return; }
    if (!mounted) return;
    final titleController = TextEditingController();
    String? assigneeId;
    DateTime appointmentDate = day;
    TimeOfDay appointmentTime = const TimeOfDay(hour: 9, minute: 0);
    final details = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(title: const Text('New group appointment'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: titleController, maxLength: 200, decoration: const InputDecoration(labelText: 'Appointment title')), OutlinedButton(onPressed: () async { final picked = await showDatePicker(context: ctx, initialDate: appointmentDate, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (picked != null) update(() => appointmentDate = picked); }, child: Text('Date: '+appointmentDate.month.toString()+'/'+appointmentDate.day.toString()+'/'+appointmentDate.year.toString())), OutlinedButton(onPressed: () async { final picked = await showTimePicker(context: ctx, initialTime: appointmentTime); if (picked != null) update(() => appointmentTime = picked); }, child: Text('Time: '+appointmentTime.format(ctx))), DropdownButtonFormField<String>(initialValue: assigneeId, isExpanded: true, decoration: const InputDecoration(labelText: 'Assign to (optional)'), items: [const DropdownMenuItem<String>(value: null, child: Text('Unassigned')), ...groupMembers.map((m) => DropdownMenuItem<String>(value: m['userId'].toString(), child: Text(m['name'].toString())))], onChanged: (v) => update(() => assigneeId = v))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, {'title': titleController.text.trim(), 'assigneeId': assigneeId}), child: const Text('Continue'))])));
    titleController.dispose();
    if (details == null || (details['title'] as String).isEmpty) return;
    final start = DateTime(appointmentDate.year, appointmentDate.month, appointmentDate.day, appointmentTime.hour, appointmentTime.minute).toUtc();
    try { await api.add('groups/$chosen/appointments', {'title': details['title'], 'assigneeId': details['assigneeId'], 'startsUtc': start.toIso8601String(), 'endsUtc': start.add(const Duration(hours: 1)).toIso8601String()}); await refresh(); } catch (e) { notify(e.toString()); }
  }

  static const taskDialogInsets = EdgeInsets.symmetric(horizontal: 16, vertical: 24);
  static const taskDialogConstraints = BoxConstraints(minWidth: 560, maxWidth: 560);

  Future<void> create(String resource, {DateTime? initialDate}) async {
    String title = '';
    String description = '';
    DateTime? due;
    int? alertMinutes;
    DateTime date = initialDate ?? DateTime.now().add(const Duration(days: 1));
    TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);
    String? statusId;
    final isAppointment = resource == 'appointments';
    final wideDialog = resource == 'tasks' || isAppointment;
    DateTime appointmentStart() => DateTime(date.year, date.month, date.day, time.hour, time.minute);
    String? alertError;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
      insetPadding: wideDialog ? taskDialogInsets : null,
      constraints: wideDialog ? taskDialogConstraints : null,
      title: Text(resource == 'tasks' ? 'New task' : resource == 'appointments' ? 'New appointment' : resource == 'groups' ? 'New group' : 'New status'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(autofocus: true, maxLength: 100, decoration: const InputDecoration(labelText: 'Name / title'), onChanged: (value) => title = value),
        if (resource == 'tasks') ...[
          const SizedBox(height: 12),
          TextFormField(
            minLines: 5, maxLines: 5,
            decoration: const InputDecoration(labelText: 'Notes'),
            onChanged: (value) => description = value,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(due == null ? 'Set due date' : 'Due: ${due!.month}/${due!.day}/${due!.year}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: due ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null && ctx.mounted) {
                update(() => due = DateTime(picked.year, picked.month, picked.day, 12));
              }
            },
          ),
          if (due != null)
            TextButton(
              onPressed: () => update(() { due = null; alertMinutes = null; }),
              child: const Text('Clear due date'),
            ),
          if (due != null && taskRemindersSupported) ...[
            OutlinedButton(
              onPressed: () async {
                final day = due!;
                final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(day));
                if (time != null && ctx.mounted) {
                  update(() => due = DateTime(day.year, day.month, day.day, time.hour, time.minute));
                }
              },
              child: Text('Due time: ${TimeOfDay.fromDateTime(due!).format(ctx)}'),
            ),
            taskAlertField(alertMinutes, (value) => update(() => alertMinutes = value)),
          ],
        ],
        if (resource == 'tasks' || resource == 'appointments') ...[
          if (statuses.isNotEmpty) DropdownButtonFormField<String>(value: statusId, decoration: const InputDecoration(labelText: 'Status (optional)'),
            items: statuses.map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['name'].toString()))).toList(),
            onChanged: (v) => update(() => statusId = v)),
          if (resource == 'appointments') ...[
            const SizedBox(height: 12), OutlinedButton(onPressed: () async { final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (picked != null) update(() => date = picked); }, child: Text('Date: ${date.month}/${date.day}/${date.year}')),
            OutlinedButton(onPressed: () async { final picked = await showTimePicker(context: ctx, initialTime: time); if (picked != null) update(() => time = picked); }, child: Text('Time: ${time.format(ctx)}')),
            if (taskRemindersSupported)
              taskAlertField(alertMinutes, (value) => update(() => alertMinutes = value)),
          ],
        ],
        if (alertError != null)
          Text(alertError!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (alertMinutes != null &&
              !(isAppointment ? appointmentStart() : due!).subtract(Duration(minutes: alertMinutes!)).isAfter(DateTime.now())) {
            update(() => alertError = 'Choose a time or alert that is still in the future.');
            return;
          }
          Navigator.pop(ctx, true);
        }, child: const Text('Save')),
      ],
    )));
    title = title.trim();
    if (ok != true || title.isEmpty) return;
    try {
      final starts = appointmentStart().toUtc();
      final data = switch (resource) {
        'tasks' => <String, dynamic>{
          'title': title,
          'description': description.trim(),
          'statusId': statusId,
          'groupId': null,
          'dueUtc': due?.toUtc().toIso8601String(),
          'isDone': false,
        },
        'appointments' => <String, dynamic>{'title': title, 'startsUtc': starts.toIso8601String(), 'endsUtc': starts.add(const Duration(hours: 1)).toIso8601String(), 'statusId': statusId, 'groupId': null},
        'groups' => <String, dynamic>{'name': title},
        _ => <String, dynamic>{'name': title, 'color': '#812A46', 'sortOrder': statuses.length},
      };
      if (alertMinutes != null) {
        final created = await api.request('POST', resource, data) as Map;
        final id = created['id'].toString();
        await saveTaskAlert(isAppointment ? 'appointment:$id' : id,
            isAppointment ? starts : due, alertMinutes, title);
        if (mounted && await taskReminders.invokeMethod<bool>('exactAllowed') == false && mounted) {
          final allow = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
            title: const Text('Allow on-time reminders?'),
            content: const Text('Allow CatchIt Pro under Alarms & reminders. Otherwise Android may delay the alert.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open settings')),
            ],
          ));
          if (allow == true) await taskReminders.invokeMethod<void>('alarmSettings');
        }
      } else {
        await api.add(resource, data);
      }
      await refresh();
    } catch (e) { notify(e.toString()); }
  }

  Future<void> editAppointment(Map<String, dynamic> appointment) async {
    String title = (appointment['title'] ?? '').toString();
    String? statusId = appointment['statusId']?.toString();
    final originalStart = DateTime.tryParse(
      appointment['startsUtc']?.toString() ?? '',
    );
    final originalEnd = DateTime.tryParse(
      appointment['endsUtc']?.toString() ?? '',
    );
    if (originalStart == null) {
      notify('This appointment has an invalid start date.');
      return;
    }
    DateTime start = originalStart.toLocal();
    final duration = originalEnd != null && originalEnd.isAfter(originalStart)
        ? originalEnd.difference(originalStart)
        : const Duration(hours: 1);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('Edit appointment'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                initialValue: title,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Appointment title'),
                onChanged: (value) => title = value,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Date: ${start.month}/${start.day}/${start.year}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: start,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    updateDialog(() => start = DateTime(
                      picked.year, picked.month, picked.day,
                      start.hour, start.minute,
                    ));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text('Time: ${TimeOfDay.fromDateTime(start).format(dialogContext)}'),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: dialogContext,
                    initialTime: TimeOfDay.fromDateTime(start),
                  );
                  if (picked != null) {
                    updateDialog(() => start = DateTime(
                      start.year, start.month, start.day,
                      picked.hour, picked.minute,
                    ));
                  }
                },
              ),
              if (statuses.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: statuses.any((s) => s['id'].toString() == statusId)
                      ? statusId : null,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '', child: Text('No status'),
                    ),
                    ...statuses.map((s) => DropdownMenuItem<String>(
                      value: s['id'].toString(),
                      child: Text(s['name'].toString()),
                    )),
                  ],
                  onChanged: (value) => updateDialog(() => statusId = value),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    if (title.trim().isEmpty) {
      notify('Please enter an appointment title.');
      return;
    }
    try {
      final startUtc = start.toUtc();
      await api.update('appointments', appointment['id'].toString(), {
        'title': title.trim(),
        'startsUtc': startUtc.toIso8601String(),
        'endsUtc': startUtc.add(duration).toIso8601String(),
        'statusId': (statusId == null || statusId!.isEmpty) ? null : statusId,
        'groupId': appointment['groupId'],
      });
      if (taskRemindersSupported) {
        final reminderId = "appointment:${appointment['id']}";
        final minutes = await taskReminders.invokeMethod<int>('get', {'id': reminderId});
        if (minutes != null) await saveTaskAlert(reminderId, startUtc, minutes, title.trim());
      }
      await refresh();
      notify('Appointment updated');
    } catch (e) {
      notify(e.toString());
    }
  }

  Future<void> editTask(Map<String, dynamic> task) async {
    String title = (task['title'] ?? '').toString();
    String description = (task['description'] ?? '').toString();
    String? statusId = task['statusId']?.toString();
    String stage = taskStage(task);
    DateTime? due = DateTime.tryParse(task['dueUtc']?.toString() ?? '')?.toLocal();
    final taskId = task['id'].toString();
    int? alertMinutes = taskRemindersSupported
        ? await taskReminders.invokeMethod<int>('get', {'id': taskId})
        : null;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          insetPadding: taskDialogInsets, constraints: taskDialogConstraints, title: const Text('Edit task'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                initialValue: title,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Task title'),
                onChanged: (value) => title = value,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: description,
                minLines: 5, maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notes'),
                onChanged: (value) => description = value,
              ),
              taskStageField(stage, (value) => updateDialog(() => stage = value)),
              if (statuses.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: statuses.any((s) => s['id'].toString() == statusId) ? statusId : null,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('No status')),
                    ...statuses.map((s) => DropdownMenuItem<String>(
                      value: s['id'].toString(), child: Text(s['name'].toString()),
                    )),
                  ],
                  onChanged: (value) => updateDialog(() => statusId = value),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(due == null ? 'Set due date' : 'Due: ${due!.month}/${due!.day}/${due!.year}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: due ?? DateTime.now(),
                    firstDate: DateTime(2020), lastDate: DateTime(2100),
                  );
                  if (picked != null && dialogContext.mounted) {
                    updateDialog(() => due = DateTime(picked.year, picked.month, picked.day, due?.hour ?? 12, due?.minute ?? 0));
                  }
                },
              ),
              if (due != null) TextButton(
                onPressed: () => updateDialog(() { due = null; alertMinutes = null; }),
                child: const Text('Clear due date'),
              ),
              if (due != null && taskRemindersSupported) ...[
                OutlinedButton(
                  onPressed: () async {
                    final day = due!;
                    final time = await showTimePicker(context: dialogContext, initialTime: TimeOfDay.fromDateTime(day));
                    if (time != null && dialogContext.mounted) {
                      updateDialog(() => due = DateTime(day.year, day.month, day.day, time.hour, time.minute));
                    }
                  },
                  child: Text('Due time: ${TimeOfDay.fromDateTime(due!).format(dialogContext)}'),
                ),
                taskAlertField(alertMinutes, (value) => updateDialog(() => alertMinutes = value)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (title.trim().isEmpty) { notify('Please enter a task title.'); return; }
    try {
      await api.update('tasks', task['id'].toString(), {
        'title': title.trim(),
        'description': description.trim(),
        'dueUtc': due?.toUtc().toIso8601String(),
        'statusId': (statusId == null || statusId!.isEmpty) ? null : statusId,
        'groupId': task['groupId'],
        'taskStage': stage, 'expectedStage': taskStage(task),
      });
      if (taskRemindersSupported) {
        await saveTaskAlert(taskId, due,
            stage == 'Completed' || stage == 'Archive' ? null : alertMinutes, title.trim());
      }
      await refresh();
      notify('Task updated');
    } catch (e) { notify(e.toString()); }
  }

  Future<void> remove(String resource, String id) async {
    try {
      await api.delete(resource, id);
      if (resource == 'tasks') await saveTaskAlert(id, null, null, '');
      if (resource == 'appointments') await saveTaskAlert('appointment:$id', null, null, '');
      await refresh();
    } catch (e) { notify(e.toString()); }
  }
  Future<void> toggleTask(Map<String, dynamic> task, {String? groupId}) async {
    final resource = groupId == null ? 'tasks' : 'groups/$groupId/tasks';
    try {
      final next = nextTaskStage(task);
      await saveTaskStage(api, resource, task, next);
      if (groupId == null && (next == 'Completed' || next == 'Archive')) {
        await saveTaskAlert(task['id'].toString(), null, null, '');
      }
      await refresh();
    } catch (e) { notify(e.toString()); }
  }
  void notify(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  Widget heading(String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)));
    Widget tile(
    String title,
    String subtitle,
    IconData icon, {
    VoidCallback? onTap,
    VoidCallback? onDelete,
    VoidCallback? onLeadingTap,
    Color? titleColor,
  }) =>
      Card(
        child: ListTile(
          leading: InkWell(
            onTap: onLeadingTap,
            borderRadius: BorderRadius.circular(30),
            child: CircleAvatar(
              backgroundColor: const Color(0xFFF3E3E9),
              child: Icon(icon, color: burgundy),
            ),
          ),
          title: Text(
            title,
            style: titleColor == null ? null : TextStyle(color: titleColor),
          ),
          subtitle: Text(subtitle),
          onTap: onTap,
          trailing: onDelete == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
        ),
      );
  String statusName(dynamic id) { for (final s in statuses) { if (s['id'] == id) return s['name'].toString(); } return 'No status'; }
  Widget home() {
    final activity = <({Map<String, dynamic> item, DateTime time, bool task, bool group})>[];
    void add(List<Map<String, dynamic>> items, {required bool task, required bool group}) {
      for (final item in items) {
        final time = DateTime.tryParse((item['activityUtc'] ?? item['createdUtc'] ?? '').toString());
        if (time != null) activity.add((item: item, time: time, task: task, group: group));
      }
    }
    add(tasks, task: true, group: false);
    add(groupTasks, task: true, group: true);
    add(appointments, task: false, group: false);
    add(groupActivityAppointments, task: false, group: true);
    activity.sort((a, b) => b.time.compareTo(a.time));
    final locale = MaterialLocalizations.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 18), children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text('Your activity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      if (activity.isEmpty) const Text('No recent task or appointment activity.'),
      for (final entry in activity.take(20))
        tile(
          entry.item['title'].toString(),
          '${entry.task ? 'Task' : 'Appointment'} · ${locale.formatShortDate(entry.time.toLocal())} ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(entry.time.toLocal()))}',
          entry.task ? Icons.task_alt : Icons.event,
          onTap: () => entry.task
              ? (entry.group ? editGroupTask(entry.item) : editTask(entry.item))
              : (entry.group ? editGroupAppointment(entry.item) : editAppointment(entry.item)),
        ),
    ]);
  }

  Widget homeQuickActions() {
    Widget action(String label, IconData icon, VoidCallback onPressed) =>
        Expanded(child: IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon)));
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(children: [
        action('Notifications', Icons.notifications_outlined, openNotifications),
        action('Add appointment', Icons.event_available_outlined, () => create('appointments')),
        action('Add task', Icons.add_task, () => create('tasks')),
        action('Add group', Icons.group_add_outlined, () => create('groups')),
        action('Throw a pitch', Icons.edit_square, () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ChatInbox(
            currentUserId: widget.account['id'].toString(), startNewChat: true,
          )),
        )),
      ]),
    );
  }

  void openNotifications() => Navigator.push(context,
    MaterialPageRoute(builder: (_) => const NotificationCenter()));
  Widget tasksPage() => ListView(padding: const EdgeInsets.all(18), children: [
    SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('My Tasks')),
        ButtonSegment(value: 1, label: Text('Group Tasks')),
        ButtonSegment(value: 2, label: Text('All Tasks')),
      ],
      selected: {taskView},
      onSelectionChanged: (values) => setState(() => taskView = values.first),
    ),
       const SizedBox(height: 8),
        heading(taskView == 0 ? 'My Tasks' : taskView == 1 ? 'Group Tasks' : 'All Tasks'),
    if (taskView != 1) ...tasks.map((t) => tile(t['title'].toString(), '${statusName(t['statusId'])} · ${taskStage(t)}', t['isDone'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
      onTap: () => editTask(t), onLeadingTap: () => toggleTask(t), onDelete: () => remove('tasks', t['id'].toString()),
        titleColor: Colors.black)),
    if (taskView != 0) ...groupTasks.map((t) => tile(t['title'].toString(), "${t['_groupName']} · ${taskStage(t)}", t['isDone'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
      onTap: () => editGroupTask(t), onLeadingTap: () => toggleTask(t, groupId: t['groupId'].toString()),
        titleColor: burgundy)),
  ]);
  Widget appointmentsPage() => CatchItCalendar(
    personal: appointments,
    groups: groups,
    personalTasks: tasks,
    groupTasks: groupTasks,
    onEditTask: (task, isGroup) => isGroup ? editGroupTask(task) : editTask(task),
    onCreate: (day, isGroup) => isGroup ? createGroupAppointment(day) : create('appointments', initialDate: day),
    onEdit: (appointment, isGroup) => isGroup ? editGroupAppointment(appointment) : editAppointment(appointment),
  );
  Future<void> showInvitations() async {
    try {
      final invites = await api.list('invitations');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Group invitations'),
        content: SizedBox(width: 320, child: invites.isEmpty ? const Text('No pending invitations') : ListView(shrinkWrap: true, children: invites.map((invite) => Column(children: [
          Text(invite['groupName'].toString()),
          Wrap(children: [TextButton(onPressed: () async { await api.request('POST', 'invitations/${invite['id']}/respond', {'accept': false}); if (dialogContext.mounted) Navigator.pop(dialogContext); await refresh(); }, child: const Text('Decline')),
          FilledButton(onPressed: () async { await api.request('POST', 'invitations/${invite['id']}/respond', {'accept': true}); if (dialogContext.mounted) Navigator.pop(dialogContext); await refresh(); }, child: const Text('Accept'))]),
        ])).toList())),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Widget groupsPage() => ListView(padding: const EdgeInsets.all(18), children: [heading('My groups'), OutlinedButton.icon(onPressed: showInvitations, icon: const Icon(Icons.mail_outline), label: const Text('View invitations')),
    ...groups.map((g) => tile(g['name'].toString(), 'Open shared workspace', Icons.groups, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupWorkspace(group: g))), onDelete: g['role'] == 'owner' ? () => remove('groups', g['id'].toString()) : null)),
  ]);
  Future<void> editStatus(Map<String, dynamic> status) async {
    final form = GlobalKey<FormState>();
    var name = status['name'].toString();
    var color = status['color'].toString();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit status'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              initialValue: name,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (value) => name = value.trim(),
              validator: (value) => name.isEmpty ? 'Enter a status name.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: color,
              decoration: const InputDecoration(labelText: 'Color', hintText: '#812A46'),
              onChanged: (value) => color = value.trim(),
              validator: (value) => RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)
                  ? null : 'Enter a color like #812A46.',
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await api.update('statuses', status['id'].toString(), {
        'name': name, 'color': color, 'sortOrder': status['sortOrder'],
      });
      if (mounted) await refresh();
    } catch (error) {
      notify(error.toString());
    }
  }

  Widget accountPage() => ListView(padding: const EdgeInsets.all(18), children: [
        Center(
      child: CircleAvatar(
        radius: 55,
        backgroundColor: const Color(0xFFF3E3E9),
        backgroundImage: avatarBytes != null
            ? MemoryImage(avatarBytes!)
            : null,
        child: avatarBytes == null
            ? const Icon(Icons.person, size: 60, color: burgundy)
            : null,
      ),
    ),
    const SizedBox(height: 16),
    Center(
      child: OutlinedButton.icon(
        onPressed: avatarUploading ? null : changeAvatar,
        icon: avatarUploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(
          avatarUploading
              ? 'Uploading Picture...'
              : 'Change Profile Picture',
        ),
      ),
    ),
    const SizedBox(height: 20),
    tile(widget.account['name']?.toString() ?? 'Account', widget.account['email']?.toString() ?? '', Icons.person),
    ExpansionTile(
      key: const PageStorageKey('account-settings'),
      leading: const Icon(Icons.settings_outlined),
      title: const Text('Settings'),
      children: [
        ExpansionTile(
          key: const PageStorageKey('account-statuses'),
          leading: const Icon(Icons.label_outline),
          title: const Text('Statuses'),
          children: [
            for (final status in statuses)
              tile(status['name'].toString(), status['color'].toString(), Icons.edit_outlined,
                onTap: () => editStatus(status),
                onDelete: () => remove('statuses', status['id'].toString())),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add status'),
              onTap: () => create('statuses'),
            ),
          ],
        ),
      ],
    ),
    ExpansionTile(
      key: const PageStorageKey('account-subscriptions'),
      leading: const Icon(Icons.workspace_premium_outlined),
      title: const Text('Subscriptions'),
      children: [
    Card(
      child: ListTile(
        title: const Text('Your Catchit Pro plan'),
        subtitle: Text(switch (account['tier']) {
          'premium' => 'Premium',
          'trial' => '${account['trialDaysRemaining']} trial days remaining',
          _ => 'Free plan',
        }),
      ),
    ),
    tile('Premium monthly', '\$9.99 / month · billing not enabled', Icons.workspace_premium),
    tile('Premium annual', '\$99.99 / year · billing not enabled', Icons.stars),
    tile('Enter a Beta Code', 'Redeem complimentary Premium access', Icons.confirmation_number_outlined,
      onTap: redeemingBeta ? null : enterBetaCode),
    if (account['canManageBetaAccess'] == true)
      tile('Revoke beta access', 'Manage an account’s complimentary access', Icons.admin_panel_settings_outlined,
        onTap: revokeBetaAccess),
      ],
    ),
    ExpansionTile(
      key: const PageStorageKey('account-about'),
      leading: const Icon(Icons.info_outline),
      title: const Text('About'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: burgundy, borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            const Text('Catchit Pro', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset('assets/catchit_logo.png', width: 80, height: 80),
            ),
            const SizedBox(height: 12),
            const Text('Catch the Ball', style: TextStyle(color: Color(0xFFFFDCAD), fontSize: 21, fontStyle: FontStyle.italic)),
            const SizedBox(height: 16),
            const Text('NO BIG TECH.\nNO SPYING.\nNO ADS EVER!', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, height: 1.6)),
            const SizedBox(height: 8),
            const Text('Our Promise!', style: TextStyle(color: Color(0xFFFFDCAD))),
          ]),
        ),
    FutureBuilder<String?>(
      future: appVersion,
      builder: (context, snapshot) => snapshot.hasData
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Version ${snapshot.data}', style: Theme.of(context).textTheme.bodySmall),
            )
          : const SizedBox.shrink(),
    ),
      ],
    ),
    const SizedBox(height: 16), OutlinedButton.icon(onPressed: widget.onSignOut, icon: const Icon(Icons.logout), label: const Text('Sign out')),
  ]);
  @override
  Widget build(BuildContext context) {
    final titles = ['Home', 'Appointments', 'My Tasks', 'Groups', 'Messages'];
    return Scaffold(
      appBar: AppBar(
        title: !showingAccount && selected == 0
            ? Row(
                children: [
                  ClipOval(child: Image.asset('assets/catchit_logo.png', width: 36, height: 36)),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Catch the Ball', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            : Text(showingAccount ? 'My Account' : titles[selected], style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: openNotifications, tooltip: 'Notifications', icon: const Icon(Icons.notifications_outlined)), if (showingAccount || selected != 4) IconButton(onPressed: refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
        IconButton(
          tooltip: 'My Account',
          onPressed: () => setState(() => showingAccount = true),
          icon: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFF3E3E9),
            backgroundImage: avatarBytes == null ? null : MemoryImage(avatarBytes!),
            child: avatarBytes == null
                ? const Icon(Icons.person, color: Color(0xFF812A46))
                : null,
          ),
        )]),
      body: showingAccount
          ? SafeArea(child: accountPage())
          : selected == 4
              ? SafeArea(child: ChatInbox(currentUserId: widget.account['id'].toString(), embedded: true))
              : loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: refresh, child: const Text('Retry'))]))) : SafeArea(child: IndexedStack(index: selected, children: [home(), appointmentsPage(), tasksPage(), groupsPage()])),
      floatingActionButton: showingAccount ? null : selected == 1 ? FloatingActionButton(onPressed: () => create('appointments'), child: const Icon(Icons.add)) : selected == 2 ? FloatingActionButton(onPressed: () => taskView == 1 ? createGroupTask() : create('tasks'), child: const Icon(Icons.add)) : selected == 3 ? FloatingActionButton(onPressed: () => create('groups'), child: const Icon(Icons.add)) : null,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!showingAccount && selected == 0) homeQuickActions(),
        NavigationBar(selectedIndex: selected, onDestinationSelected: (i) => setState(() { selected = i; showingAccount = false; }), destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'), NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Calendar'),
        NavigationDestination(icon: Icon(Icons.check_circle_outline), label: 'Tasks'), NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Groups'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
        ]),
      ]),
    );
  }
}





































