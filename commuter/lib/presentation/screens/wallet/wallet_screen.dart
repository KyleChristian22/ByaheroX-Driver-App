import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../data/services/gcash_receipt_topup_service.dart';
import '../../../data/services/wallet_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../widgets/common/app_background.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _transactionSearchCtrl = TextEditingController();
  final _transactionSearchFocusNode = FocusNode();
  final Set<String> _cancellingTopupRequestIds = <String>{};
  static const int _transactionsPerPage = 5;
  DateTimeRange? _transactionDateRange;
  int _transactionPage = 0;

  @override
  void initState() {
    super.initState();
    _transactionSearchCtrl.addListener(_resetTransactionPage);
  }

  @override
  void dispose() {
    _transactionSearchCtrl.removeListener(_resetTransactionPage);
    _transactionSearchFocusNode.dispose();
    _transactionSearchCtrl.dispose();
    super.dispose();
  }

  void _resetTransactionPage() {
    if (_transactionPage == 0) return;
    setState(() => _transactionPage = 0);
  }

  void _leaveWallet(BuildContext context) {
    final auth = context.read<AuthViewModel>();
    context.go(auth.isGuest ? AppRouter.login : AppRouter.profile);
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    final userId = authViewModel.currentUser.id;

    if (authViewModel.isGuest) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leaveWallet(context);
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Wallet'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _leaveWallet(context),
            ),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Sign in to use your wallet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leaveWallet(context);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Wallet'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _leaveWallet(context),
          ),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('commuters')
              .doc(userId)
              .snapshots(),
          builder: (context, commuterSnapshot) {
            if (commuterSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final commuterData = commuterSnapshot.data?.data();
            final rfidCard = commuterData?['rfidCard']?.toString().trim() ?? '';

            if (rfidCard.isEmpty) {
              return _buildLockedWalletMessage();
            }

            return StreamBuilder<double>(
              stream: WalletService.balanceStream(userId),
              builder: (context, balanceSnapshot) {
                final balance = balanceSnapshot.data ?? 0.0;

                return Column(
                  children: [
                    _buildBalanceCard(
                      context,
                      balance,
                      userId,
                      rfidCard,
                      commuterData,
                    ),
                    _buildDiscountWalletNotice(context, commuterData),
                    Expanded(child: _buildTransactionList(userId)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLockedWalletMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Wallet locked',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You need to get an RFID card first to unlock your wallet.',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(
    BuildContext context,
    double balance,
    String userId,
    String rfidCard,
    Map<String, dynamic>? commuterData,
  ) {
    final rfidStatus =
        commuterData?['rfidStatus']?.toString().trim().toLowerCase() ??
        'active';

    return GlassSurface(
      margin: const EdgeInsets.fromLTRB(
        AppDimensions.md,
        AppDimensions.md,
        AppDimensions.md,
        0,
      ),
      padding: const EdgeInsets.all(AppDimensions.lg),
      backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.5),
      borderColor: AppColors.neonBlue.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Wallet Balance',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'PHP ${balance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (balance < 80)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Low balance, please top up soon',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          StreamBuilder<Map<String, dynamic>?>(
            stream: WalletService.blockingTopupRequestStream(userId),
            builder: (context, snapshot) {
              final pendingTopup = snapshot.data;
              final hasPendingTopup = pendingTopup != null;
              final isChecking =
                  snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData;
              final isTopUpDisabled = hasPendingTopup || isChecking;
              final pendingTopupId = pendingTopup?['id']?.toString() ?? '';
              final pendingTopupStatus = WalletService.topupStatusLabel(
                pendingTopup?['status']?.toString() ?? '',
              );
              final isCancelling =
                  pendingTopupId.isNotEmpty &&
                  _cancellingTopupRequestIds.contains(pendingTopupId);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: isTopUpDisabled
                        ? null
                        : () => _showTopUpSheet(context, userId, rfidCard),
                    icon: const Icon(Icons.receipt_long_outlined, size: 20),
                    label: Text(isChecking ? 'Checking...' : 'Top Up'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: 0.55,
                      ),
                      disabledForegroundColor: AppColors.primary.withValues(
                        alpha: 0.45,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (hasPendingTopup) ...[
                    const SizedBox(height: 8),
                    Text(
                      'You already have a top-up request: $pendingTopupStatus.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: pendingTopupId.isEmpty || isCancelling
                          ? null
                          : () => _cancelTopupRequest(
                              context,
                              commuterId: userId,
                              topupRequestId: pendingTopupId,
                            ),
                      icon: isCancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cancel_outlined, size: 18),
                      label: Text(
                        isCancelling ? 'Cancelling...' : 'Cancel Request',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          StreamBuilder<Map<String, dynamic>?>(
            stream: WalletService.blockingRfidDeactivationRequestStream(userId),
            builder: (context, snapshot) {
              final pendingRequest = snapshot.data;
              final hasPendingRequest = pendingRequest != null;
              final isChecking =
                  snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData;
              final effectiveRfidStatus = hasPendingRequest
                  ? 'deactivation_pending'
                  : rfidStatus;
              final isDeactivationPending =
                  effectiveRfidStatus == 'deactivation_pending';
              final isDeactivated = effectiveRfidStatus == 'deactivated';
              final canRequestDeactivation =
                  rfidCard.isNotEmpty &&
                  !isChecking &&
                  !hasPendingRequest &&
                  !isDeactivated;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRfidStatusNotice(
                    effectiveRfidStatus,
                    pendingRequest: pendingRequest,
                    isChecking: isChecking,
                  ),
                  if (effectiveRfidStatus != 'active' || isChecking)
                    const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: canRequestDeactivation
                        ? () => _confirmRfidDeactivation(
                            context,
                            userId,
                            rfidCard,
                          )
                        : null,
                    icon: const Icon(Icons.credit_card_off_outlined, size: 20),
                    label: Text(
                      isChecking
                          ? 'Checking Request...'
                          : isDeactivationPending
                          ? 'Deactivation Pending'
                          : isDeactivated
                          ? 'RFID Deactivated'
                          : 'Request RFID Deactivation',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white.withValues(
                        alpha: 0.55,
                      ),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRfidStatusNotice(
    String rfidStatus, {
    Map<String, dynamic>? pendingRequest,
    bool isChecking = false,
  }) {
    if (rfidStatus == 'active' && !isChecking) return const SizedBox.shrink();

    final isPending = rfidStatus == 'deactivation_pending' || isChecking;
    final isDeactivated = rfidStatus == 'deactivated';
    final color = isPending
        ? Colors.orange
        : isDeactivated
        ? AppColors.error
        : Colors.white;
    final icon = isPending
        ? Icons.hourglass_top_outlined
        : isDeactivated
        ? Icons.credit_card_off_outlined
        : Icons.info_outline;
    final title = isPending
        ? isChecking
              ? 'Checking RFID request'
              : 'RFID deactivation pending'
        : isDeactivated
        ? 'RFID deactivated'
        : 'RFID status: ${rfidStatus.replaceAll('_', ' ')}';
    final pendingStatus = pendingRequest?['status']?.toString() ?? 'pending';
    final message = isChecking
        ? 'Checking if you already have a pending deactivation request.'
        : isPending
        ? 'Your request is ${WalletService.rfidDeactivationStatusLabel(pendingStatus).toLowerCase()}.'
        : isDeactivated
        ? 'This RFID can no longer be used for fare payments.'
        : 'Please refresh if this status looks incorrect.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountWalletNotice(
    BuildContext context,
    Map<String, dynamic>? commuterData,
  ) {
    final status =
        commuterData?['discountStatus']?.toString().trim().toLowerCase() ??
        'none';
    final expiresAt = _toDateTime(commuterData?['discountExpiresAt']);
    final now = DateTime.now();
    final isApproved =
        status == 'approved' && expiresAt != null && expiresAt.isAfter(now);
    final isExpiringSoon = isApproved && expiresAt.difference(now).inDays <= 30;
    final isExpired =
        status == 'approved' && expiresAt != null && !expiresAt.isAfter(now);

    Color color;
    IconData icon;
    String title;
    String message;
    if (isExpiringSoon) {
      color = Colors.orange;
      icon = Icons.event_busy_outlined;
      title = 'Discount expiring soon';
      message =
          'Renew before ${_formatDate(expiresAt)} to keep discounted RFID fares.';
    } else if (isApproved) {
      color = AppColors.success;
      icon = Icons.verified_outlined;
      title = 'RFID discount active';
      message = 'Valid until ${_formatDate(expiresAt)}.';
    } else if (isExpired) {
      color = AppColors.error;
      icon = Icons.event_busy_outlined;
      title = 'Discount expired';
      message = 'RFID fares are regular until you apply again.';
    } else if (status == 'pending') {
      color = Colors.orange;
      icon = Icons.hourglass_top_outlined;
      title = 'Discount application pending';
      message = 'RFID fares stay regular until treasurer approval.';
    } else {
      color = AppColors.primary;
      icon = Icons.badge_outlined;
      title = 'No active RFID discount';
      message = 'Apply for Student, PWD, or Senior fare discount.';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppDimensions.md,
        AppDimensions.sm,
        AppDimensions.md,
        0,
      ),
      child: InkWell(
        onTap: () => context.go(AppRouter.discountApplication),
        borderRadius: BorderRadius.circular(12),
        child: GlassSurface(
          padding: const EdgeInsets.all(12),
          backgroundColor: color.withValues(alpha: 0.1),
          borderColor: color.withValues(alpha: 0.25),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'the expiry date';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  void _showTopUpSheet(BuildContext context, String userId, String rfidCard) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GlassSurface(
          padding: EdgeInsets.zero,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          backgroundColor: AppColors.surface.withValues(alpha: 0.38),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Top Up with GCash',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan the official GCash QR, complete payment, then upload the receipt.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Image.asset(
                        'assets/images/coop_gcash_qr.jpg',
                        width: 220,
                        height: 220,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _pickAndAnalyzeReceipt(
                              context,
                              userId,
                              rfidCard,
                              ImageSource.gallery,
                            );
                          },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _pickAndAnalyzeReceipt(
                              context,
                              userId,
                              rfidCard,
                              ImageSource.camera,
                            );
                          },
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndAnalyzeReceipt(
    BuildContext context,
    String userId,
    String rfidCard,
    ImageSource source,
  ) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      imageQuality: 55,
      maxWidth: 1000,
    );
    if (image == null || !context.mounted) return;

    final bytes = await image.readAsBytes();
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> preview;
    try {
      preview = await GcashReceiptTopupService.previewReceiptTopup(
        commuterId: userId,
        receiptBytes: bytes,
        mimeType: image.mimeType ?? 'image/jpeg',
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } on GcashReceiptTopupException catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.retryable
                ? '${error.message}. You can try uploading again.'
                : error.message,
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error'), backgroundColor: AppColors.error),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmedExtraction = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _ReceiptReviewDialog(receiptBytes: bytes, preview: preview),
    );

    if (confirmedExtraction == null || !context.mounted) return;
    await _submitReviewedReceipt(
      context,
      userId,
      rfidCard,
      bytes,
      image.mimeType ?? 'image/jpeg',
      confirmedExtraction,
    );
  }

  Future<void> _submitReviewedReceipt(
    BuildContext context,
    String userId,
    String rfidCard,
    List<int> bytes,
    String mimeType,
    Map<String, dynamic> confirmedExtraction,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await GcashReceiptTopupService.analyzeReceiptTopup(
        commuterId: userId,
        rfidCard: rfidCard,
        receiptBytes: Uint8List.fromList(bytes),
        mimeType: mimeType,
        confirmedExtraction: confirmedExtraction,
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_topUpResultMessage(result)),
          backgroundColor: Colors.orange,
        ),
      );
    } on GcashReceiptTopupException catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.retryable
                ? '${error.message}. You can try submitting again.'
                : error.message,
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error'), backgroundColor: AppColors.error),
      );
    }
  }

  String _topUpResultMessage(Map<String, dynamic> result) {
    final extracted = result['extracted'];
    final amount = extracted is Map
        ? extracted['totalAmountSent'] ?? extracted['amount']
        : null;
    final status = result['status']?.toString() ?? '';
    if (status == 'needs_review') {
      return 'Receipt submitted: PHP $amount is waiting for treasurer review';
    }
    return 'Receipt submitted: $status';
  }

  Future<void> _cancelTopupRequest(
    BuildContext context, {
    required String commuterId,
    required String topupRequestId,
    bool closeCurrentSheet = false,
  }) async {
    if (_cancellingTopupRequestIds.contains(topupRequestId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Top-Up Request'),
        content: const Text(
          'Cancel this pending top-up request? You can submit a new top-up after it is cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Request'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _cancellingTopupRequestIds.add(topupRequestId));
    try {
      await GcashReceiptTopupService.cancelTopupRequest(
        commuterId: commuterId,
        topupRequestId: topupRequestId,
      );

      if (!mounted) return;
      setState(() => _cancellingTopupRequestIds.remove(topupRequestId));
      if (closeCurrentSheet && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Top-up request cancelled')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _cancellingTopupRequestIds.remove(topupRequestId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _confirmRfidDeactivation(
    BuildContext context,
    String userId,
    String rfidCard,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Request RFID Deactivation'),
        content: Text(
          'Request deactivation for RFID $rfidCard? This protects your wallet if the card is lost. A dispatcher will review the request before the card is blocked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await WalletService.requestRfidDeactivation(
        commuterId: userId,
        rfidCard: rfidCard,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RFID deactivation request sent')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: AppColors.error),
      );
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Widget _buildTransactionList(String userId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: WalletService.transactionsStream(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    'Transaction history could not be loaded',
                    style: TextStyle(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final rawTransactions = (snapshot.data ?? [])
            .where((tx) => tx['type']?.toString() != 'commuter_cash_withdrawal')
            .toList();
        final hasRawTransactions = rawTransactions.isNotEmpty;

        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
          children: [
            Padding(
              padding: const EdgeInsets.only(
                bottom: AppDimensions.sm,
                left: AppDimensions.xs,
                top: AppDimensions.sm,
              ),
              child: Text(
                'Recent Transactions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _buildTransactionFilters(context),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _transactionSearchCtrl,
              builder: (context, value, _) {
                final transactions = _filterTransactions(rawTransactions);
                final totalPages = transactions.isEmpty
                    ? 1
                    : ((transactions.length - 1) ~/ _transactionsPerPage) + 1;
                final safePage = _transactionPage.clamp(0, totalPages - 1);
                if (safePage != _transactionPage) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _transactionPage = safePage);
                    }
                  });
                }
                final start = safePage * _transactionsPerPage;
                final end = (start + _transactionsPerPage) > transactions.length
                    ? transactions.length
                    : start + _transactionsPerPage;
                final visibleTransactions = transactions.sublist(start, end);

                return Column(
                  children: [
                    const SizedBox(height: AppDimensions.sm),
                    ...visibleTransactions.map(
                      (tx) => _buildTransactionTile(context, tx),
                    ),
                    if (!hasRawTransactions)
                      Padding(
                        padding: const EdgeInsets.all(AppDimensions.lg),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No transactions yet',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (transactions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppDimensions.lg),
                        child: Center(
                          child: Text(
                            'No matching transactions',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      ),
                    if (transactions.length > _transactionsPerPage)
                      _buildPaginationControls(
                        context: context,
                        currentPage: safePage,
                        totalPages: totalPages,
                        onPrevious: safePage == 0
                            ? null
                            : () => setState(() => _transactionPage--),
                        onNext: safePage >= totalPages - 1
                            ? null
                            : () => setState(() => _transactionPage++),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransactionFilters(BuildContext context) {
    final hasFilters =
        _transactionSearchCtrl.text.trim().isNotEmpty ||
        _transactionDateRange != null;
    final summary = hasFilters
        ? [
            if (_transactionSearchCtrl.text.trim().isNotEmpty)
              'Search: ${_transactionSearchCtrl.text.trim()}',
            if (_transactionDateRange != null)
              '${_shortDate(_transactionDateRange!.start)} - ${_shortDate(_transactionDateRange!.end)}',
          ].join(' | ')
        : 'Search and date filters';

    return Padding(
      padding: const EdgeInsets.only(top: AppDimensions.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => _showTransactionFilterSheet(context),
            icon: Icon(
              hasFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            label: const Text('Filter transactions'),
          ),
          const SizedBox(height: AppDimensions.xs),
          Text(
            summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls({
    required BuildContext context,
    required int currentPage,
    required int totalPages,
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.md),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.sm),
            child: Semantics(
              label: 'Page ${currentPage + 1} of $totalPages',
              child: Text(
                '${currentPage + 1} / $totalPages',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
            ),
          ),
        ],
      ),
    );
  }

  void _showTransactionFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: GlassSurface(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: EdgeInsets.only(
              left: AppDimensions.lg,
              right: AppDimensions.lg,
              top: AppDimensions.lg,
              bottom:
                  MediaQuery.viewInsetsOf(sheetContext).bottom +
                  AppDimensions.lg,
            ),
            borderRadius: AppDimensions.borderRadiusLg,
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                final dateLabel = _transactionDateRange == null
                    ? 'Choose date range'
                    : '${_shortDate(_transactionDateRange!.start)} - ${_shortDate(_transactionDateRange!.end)}';
                final hasFilters =
                    _transactionSearchCtrl.text.trim().isNotEmpty ||
                    _transactionDateRange != null;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Filter transactions',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppDimensions.lg),
                    TextField(
                      controller: _transactionSearchCtrl,
                      focusNode: _transactionSearchFocusNode,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: 'Reference or transaction ID',
                        hintText: 'Search ref or transaction ID',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.md),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 1),
                          ),
                          initialDateRange: _transactionDateRange,
                        );
                        if (picked != null) {
                          setState(() {
                            _transactionDateRange = picked;
                            _transactionPage = 0;
                          });
                          setSheetState(() {});
                        }
                      },
                      icon: const Icon(Icons.date_range),
                      label: Text(dateLabel),
                    ),
                    const SizedBox(height: AppDimensions.lg),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: hasFilters
                                ? () {
                                    _transactionSearchCtrl.clear();
                                    setState(() {
                                      _transactionDateRange = null;
                                      _transactionPage = 0;
                                    });
                                    setSheetState(() {});
                                  }
                                : null,
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: AppDimensions.sm),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.check),
                            label: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _filterTransactions(
    List<Map<String, dynamic>> transactions,
  ) {
    final query = _transactionSearchCtrl.text.trim().toLowerCase();
    return transactions.where((tx) {
      if (_transactionDateRange != null) {
        final createdAt = tx['createdAt'];
        if (createdAt is! Timestamp) return false;
        final date = createdAt.toDate();
        final start = DateTime(
          _transactionDateRange!.start.year,
          _transactionDateRange!.start.month,
          _transactionDateRange!.start.day,
        );
        final end = DateTime(
          _transactionDateRange!.end.year,
          _transactionDateRange!.end.month,
          _transactionDateRange!.end.day,
        ).add(const Duration(days: 1));
        if (date.isBefore(start) || !date.isBefore(end)) return false;
      }

      if (query.isEmpty) return true;
      final type = tx['type']?.toString() ?? '';
      final paymentMethod = tx['paymentMethod']?.toString() ?? '';
      final label = _transactionSearchLabel(type, paymentMethod);
      final amount = (tx['amount'] is num)
          ? (tx['amount'] as num).toStringAsFixed(2)
          : tx['amount']?.toString();
      final haystack = [
        tx['id'],
        type,
        label,
        paymentMethod,
        tx['status'],
        tx['note'],
        amount,
        tx['gcashReference'],
        tx['receiptImageHash'],
        tx['referenceNumber'],
        tx['referenceId'],
        tx['requestId'],
        tx['topupRequestId'],
        tx['transactionId'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(query);
    }).toList();
  }

  String _shortDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

  String _transactionSearchLabel(String type, String paymentMethod) {
    final isRfidReplacement = type == 'rfid_replace';
    final isTopUp =
        !isRfidReplacement &&
        (type == 'topup' ||
            type == 'regular_gcash_topup' ||
            type == 'initial_rfid_cash' ||
            paymentMethod.startsWith('rfid_') ||
            paymentMethod == 'ai_gcash_receipt');

    if (isRfidReplacement) return 'rfid replacement';
    if (type == 'rfid_deactivation_request') return 'rfid deactivation request';
    if (type == 'rfid_deactivation') return 'rfid deactivation';
    if (type == 'regular_gcash_topup') return 'gcash top up';
    if (type == 'initial_rfid_cash') return 'initial rfid balance';
    if (isTopUp)
      return paymentMethod.startsWith('rfid_') ? 'rfid top up' : 'top up';
    if (type == 'fare') return 'fare payment';
    return type;
  }

  Widget _buildTransactionTile(BuildContext context, Map<String, dynamic> tx) {
    final type = tx['type']?.toString() ?? '';
    final requestId = tx['requestId']?.toString().trim() ?? '';
    final isRfidDeactivation =
        type == 'rfid_deactivation_request' || type == 'rfid_deactivation';

    if (isRfidDeactivation && requestId.isNotEmpty) {
      return StreamBuilder<Map<String, dynamic>?>(
        stream: WalletService.rfidDeactivationRequestStream(requestId),
        builder: (context, snapshot) {
          final request = snapshot.data;
          final mergedTx = request == null
              ? tx
              : {
                  ...tx,
                  'status': request['status'] ?? tx['status'],
                  'rfidCard': request['rfidCard'] ?? tx['rfidCard'],
                  'requestedAt': request['requestedAt'] ?? tx['requestedAt'],
                  'reviewedAt': request['reviewedAt'] ?? tx['reviewedAt'],
                  'reviewedByName':
                      request['reviewedByName'] ?? tx['reviewedByName'],
                  'rejectionReason':
                      request['rejectionReason'] ?? tx['rejectionReason'],
                };
          return _buildTransactionTileContent(context, mergedTx);
        },
      );
    }

    return _buildTransactionTileContent(context, tx);
  }

  Widget _buildTransactionTileContent(
    BuildContext context,
    Map<String, dynamic> tx,
  ) {
    final type = tx['type']?.toString() ?? '';
    final paymentMethod = tx['paymentMethod']?.toString() ?? '';
    final note = tx['note']?.toString() ?? '';
    final gcashReference = tx['gcashReference']?.toString() ?? '';
    final status = tx['status']?.toString().trim().toLowerCase() ?? '';
    final amount = (tx['amount'] is num)
        ? (tx['amount'] as num).toDouble()
        : 0.0;
    final isRfidReplacement = type == 'rfid_replace';
    final isRfidDeactivationRequest = type == 'rfid_deactivation_request';
    final isRfidDeactivation = type == 'rfid_deactivation';
    final createdAt =
        (isRfidDeactivationRequest || isRfidDeactivation) &&
            tx['reviewedAt'] != null
        ? tx['reviewedAt']
        : (isRfidDeactivationRequest || isRfidDeactivation) &&
              tx['requestedAt'] != null
        ? tx['requestedAt']
        : tx['createdAt'];
    String dateStr = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      dateStr = '${dt.month}/${dt.day}/${dt.year}';
    }

    final isTopUp =
        !isRfidReplacement &&
        !isRfidDeactivationRequest &&
        !isRfidDeactivation &&
        (type == 'topup' ||
            type == 'regular_gcash_topup' ||
            type == 'initial_rfid_cash' ||
            paymentMethod.startsWith('rfid_') ||
            paymentMethod == 'ai_gcash_receipt');
    final isFare = type == 'fare';
    final isCreditedTopUp =
        isTopUp &&
        (status.isEmpty ||
            status == 'auto_approved' ||
            status == 'approved' ||
            status == 'succeeded' ||
            status == 'test');

    IconData icon;
    Color iconColor;
    String label;
    String subtitle = dateStr.isNotEmpty ? dateStr : 'Pending';

    if (isRfidReplacement) {
      icon = Icons.credit_card;
      iconColor = AppColors.primary;
      label = 'RFID Replacement';
      if (note.isNotEmpty) subtitle = note;
    } else if (isRfidDeactivationRequest || isRfidDeactivation) {
      icon = Icons.credit_card_off_outlined;
      iconColor = status == 'rejected'
          ? AppColors.error
          : status == 'approved'
          ? AppColors.success
          : Colors.orange;
      label = isRfidDeactivation ? 'RFID Deactivated' : 'RFID Deactivation';
      final statusLabel = WalletService.rfidDeactivationStatusLabel(status);
      final rejectionReason = tx['rejectionReason']?.toString() ?? '';
      if (rejectionReason.isNotEmpty) {
        subtitle =
            'Rejected: $rejectionReason${dateStr.isNotEmpty ? ' - $dateStr' : ''}';
      } else if (note.isNotEmpty) {
        subtitle =
            '$note - $statusLabel${dateStr.isNotEmpty ? ' - $dateStr' : ''}';
      } else {
        subtitle = '$statusLabel${dateStr.isNotEmpty ? ' - $dateStr' : ''}';
      }
    } else if (isTopUp) {
      icon = paymentMethod.startsWith('rfid_')
          ? Icons.credit_card
          : Icons.add_circle_outline;
      iconColor =
          status == 'rejected' ||
              status == 'canceled' ||
              status == 'cancelled' ||
              status == 'commuter_canceled' ||
              status == 'commuter_cancelled'
          ? AppColors.error
          : AppColors.success;
      label = paymentMethod.startsWith('rfid_') ? 'RFID Top Up' : 'Top Up';
      if (type == 'regular_gcash_topup') {
        label = 'GCash Top Up';
      } else if (type == 'initial_rfid_cash') {
        label = 'Initial RFID Balance';
      }
      final rejectionReason = tx['rejectionReason']?.toString() ?? '';
      final statusLabel = WalletService.topupStatusLabel(status);
      if (gcashReference.isNotEmpty) {
        subtitle =
            'Ref: $gcashReference${status.isNotEmpty ? ' - $statusLabel' : ''}';
        if (dateStr.isNotEmpty) subtitle = '$subtitle - $dateStr';
      }
      if (rejectionReason.isNotEmpty) {
        subtitle =
            'Rejected: $rejectionReason${dateStr.isNotEmpty ? ' - $dateStr' : ''}';
      } else if (note.isNotEmpty) {
        subtitle = '$note${dateStr.isNotEmpty ? ' - $dateStr' : ''}';
      } else if (status.isNotEmpty) {
        subtitle = '$statusLabel${dateStr.isNotEmpty ? ' - $dateStr' : ''}';
      }
    } else if (isFare) {
      icon = Icons.directions_bus_outlined;
      iconColor = AppColors.primary;
      label = 'Fare Payment';
    } else {
      icon = Icons.receipt_outlined;
      iconColor = Colors.grey;
      label = type;
    }

    final sign = isCreditedTopUp
        ? '+'
        : isRfidReplacement ||
              isRfidDeactivationRequest ||
              isRfidDeactivation ||
              (isTopUp && !isCreditedTopUp)
        ? ''
        : '-';

    return GlassSurface(
      margin: const EdgeInsets.only(bottom: AppDimensions.sm),
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.42),
            borderRadius: AppDimensions.borderRadiusSm,
            border: Border.all(color: iconColor.withValues(alpha: 0.22)),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        trailing: Text(
          '$sign PHP ${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isCreditedTopUp ? AppColors.success : AppColors.textPrimary,
          ),
        ),
        onTap: () => _showTransactionDetails(context, tx),
      ),
    );
  }

  void _showTransactionDetails(BuildContext context, Map<String, dynamic> tx) {
    final userId = context.read<AuthViewModel>().currentUser.id;
    final amount = (tx['amount'] is num)
        ? (tx['amount'] as num).toDouble()
        : 0.0;
    final type = tx['type']?.toString() ?? '';
    final paymentMethod = tx['paymentMethod']?.toString() ?? '';
    final status = tx['status']?.toString().trim().toLowerCase() ?? '';
    final topupRequestId = tx['topupRequestId']?.toString().trim() ?? '';
    final requestId = tx['requestId']?.toString().trim() ?? '';
    final isRfidDeactivation =
        type == 'rfid_deactivation_request' || type == 'rfid_deactivation';
    final isTopUp =
        !isRfidDeactivation &&
        (type == 'topup' ||
            type == 'regular_gcash_topup' ||
            type == 'initial_rfid_cash' ||
            paymentMethod.startsWith('rfid_') ||
            paymentMethod == 'ai_gcash_receipt');
    final isFare = type == 'fare';
    final canCancelTopup =
        isTopUp &&
        topupRequestId.isNotEmpty &&
        WalletService.isCancellableTopupStatus(status);
    final receiptImageSource = _firstDisplayValue([
      tx['receiptImagePath'],
      tx['receiptImageUrl'],
      tx['receiptUrl'],
      tx['proofImageUrl'],
      tx['imageUrl'],
      tx['downloadUrl'],
    ]);

    List<MapEntry<String, String>> rowsFor([Map<String, dynamic>? request]) {
      final effectiveStatus = isRfidDeactivation
          ? (request?['status']?.toString().trim().toLowerCase() ?? status)
          : status;
      return <MapEntry<String, String>>[
        MapEntry('Type', _transactionSearchLabel(type, paymentMethod)),
        MapEntry(
          'Status',
          isTopUp
              ? WalletService.topupStatusLabel(status)
              : isRfidDeactivation
              ? WalletService.rfidDeactivationStatusLabel(effectiveStatus)
              : _displayValue(tx['status']),
        ),
        MapEntry('Amount', 'PHP ${amount.toStringAsFixed(2)}'),
        MapEntry('Payment', _displayValue(tx['paymentMethod'])),
        if (isFare) ...[
          MapEntry('Driver', _displayValue(tx['driverName'])),
          MapEntry(
            'Jeepney',
            _firstDisplayValue([tx['plateNumber'], tx['jeepneyId']]),
          ),
          MapEntry('Booking ID', _displayValue(tx['bookingId'])),
          MapEntry('Trip Schedule', _displayValue(tx['tripScheduleId'])),
          MapEntry('Previous Balance', _displayMoney(tx['balanceBefore'])),
          MapEntry('Current Balance', _displayMoney(tx['balanceAfter'])),
          MapEntry('Paid At', _formatTimestamp(tx['createdAt'])),
        ] else if (isTopUp) ...[
          MapEntry('Reference', _displayValue(tx['gcashReference'])),
          MapEntry('Receiver', _displayValue(tx['gcashReceiverName'])),
          MapEntry('Receiver Number', _displayValue(tx['gcashReceiverNumber'])),
          MapEntry('Receipt Type', _displayValue(tx['receiptType'])),
          MapEntry('Paid At', _formatTimestamp(tx['extractedPaidAt'])),
          MapEntry('AI Confidence', _displayValue(tx['aiConfidence'])),
          MapEntry('Review Mode', _displayValue(tx['creditMode'])),
          MapEntry('Previous Balance', _displayMoney(tx['balanceBefore'])),
          MapEntry('Current Balance', _displayMoney(tx['balanceAfter'])),
          MapEntry('Submitted', _formatTimestamp(tx['createdAt'])),
          MapEntry('Approved', _formatTimestamp(tx['approvedAt'])),
          MapEntry('Rejected', _formatTimestamp(tx['rejectedAt'])),
          MapEntry('Cancelled', _formatTimestamp(tx['cancelledAt'])),
          MapEntry('Rejected Reason', _displayValue(tx['rejectionReason'])),
          MapEntry('Receipt Image', receiptImageSource),
        ] else if (isRfidDeactivation) ...[
          MapEntry(
            'RFID Card',
            _displayValue(request?['rfidCard'] ?? tx['rfidCard']),
          ),
          MapEntry(
            'Submitted',
            _formatTimestamp(request?['requestedAt'] ?? tx['createdAt']),
          ),
          MapEntry(
            'Reviewed',
            _formatTimestamp(request?['reviewedAt'] ?? tx['reviewedAt']),
          ),
          MapEntry(
            'Reviewed By',
            _displayValue(request?['reviewedByName'] ?? tx['reviewedByName']),
          ),
          MapEntry(
            'Rejected Reason',
            _displayValue(request?['rejectionReason'] ?? tx['rejectionReason']),
          ),
          MapEntry('Note', _displayValue(tx['note'])),
          MapEntry('Request ID', _displayValue(requestId)),
        ] else ...[
          MapEntry('Submitted', _formatTimestamp(tx['createdAt'])),
          MapEntry('Note', _displayValue(tx['note'])),
          MapEntry('Request ID', _displayValue(tx['requestId'])),
        ],
        MapEntry('Transaction ID', _displayValue(tx['id'])),
        MapEntry('Top-up Request ID', _displayValue(tx['topupRequestId'])),
      ].where((entry) => entry.value != '-').toList();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scrollController) => GlassSurface(
            padding: EdgeInsets.zero,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            backgroundColor: AppColors.surface.withValues(alpha: 0.38),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Transaction Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isTopUp) ...[
                _buildReceiptPreview(tx),
                const SizedBox(height: 16),
              ],
              if (isRfidDeactivation && requestId.isNotEmpty)
                StreamBuilder<Map<String, dynamic>?>(
                  stream: WalletService.rfidDeactivationRequestStream(
                    requestId,
                  ),
                  builder: (context, snapshot) {
                    return _buildTransactionDetailRows(rowsFor(snapshot.data));
                  },
                )
              else
                _buildTransactionDetailRows(rowsFor()),
              if (canCancelTopup) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _cancellingTopupRequestIds.contains(topupRequestId)
                      ? null
                      : () => _cancelTopupRequest(
                          ctx,
                          commuterId: userId,
                          topupRequestId: topupRequestId,
                          closeCurrentSheet: true,
                        ),
                  icon: _cancellingTopupRequestIds.contains(topupRequestId)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cancel_outlined),
                  label: Text(
                    _cancellingTopupRequestIds.contains(topupRequestId)
                        ? 'Cancelling...'
                        : 'Cancel Top-Up Request',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.error.withValues(alpha: 0.45),
                  ),
                ),
              ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionDetailRows(List<MapEntry<String, String>> rows) {
    return Column(
      children: rows
          .map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      row.key,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildReceiptPreview(Map<String, dynamic> tx) {
    return FutureBuilder<String?>(
      future: _resolveReceiptImageUrl(tx),
      builder: (context, snapshot) {
        Widget child;

        if (snapshot.connectionState == ConnectionState.waiting) {
          child = const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          final message = snapshot.hasError
              ? _receiptPreviewErrorMessage(snapshot.error)
              : 'No receipt image could be loaded for this transaction.';
          child = Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDimensions.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: AppDimensions.borderRadiusMd,
            ),
            child: Text(
              message,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          );
        } else {
          child = ClipRRect(
            borderRadius: AppDimensions.borderRadiusMd,
            child: Image.network(
              snapshot.data!,
              height: 260,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDimensions.md),
                color: AppColors.surfaceVariant,
                child: const Text(
                  'Receipt image could not be displayed.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Submitted Receipt',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: AppDimensions.sm),
            child,
          ],
        );
      },
    );
  }

  String _receiptPreviewErrorMessage(Object? error) {
    final text = error?.toString().toLowerCase() ?? '';

    if (text.contains('permission') ||
        text.contains('unauthorized') ||
        text.contains('403')) {
      return 'Receipt image exists, but Firebase Storage permission is blocking access.';
    }

    if (text.contains('object-not-found') || text.contains('not found')) {
      return 'Receipt image file was not found in storage.';
    }

    return 'Receipt image could not be loaded for this transaction.';
  }

  Future<String?> _resolveReceiptImageUrl(Map<String, dynamic> tx) async {
    final directSource = _receiptImageSourceFrom(tx);
    if (directSource != null) {
      return _receiptImageUrlFromSource(directSource);
    }

    final topupRequestId = tx['topupRequestId']?.toString().trim() ?? '';
    if (topupRequestId.isEmpty) return null;

    final topupDoc = await FirebaseFirestore.instance
        .collection('topup_requests')
        .doc(topupRequestId)
        .get();
    final topupData = topupDoc.data();
    if (topupData == null) return null;

    final requestSource = _receiptImageSourceFrom(topupData);
    if (requestSource == null) return null;

    return _receiptImageUrlFromSource(requestSource);
  }

  String? _receiptImageSourceFrom(Map<String, dynamic> data) {
    final fields = [
      data['receiptImagePath'],
      data['receiptImageUrl'],
      data['receiptUrl'],
      data['proofImageUrl'],
      data['imageUrl'],
      data['downloadUrl'],
    ];

    for (final field in fields) {
      final text = field?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }

    return null;
  }

  Future<String> _receiptImageUrlFromSource(String source) async {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return source;
    }

    final storage = FirebaseStorage.instance;
    if (source.startsWith('gs://')) {
      return storage.refFromURL(source).getDownloadURL();
    }

    return storage.ref(source).getDownloadURL();
  }

  String _displayValue(dynamic value) {
    if (value == null) return '-';
    if (value is num) return value.toString();
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  String _displayMoney(dynamic value) {
    if (value is num) return 'PHP ${value.toDouble().toStringAsFixed(2)}';
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null) return '-';
    return 'PHP ${parsed.toStringAsFixed(2)}';
  }

  String _firstDisplayValue(List<dynamic> values) {
    for (final value in values) {
      final display = _displayValue(value);
      if (display != '-') return display;
    }
    return '-';
  }

  String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) return '-';
    final dt = value.toDate();
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour}:$minute';
  }
}

class _ReceiptReviewDialog extends StatefulWidget {
  const _ReceiptReviewDialog({
    required this.receiptBytes,
    required this.preview,
  });

  final Uint8List receiptBytes;
  final Map<String, dynamic> preview;

  @override
  State<_ReceiptReviewDialog> createState() => _ReceiptReviewDialogState();
}

class _ReceiptReviewDialogState extends State<_ReceiptReviewDialog> {
  Map<String, dynamic> get _extracted {
    final value = widget.preview['extracted'];
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final validationErrors =
        (widget.preview['validationErrors'] as List?)?.cast<dynamic>() ?? [];
    final rows = <MapEntry<String, String>>[
      MapEntry('Receipt Type', _fieldText(_extracted['receiptType'])),
      MapEntry('Receiver', _fieldText(_extracted['receiverName'])),
      MapEntry('Receiver Number', _fieldText(_extracted['receiverNumber'])),
      MapEntry('Channel', _fieldText(_extracted['channelText'])),
      MapEntry('Currency', _fieldText(_extracted['currency'])),
      MapEntry('Amount', _moneyText(_extracted['amount'])),
      MapEntry(
        'Total Amount Sent',
        _moneyText(_extracted['totalAmountSent'] ?? _extracted['amount']),
      ),
      MapEntry('Ref No.', _fieldText(_extracted['referenceNumber'])),
      MapEntry('Paid At', _fieldText(_extracted['paidAt'])),
      MapEntry('Carbon Savings', _fieldText(_extracted['carbonSavingsText'])),
      MapEntry('Notes', _fieldText(_extracted['notes'])),
    ].where((row) => row.value != '-').toList();

    return AlertDialog(
      title: const Text('Review Top-up Details'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  widget.receiptBytes,
                  height: 320,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
              if (validationErrors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: validationErrors
                      .map(
                        (error) => Chip(
                          label: Text(
                            error.toString().replaceAll('_', ' '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: Colors.orange.withValues(
                            alpha: 0.12,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              ...rows.map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 124,
                        child: Text(
                          row.key,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.value,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Submit Top-up'),
        ),
      ],
    );
  }

  bool get _canSubmit {
    final amount = _numberValue(
      _extracted['totalAmountSent'] ?? _extracted['amount'],
    );
    final reference = _fieldText(_extracted['referenceNumber']);
    return amount != null && amount > 0 && reference != '-';
  }

  void _submit() {
    final amount = _numberValue(
      _extracted['totalAmountSent'] ?? _extracted['amount'],
    )!;
    final reference = _fieldText(_extracted['referenceNumber']);

    Navigator.of(context).pop({
      'isGcashReceipt': _extracted['isGcashReceipt'] == true,
      'receiptType': _emptyToNull(_fieldText(_extracted['receiptType'])),
      'receiverName': _emptyToNull(_fieldText(_extracted['receiverName'])),
      'receiverNumber': _emptyToNull(_fieldText(_extracted['receiverNumber'])),
      'channelText': _emptyToNull(_fieldText(_extracted['channelText'])),
      'currency': _emptyToNull(_fieldText(_extracted['currency'])),
      'amount': amount,
      'totalAmountSent': amount,
      'referenceNumber': reference,
      'paidAt': _emptyToNull(_fieldText(_extracted['paidAt'])),
      'carbonSavingsText': _emptyToNull(
        _fieldText(_extracted['carbonSavingsText']),
      ),
      'confidence': _extracted['confidence'] ?? 1,
      'notes': _emptyToNull(_fieldText(_extracted['notes'])),
    });
  }

  String _fieldText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _moneyText(dynamic value) {
    final amount = _numberValue(value);
    return amount == null ? '-' : 'PHP ${amount.toStringAsFixed(2)}';
  }

  double? _numberValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String? _emptyToNull(String value) {
    final text = value.trim();
    return text.isEmpty || text == '-' ? null : text;
  }
}
