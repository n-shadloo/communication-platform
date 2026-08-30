import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';

class AppCheckboxRow extends StatelessWidget {
  const AppCheckboxRow({
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value,
    enabled: onChanged != null,
    child: Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged == null
            ? null
            : (next) => onChanged!(next ?? false),
        title: Text(label, style: context.tokens.typography.body),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
      ),
    ),
  );
}
