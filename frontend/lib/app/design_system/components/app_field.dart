import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class AppField extends StatelessWidget {
  const AppField({
    required this.label,
    this.controller,
    this.hint,
    this.description,
    this.error,
    this.enabled = true,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.textInputAction,
    this.keyboardType,
    this.autofillHints,
    this.maxLength,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? description;
  final String? error;
  final bool enabled;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final control = FTextFieldControl.managed(
      controller: controller,
      onChange: onChanged == null ? null : (value) => onChanged!(value.text),
    );
    if (obscureText) {
      return FTextField.password(
        control: control,
        size: FTextFieldSizeVariant.lg,
        label: Text(label),
        hint: hint,
        description: description == null ? null : Text(description!),
        error: error == null ? null : Text(error!),
        enabled: enabled,
        focusNode: focusNode,
        textInputAction: textInputAction ?? TextInputAction.next,
        keyboardType: keyboardType,
        onSubmit: onSubmitted,
        maxLength: maxLength,
        autofillHints: autofillHints ?? const [AutofillHints.password],
      );
    }
    return FTextField(
      control: control,
      size: FTextFieldSizeVariant.lg,
      label: Text(label),
      hint: hint,
      description: description == null ? null : Text(description!),
      error: error == null ? null : Text(error!),
      enabled: enabled,
      focusNode: focusNode,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      onSubmit: onSubmitted,
      maxLength: maxLength,
      autofillHints: autofillHints,
    );
  }
}
