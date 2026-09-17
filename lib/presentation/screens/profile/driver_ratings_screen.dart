import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/feedback_service.dart';
import '../../widgets/driver_app_background.dart';

class DriverRatingsScreen extends StatefulWidget {
  final String driverId;
  final bool isTagalog;

  const DriverRatingsScreen({
    super.key,
    required this.driverId,
    required this.isTagalog,
  });

  @override
  State<DriverRatingsScreen> createState() => _DriverRatingsScreenState();
}

class _DriverRatingsScreenState extends State<DriverRatingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTagalog = widget.isTagalog;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(isTagalog ? 'Mga Rating' : 'Ratings'),
      ),
      body: DriverAppBackground(
        safeArea: false,
        child: SafeArea(
          child: StreamBuilder<List<DriverFeedback>>(
            stream: FeedbackService.watchAllDriverFeedback(widget.driverId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _CenteredMessage(
                  message: isTagalog
                      ? 'Hindi ma-load ang ratings.'
                      : 'Could not load ratings.',
                  color: Colors.red.shade600,
                );
              }

              final ratings = snapshot.data ?? const <DriverFeedback>[];
              final filteredRatings = _filterRatings(ratings);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() => _searchText = value.trim());
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchText.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchText = '');
                                },
                              ),
                        hintText: isTagalog
                            ? 'Maghanap ayon sa petsa'
                            : 'Search by date',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryBlue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (ratings.isEmpty)
                    Expanded(
                      child: _CenteredMessage(
                        message: isTagalog
                            ? 'Wala pang ratings.'
                            : 'No ratings yet.',
                      ),
                    )
                  else if (filteredRatings.isEmpty)
                    Expanded(
                      child: _CenteredMessage(
                        message: isTagalog
                            ? 'Walang rating para sa petsang iyon.'
                            : 'No ratings match that date.',
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                        itemCount: filteredRatings.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return RatingCommentTile(
                            feedback: filteredRatings[index],
                            datePattern: 'MMM d, yyyy h:mm a',
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<DriverFeedback> _filterRatings(List<DriverFeedback> ratings) {
    final query = _searchText.toLowerCase();
    if (query.isEmpty) return ratings;

    return ratings.where((rating) {
      final createdAt = rating.createdAt;
      if (createdAt == null) return false;

      final searchableDate = [
        DateFormat('MMM d, yyyy h:mm a').format(createdAt),
        DateFormat('MMMM d, yyyy').format(createdAt),
        DateFormat('MM/dd/yyyy').format(createdAt),
        DateFormat('yyyy-MM-dd').format(createdAt),
      ].join(' ').toLowerCase();

      return searchableDate.contains(query);
    }).toList();
  }
}

class RatingCommentTile extends StatelessWidget {
  final DriverFeedback feedback;
  final String datePattern;

  const RatingCommentTile({
    super.key,
    required this.feedback,
    this.datePattern = 'MMM d, yyyy h:mm a',
  });

  @override
  Widget build(BuildContext context) {
    final date = feedback.createdAt == null
        ? ''
        : DateFormat(datePattern).format(feedback.createdAt!);
    final comment = feedback.comment.trim();
    final tags = feedback.tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RatingStars(rating: feedback.rating),
              const Spacer(),
              if (date.isNotEmpty)
                Text(
                  date,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags.map((tag) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(
                      color: AppTheme.primaryBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class RatingStars extends StatelessWidget {
  final int rating;

  const RatingStars({super.key, required this.rating});

  @override
  Widget build(BuildContext context) {
    final safeRating = rating.clamp(0, 5);

    return Row(
      children: List.generate(5, (index) {
        return Icon(
          index < safeRating ? Icons.star_rounded : Icons.star_border_rounded,
          size: 16,
          color: const Color(0xFFF59E0B),
        );
      }),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String message;
  final Color? color;

  const _CenteredMessage({
    required this.message,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color ?? Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
