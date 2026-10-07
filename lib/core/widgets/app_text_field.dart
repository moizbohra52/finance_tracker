import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Labelled form field. Validation errors appear on form submit and then
/// update live while the user corrects them.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.helperText,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? helperText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;

  /// Masks the input and adds a show/hide toggle (passwords).
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _isObscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      obscureText: _isObscured,
      enableSuggestions: !widget.obscureText,
      autocorrect: !widget.obscureText,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      validator: widget.validator,
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: widget.helperText,
        suffixIcon: widget.obscureText
            ? IconButton(
                tooltip: _isObscured ? 'Show password' : 'Hide password',
                icon: Icon(
                  _isObscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _isObscured = !_isObscured),
              )
            : null,
      ),
    );
  }
}
