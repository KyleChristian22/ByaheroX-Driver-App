import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../data/services/ride_feedback_service.dart';
import 'common/app_background.dart';

const List<String> rideFeedbackTags = [
  'Safe driving',
  'Polite driver',
  'Clean jeep',
  'Smooth ride',
  'Fast trip',
  'Helpful driver',
  'Overcrowded',
  'Delayed',
  'Rude behavior',
  'Unsafe driving',
  'Jeep not clean',
  'Wrong route',
];

Future<bool?> showRideFeedbackSheet(
  BuildContext context, {
  required CompletedTrip trip,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RideFeedbackSheet(trip: trip),
  );
}

Future<void> showPostRideFeedbackPrompt(
  BuildContext context, {
  required CompletedTrip trip,
}) async {
  final wantsToRate = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        child: GlassSurface(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          borderRadius: AppDimensions.borderRadiusLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ride completed',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'How was your ride${trip.plateNumber.isEmpty ? '' : ' with ${trip.plateNumber}'}?',
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      icon: const Icon(Icons.star_border),
                      label: const Text('Rate Now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (wantsToRate != true || !context.mounted) return;
  await showRideFeedbackSheet(context, trip: trip);
}

class RideFeedbackSheet extends StatefulWidget {
  final CompletedTrip trip;

  const RideFeedbackSheet({super.key, required this.trip});

  @override
  State<RideFeedbackSheet> createState() => _RideFeedbackSheetState();
}

class _RideFeedbackSheetState extends State<RideFeedbackSheet> {
  final TextEditingController _commentController = TextEditingController();
  final Set<String> _selectedTags = <String>{};
  int _rating = 0;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1 || _rating > 5) {
      setState(() => _error = 'Please choose a rating first.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await RideFeedbackService.submitFeedback(
        RideFeedbackSubmission(
          trip: widget.trip,
          rating: _rating,
          comment: _commentController.text,
          tags: _selectedTags.toList(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _friendlyMessage(error);
      });
    }
  }

  String _friendlyMessage(Object error) {
    final text = error.toString().replaceFirst('Bad state: ', '');
    if (text.trim().isNotEmpty) return text;
    return 'Could not submit feedback. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final trip = widget.trip;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GlassSurface(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: EdgeInsets.zero,
        borderRadius: AppDimensions.borderRadiusLg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: AppDimensions.borderRadiusMd,
                    ),
                    child: const Icon(
                      Icons.rate_review_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rate your ride',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (trip.plateNumber.isNotEmpty) trip.plateNumber,
                            if (trip.driverName.isNotEmpty) trip.driverName,
                          ].join(' - '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final value = index + 1;
                  return IconButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                            _rating = value;
                            _error = null;
                          }),
                    icon: Icon(
                      value <= _rating ? Icons.star : Icons.star_border,
                      color: value <= _rating
                          ? const Color(0xFFF59E0B)
                          : AppColors.textTertiary,
                      size: 36,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Text(
                'Tags',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: rideFeedbackTags.map((tag) {
                  final selected = _selectedTags.contains(tag);
                  return FilterChip(
                    label: Text(tag),
                    selected: selected,
                    onSelected: _isSubmitting
                        ? null
                        : (value) {
                            setState(() {
                              if (value) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                          },
                    selectedColor: AppColors.primary.withValues(alpha: 0.14),
                    checkmarkColor: AppColors.primary,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentController,
                enabled: !_isSubmitting,
                minLines: 3,
                maxLines: 5,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: 'Optional comment',
                  hintText: 'Tell us more about the ride',
                  border: OutlineInputBorder(
                    borderRadius: AppDimensions.borderRadiusMd,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
