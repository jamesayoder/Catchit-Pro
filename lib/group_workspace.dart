import 'task_stages.dart';
import 'package:flutter/material.dart';
import 'cloud.dart';

class GroupWorkspace extends StatefulWidget {
  final Map<String, dynamic> group;
  const GroupWorkspace({super.key, required this.group});
  @override
  State<GroupWorkspace> createState() => _GroupWorkspaceState();
}

class _GroupWorkspaceState extends State<GroupWorkspace> {
  final api = CloudApi();
  List<Map<String, dynamic>> members = [];
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> appointments = [];
  bool busy = true;
  String? error;
  String get id => widget.group['id'].toString();
  @override
  void initState() { super.initState(); reload(); }
  Future<void> reload() async {
    try {
      final result = await Future.wait([api.list('groups/$id/members'), api.request('GET', 'groups/$id/work')]);
      final work = Map<String, dynamic>.from(result[1] as Map);
      if (mounted) setState(() {
        members = (result[0] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
        tasks = (work['tasks'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
        appointments = (work['appointments'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
        busy = false; error = null;
      });
    } catch (e) { if (mounted) setState(() { busy = false; error = '$e'; }); }
  }
  Future<void> invite() async {
    String enteredEmail = '';
    final email = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Invite registered user'), content: TextField(keyboardType: TextInputType.emailAddress, onChanged: (value) => enteredEmail = value, decoration: const InputDecoration(labelText: 'Email address')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, enteredEmail.trim()), child: const Text('Send invitation'))],
    ));
    if (email == null || email.isEmpty) return;
    try { await api.add('groups/$id/invite', {'email': email}); await reload(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation sent'))); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Future<void> addItem(bool appointment) async {
    String enteredTitle = '';
    String? assignee;
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text(appointment ? 'Group appointment' : 'Group task'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(onChanged: (value) => enteredTitle = value, decoration: const InputDecoration(labelText: 'Title')),
        DropdownButtonFormField<String>(value: assignee, decoration: const InputDecoration(labelText: 'Assign to (optional)'), items: [const DropdownMenuItem(value: null, child: Text('Unassigned')),
          ...members.where((m) => m['state'] == 'accepted').map((m) => DropdownMenuItem(value: m['userId'].toString(), child: Text(m['name'].toString())))], onChanged: (v) => update(() => assignee = v))]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, {'title': enteredTitle.trim(), 'assigneeId': assignee}), child: const Text('Save'))],
    )));
    if (result == null || (result['title'] as String).isEmpty) return;
    final start = DateTime.now().toUtc().add(const Duration(hours: 1));
    try {
      await api.add('groups/$id/${appointment ? 'appointments' : 'tasks'}', appointment
        ? {...result, 'startsUtc': start.toIso8601String(), 'endsUtc': start.add(const Duration(hours: 1)).toIso8601String()}
        : {...result, 'description': '', 'dueUtc': null, 'isDone': false});
      await reload();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Future<void> changeStage(Map<String, dynamic> task, String stage) async {
    try {
      await saveTaskStage(api, 'groups/$id/tasks', task, stage);
      await reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.group['name'].toString()), actions: [IconButton(onPressed: reload, icon: const Icon(Icons.refresh))]),
    body: busy ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Text(error!)) : ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Members', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ...members.map((m) => ListTile(leading: const Icon(Icons.person_outline), title: Text(m['name'].toString()), subtitle: Text(m['state'].toString()))),
      if (widget.group['role'] == 'owner') OutlinedButton.icon(onPressed: invite, icon: const Icon(Icons.person_add_alt), label: const Text('Invite user')),
      const SizedBox(height: 16), const Text('Group tasks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ...tasks.map((task) => ListTile(
        leading: IconButton(
          tooltip: 'Advance task stage',
          icon: Icon(task['isDone'] == true ? Icons.check_circle : Icons.radio_button_unchecked),
          onPressed: () => changeStage(task, nextTaskStage(task)),
        ),
        title: Text(task['title'].toString()),
        subtitle: Text(taskStage(task)),
        trailing: PopupMenuButton<String>(
          tooltip: 'Set task stage',
          onSelected: (stage) => changeStage(task, stage),
          itemBuilder: (_) => [
            for (final stage in taskStages) PopupMenuItem(value: stage, child: Text(stage)),
          ],
        ),
      )),
      OutlinedButton.icon(onPressed: () => addItem(false), icon: const Icon(Icons.add), label: const Text('New group task')),
      const SizedBox(height: 16), const Text('Group appointments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ...appointments.map((a) => ListTile(leading: const Icon(Icons.event), title: Text(a['title'].toString()), subtitle: Text(a['startsUtc'].toString()))),
      OutlinedButton.icon(onPressed: () => addItem(true), icon: const Icon(Icons.add), label: const Text('New group appointment')),
    ]),
  );
}
