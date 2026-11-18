import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

const taskReminders = MethodChannel('catchit/task_reminders');
bool get taskRemindersSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Widget taskAlertField(int? minutes, ValueChanged<int?> onChanged) =>
    DropdownButtonFormField<int>(
      initialValue: minutes ?? 0,
      decoration: const InputDecoration(labelText: 'Alert'),
      items: [
        const DropdownMenuItem(value: 0, child: Text('No alert')),
        for (final value in [5, 10, 15, 30, 60, 120, 1440])
          DropdownMenuItem(value: value, child: Text('$value minutes before')),
      ],
      onChanged: (value) => onChanged(value == 0 ? null : value),
    );

Future<void> saveTaskAlert(String id, DateTime? due, int? minutes, String title) async {
  if (taskRemindersSupported) {
    await taskReminders.invokeMethod<void>('save', {
      'id': id, 'due': due?.millisecondsSinceEpoch, 'minutes': minutes, 'title': title,
    });
  }
}
