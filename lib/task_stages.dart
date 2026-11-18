import 'package:flutter/material.dart';
import 'cloud.dart';

const taskStages = ['Created', 'Started', 'In Process', 'Completed', 'Archive'];

String taskStage(Map<String, dynamic> task) {
  final stage = task['taskStage'];
  if (stage is String && taskStages.contains(stage)) return stage;
  return task['isDone'] == true ? 'Completed' : 'Created';
}

String nextTaskStage(Map<String, dynamic> task) =>
    taskStages[(taskStages.indexOf(taskStage(task)) + 1) % taskStages.length];

Widget taskStageField(String stage, ValueChanged<String> onChanged) =>
    DropdownButtonFormField<String>(
      initialValue: stage,
      decoration: const InputDecoration(labelText: 'Task stage'),
      items: [
        for (final value in taskStages)
          DropdownMenuItem(value: value, child: Text(value)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );

Future<void> saveTaskStage(
  CloudApi api, String resource, Map<String, dynamic> task, String stage,
) async {
  await api.request('PUT', "$resource/${task['id']}/stage", {
    'taskStage': stage,
    'expectedStage': taskStage(task),
  });
}