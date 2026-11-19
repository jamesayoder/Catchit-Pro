import 'package:flutter/material.dart';
import 'task_stages.dart';

class GroupTaskDialog extends StatefulWidget {
  const GroupTaskDialog({
    super.key,
    required this.task,
    required this.members,
    required this.insets,
    required this.constraints,
  });

  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> members;
  final EdgeInsets insets;
  final BoxConstraints constraints;

  @override
  State<GroupTaskDialog> createState() => _GroupTaskDialogState();
}

class _GroupTaskDialogState extends State<GroupTaskDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController notes;
  late DateTime? dueDate;
  late String? assigneeId;
  late String stage;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.task['title']?.toString() ?? '');
    notes = TextEditingController(text: widget.task['description']?.toString() ?? '');
    dueDate = DateTime.tryParse(widget.task['dueUtc']?.toString() ?? '')?.toLocal();
    assigneeId = widget.task['assigneeId']?.toString();
    stage = taskStage(widget.task);
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (mounted && picked != null) setState(() => dueDate = picked);
  }

  void save() {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop({
      'title': title.text.trim(),
      'description': notes.text.trim(),
      'dueUtc': dueDate?.toUtc().toIso8601String(),
      'assigneeId': assigneeId,
      'taskStage': stage,
      'expectedStage': taskStage(widget.task),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: widget.insets,
    constraints: widget.constraints,
    title: const Text('Edit group task'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: title,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Task title'),
              validator: (value) => value == null || value.trim().isEmpty ? 'Task title is required.' : null,
            ),
            TextFormField(
              controller: notes,
              minLines: 5,
              maxLines: 5,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            OutlinedButton(
              onPressed: pickDueDate,
              child: Text(dueDate == null
                  ? 'Set due date'
                  : 'Due: ${dueDate!.month}/${dueDate!.day}/${dueDate!.year}'),
            ),
            DropdownButtonFormField<String>(
              initialValue: widget.members.any((member) => member['userId']?.toString() == assigneeId)
                  ? assigneeId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Assigned member'),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('Unassigned')),
                ...widget.members.map((member) => DropdownMenuItem<String>(
                  value: member['userId'].toString(),
                  child: Text(member['displayName']?.toString() ?? member['email']?.toString() ?? 'Member'),
                )),
              ],
              onChanged: (value) => setState(() => assigneeId = value),
            ),
            taskStageField(stage, (value) => setState(() => stage = value)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: save, child: const Text('Save')),
    ],
  );
}
