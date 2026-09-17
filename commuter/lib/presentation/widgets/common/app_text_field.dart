import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';

/// Custom text field for ByaheroX app
class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixIconTap;
  final String? suffixTooltip;
  final bool enabled;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;
  final FocusNode? focusNode;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixIconTap,
    this.suffixTooltip,
    this.enabled = true,
    this.maxLines = 1,
    this.inputFormatters,
    this.textInputAction,
    this.onFieldSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderRadius: AppDimensions.borderRadiusMd,
      borderSide: BorderSide(
        color: AppColors.surface.withValues(alpha: 0.46),
        width: 1.4,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: AppDimensions.borderRadiusMd,
      borderSide: BorderSide(
        color: AppColors.neonBlue.withValues(alpha: 0.92),
        width: AppDimensions.borderWidthThick,
      ),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: AppDimensions.borderRadiusMd,
      borderSide: const BorderSide(
        color: AppColors.error,
        width: AppDimensions.borderWidthThick,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppDimensions.sm),
        Semantics(
          textField: true,
          label: label,
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            validator: validator,
            onChanged: onChanged,
            onFieldSubmitted: onFieldSubmitted,
            enabled: enabled,
            maxLines: maxLines,
            inputFormatters: inputFormatters,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: enabled
                  ? AppColors.surface.withValues(alpha: 0.34)
                  : AppColors.surface.withValues(alpha: 0.22),
              enabledBorder: inputBorder,
              border: inputBorder,
              focusedBorder: focusedBorder,
              errorBorder: errorBorder,
              focusedErrorBorder: errorBorder,
              errorMaxLines: 3,
              prefixIcon: prefixIcon != null
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.34),
                          borderRadius: AppDimensions.borderRadiusSm,
                          border: Border.all(
                            color: AppColors.surface.withValues(alpha: 0.44),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          prefixIcon,
                          color: AppColors.primaryBlue,
                          semanticLabel: label,
                        ),
                      ),
                    )
                  : null,
              suffixIcon: suffixIcon != null
                  ? Tooltip(
                      message: suffixTooltip ?? 'Toggle visibility',
                      child: Semantics(
                        button: true,
                        label: suffixTooltip ?? 'Toggle visibility',
                        child: IconButton(
                          icon: Icon(suffixIcon, color: AppColors.textSecondary),
                          onPressed: onSuffixIconTap,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
