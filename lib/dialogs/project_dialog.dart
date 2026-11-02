import 'package:flutter/material.dart';

class ProjectFormResult {
  ProjectFormResult(this.name, this.location, this.description, this.buildings);
  final String name;
  final String location;
  final String description;
  final List<String> buildings;
}

/// Create (with buildings) or edit a project.
Future<ProjectFormResult?> showProjectDialog(
  BuildContext context, {
  String name = '',
  String location = '',
  String description = '',
  bool editing = false,
}) {
  final nameC = TextEditingController(text: name);
  final locC = TextEditingController(text: location);
  final descC = TextEditingController(text: description);
  final bldC = TextEditingController(text: editing ? '' : 'Overall Site');
  final formKey = GlobalKey<FormState>();

  return showDialog<ProjectFormResult>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (!formKey.currentState!.validate()) return;
        Navigator.pop(
          ctx,
          ProjectFormResult(
            nameC.text,
            locC.text,
            descC.text,
            bldC.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
          ),
        );
      }

      return AlertDialog(
        title: Text(editing ? 'Edit project' : 'New project'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameC,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Project name', border: OutlineInputBorder()),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: locC,
                    decoration: const InputDecoration(
                        labelText: 'Location (optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descC,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Description (optional)', border: OutlineInputBorder()),
                  ),
                  if (!editing) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: bldC,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Buildings / areas — one per line',
                        helperText: 'You can add, rename or remove these later.',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: Text(editing ? 'Save' : 'Create project')),
        ],
      );
    },
  );
}
