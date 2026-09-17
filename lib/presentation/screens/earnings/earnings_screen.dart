import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/firestore_service.dart';
import '../../viewmodels/earnings_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/language_viewmodel.dart';
import '../../widgets/driver_app_background.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  late final EarningsViewModel _viewModel;
  String? _loadedDriverId;
  String? _loadedRecentFaresJeepneyId;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _viewModel = EarningsViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleEarningsSync(context.read<JeepneyViewModel>());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final jeepneyVM = context.read<JeepneyViewModel>();
    final driverId = jeepneyVM.driverId.trim();
    final jeepneyId = jeepneyVM.hasAssignedJeepney ? jeepneyVM.jeepneyId : null;
    await _viewModel.loadRecentFares(
      jeepneyId: jeepneyId,
      driverId: driverId.isEmpty ? null : driverId,
    );
  }

  void _scheduleEarningsSync(JeepneyViewModel jeepneyVM) {
    if (_syncScheduled) return;

    final driverId = jeepneyVM.driverId.trim();
    final jeepneyId =
        jeepneyVM.hasAssignedJeepney ? jeepneyVM.jeepneyId.trim() : null;

    final shouldLoadDriver = driverId.isNotEmpty && driverId != _loadedDriverId;
    final shouldLoadRecentFares = driverId.isNotEmpty &&
        (driverId != _loadedDriverId ||
            jeepneyId != _loadedRecentFaresJeepneyId);

    if (!shouldLoadDriver && !shouldLoadRecentFares) return;

    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncScheduled = false;

      final latestJeepneyVM = context.read<JeepneyViewModel>();
      final latestDriverId = latestJeepneyVM.driverId.trim();
      if (latestDriverId.isEmpty) return;

      final previousDriverId = _loadedDriverId;
      if (latestDriverId != previousDriverId) {
        _loadedDriverId = latestDriverId;
        _viewModel.loadDriverEarnings(latestDriverId);
        _viewModel.watchPayoutHistory(latestDriverId);
      }

      final latestJeepneyId = latestJeepneyVM.hasAssignedJeepney
          ? latestJeepneyVM.jeepneyId.trim()
          : null;
      if (latestDriverId != previousDriverId ||
          latestJeepneyId != _loadedRecentFaresJeepneyId) {
        _loadedRecentFaresJeepneyId = latestJeepneyId;
        _viewModel.loadRecentFares(
          jeepneyId: latestJeepneyId,
          driverId: latestDriverId,
        );
      }
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showWithdrawDialog() {
    final lang = context.read<LanguageViewModel>();
    final isTagalog = lang.isTagalog;
    final balance = _viewModel.earningsBalance;
    final activeRequest = _viewModel.activePayoutRequest;

    if (activeRequest != null) {
      _showSnack(isTagalog
          ? 'May pending payout request ka pa.'
          : 'You already have a pending payout request.');
      return;
    }

    if (balance <= 0) {
      _showSnack(
          isTagalog ? 'Walang pwedeng i-withdraw' : 'Nothing to withdraw');
      return;
    }

    final amountCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String? amountError;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            double? parsedAmount() {
              final normalized = amountCtrl.text.trim().replaceAll(',', '');
              if (normalized.isEmpty) return null;
              return double.tryParse(normalized);
            }

            void submit() {
              final amount = parsedAmount();
              if (amount == null || amount <= 0) {
                setSheetState(() {
                  amountError = isTagalog
                      ? 'Maglagay ng valid na halaga'
                      : 'Enter a valid amount';
                });
                return;
              }
              if (amount > balance) {
                setSheetState(() {
                  amountError = isTagalog
                      ? 'Mas mataas ito sa available balance'
                      : 'Amount exceeds available balance';
                });
                return;
              }

              Navigator.pop(ctx);
              _confirmWithdraw(amount);
            }

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
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
                    Text(
                      isTagalog ? 'Mag-withdraw' : 'Withdraw',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isTagalog
                          ? 'Ilagay ang halaga. Hindi ito mababawas hangga\'t hindi ina-approve ng treasurer.'
                          : 'Enter an amount. It will not be deducted until the treasurer approves it.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: isTagalog ? 'Halaga' : 'Amount',
                        prefixText: 'PHP ',
                        helperText:
                            'Available: PHP ${balance.toStringAsFixed(2)}',
                        errorText: amountError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (amountError != null) {
                          setSheetState(() => amountError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _viewModel.isSubmitting ? null : submit,
                        icon: _viewModel.isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send),
                        label: Text(
                          isTagalog ? 'Ipadala ang Request' : 'Send Request',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmWithdraw(double amount) {
    final lang = context.read<LanguageViewModel>();
    final jeepneyVM = context.read<JeepneyViewModel>();
    final isTagalog = lang.isTagalog;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTagalog ? 'Kumpirmahin' : 'Confirm Request'),
        content: Text(isTagalog
            ? 'Ipadala ang cash payout request na PHP ${amount.toStringAsFixed(2)}? Hindi ito mababawas hangga\'t hindi approved.'
            : 'Send a cash payout request for PHP ${amount.toStringAsFixed(2)}? This will not be deducted until approved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isTagalog ? 'Kanselahin' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isTagalog ? 'Ipadala' : 'Send Request'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true || !mounted) return;

      final success = await _viewModel.submitPayoutRequest(
        driverId: jeepneyVM.driverId,
        amount: amount,
      );

      if (!mounted) return;
      _showSnack(success
          ? (isTagalog
              ? 'Naipasa ang cash payout request'
              : 'Cash payout request submitted')
          : (isTagalog ? 'Nabigo ang pag-withdraw' : 'Withdrawal failed'));
    });
  }

  Future<void> _cancelActivePayout(
    Map<String, dynamic> payout,
    bool isTagalog,
  ) async {
    final payoutId = payout['id']?.toString().trim() ?? '';
    if (payoutId.isEmpty) {
      _showSnack(isTagalog
          ? 'Hindi mahanap ang payout request.'
          : 'Could not find the payout request.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTagalog ? 'Kanselahin ang Request?' : 'Cancel Request?'),
        content: Text(isTagalog
            ? 'Sigurado ka bang gusto mong kanselahin ang cash payout request na ito?'
            : 'Are you sure you want to cancel this cash payout request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isTagalog ? 'Hindi' : 'No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isTagalog ? 'Kanselahin' : 'Cancel Request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await _viewModel.cancelPayoutRequest(payoutId: payoutId);
    if (!mounted) return;
    _showSnack(success
        ? (isTagalog
            ? 'Nakansela ang payout request'
            : 'Payout request cancelled')
        : (isTagalog
            ? 'Nabigo ang pagkansela ng request'
            : 'Could not cancel payout request'));
  }

  @override
  Widget build(BuildContext context) {
    final jeepneyVM = context.watch<JeepneyViewModel>();
    final lang = context.watch<LanguageViewModel>();
    final isTagalog = lang.isTagalog;
    _scheduleEarningsSync(jeepneyVM);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(isTagalog ? 'Kita' : 'Wallet'),
      ),
      body: DriverAppBackground(
        safeArea: false,
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (_viewModel.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildEarningsCard(isTagalog),
                  const SizedBox(height: 24),
                  if (_viewModel.activePayoutRequest != null) ...[
                    _buildActivePayoutRequest(
                      _viewModel.activePayoutRequest!,
                      isTagalog,
                    ),
                    const SizedBox(height: 24),
                  ],
                  _buildRecentEarnings(isTagalog),
                  const SizedBox(height: 24),
                  _buildPayoutHistory(isTagalog),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEarningsCard(bool isTagalog) {
    final balance = _viewModel.earningsBalance;
    final hasActivePayout = _viewModel.hasActivePayoutRequest;
    return DriverGlassSurface(
      padding: EdgeInsets.zero,
      backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.68),
      borderColor: AppTheme.accentBlue.withValues(alpha: 0.42),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryBlue.withValues(alpha: 0.62),
              AppTheme.darkBlue.withValues(alpha: 0.68),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.white70, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    isTagalog ? 'Magagamit na Kita' : 'Available Balance',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '₱${balance.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: balance > 0 && !hasActivePayout
                      ? _showWithdrawDialog
                      : null,
                  icon: Icon(
                    hasActivePayout ? Icons.hourglass_empty : Icons.send,
                    size: 18,
                  ),
                  label: Text(
                    hasActivePayout
                        ? (isTagalog
                            ? 'May Pending Request'
                            : 'Request Pending')
                        : (isTagalog
                            ? 'Cash Payout Request'
                            : 'Request Cash Payout'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivePayoutRequest(
    Map<String, dynamic> payout,
    bool isTagalog,
  ) {
    final amount = (payout['amount'] as num?)?.toDouble() ?? 0;
    final requestedAt = payout['requestedAt'];
    final status =
        payout['status']?.toString().trim().toLowerCase() ?? 'requested';

    var dateText = '';
    if (requestedAt is Timestamp) {
      final date = requestedAt.toDate();
      dateText =
          '${date.month}/${date.day}/${date.year} ${_formatClockTime(date)}';
    }

    return DriverGlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hourglass_empty,
                  color: Colors.orange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTagalog ? 'Pending Cash Payout' : 'Pending Cash Payout',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTagalog
                          ? 'Magiging available ulit ang request kapag nakansela, na-reject, o na-approve.'
                          : 'New requests unlock after this is cancelled, rejected, or approved.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _payoutInfoRow(
            isTagalog ? 'Halaga' : 'Amount',
            'PHP ${amount.toStringAsFixed(2)}',
          ),
          if (dateText.isNotEmpty)
            _payoutInfoRow(
              isTagalog ? 'Na-request' : 'Requested',
              dateText,
            ),
          _payoutInfoRow(
            isTagalog ? 'Status' : 'Status',
            _payoutStatusLabel(status, isTagalog),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _viewModel.isSubmitting
                  ? null
                  : () => _cancelActivePayout(payout, isTagalog),
              icon: _viewModel.isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.close),
              label: Text(isTagalog ? 'Kanselahin' : 'Cancel Request'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _payoutInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _formatClockTime(DateTime date) {
    final hour = date.hour == 0
        ? 12
        : date.hour > 12
            ? date.hour - 12
            : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _payoutStatusLabel(String status, bool isTagalog) {
    switch (status) {
      case 'paid':
      case 'completed':
        return isTagalog ? 'Na-approve' : 'Approved';
      case 'rejected':
      case 'failed':
        return isTagalog ? 'Tinanggihan' : 'Rejected';
      case 'cancelled':
      case 'canceled':
        return isTagalog ? 'Nakansela' : 'Cancelled';
      default:
        return isTagalog ? 'Hinihintay' : 'Requested';
    }
  }

  Widget _buildRecentEarnings(bool isTagalog) {
    final fares = _viewModel.recentFares;
    final previewFares = fares.take(3).toList();
    final hasRawFares = _viewModel.recentFares.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isTagalog ? 'Kasaysayan ng RFID Bayad' : 'RFID Payment History',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (fares.isNotEmpty)
              Text(
                '${fares.length} tx',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!hasRawFares)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  isTagalog ? 'Wala pang RFID payment' : 'No RFID payments yet',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          )
        else
          ...previewFares.map((f) => _buildFareItem(f, isTagalog)),
        if (fares.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildViewAllButton(
            label: isTagalog ? 'Tingnan lahat' : 'View All',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RfidPaymentHistoryScreen(
                  fares: _viewModel.recentFares,
                  isTagalog: isTagalog,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFareItem(Map<String, dynamic> fare, bool isTagalog) {
    final amount = (fare['amount'] as num?)?.toDouble() ?? 0;
    final name = fare['commuterName']?.toString() ?? 'Unknown';
    final transactionId = fare['id']?.toString() ?? '';
    final rfidTag = fare['rfidTag']?.toString() ?? '';
    final balanceBefore = (fare['balanceBefore'] as num?)?.toDouble();
    final balanceAfter = (fare['balanceAfter'] as num?)?.toDouble();
    final createdAt = fare['createdAt'] as dynamic;
    final plateNumber = fare['plateNumber']?.toString() ?? '';
    final scheduleDate = fare['scheduleDate']?.toString() ?? '';
    final commuterId = fare['commuterId']?.toString() ?? '';
    final bookingId = fare['bookingId']?.toString() ?? '';
    final tripScheduleId = fare['tripScheduleId']?.toString() ?? '';

    String dateStr = '';
    DateTime? createdDt;
    if (createdAt is Timestamp) {
      createdDt = createdAt.toDate();
      dateStr =
          '${createdDt.month}/${createdDt.day} ${createdDt.hour.toString().padLeft(2, '0')}:${createdDt.minute.toString().padLeft(2, '0')}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _showFareTransactionDetail(
          isTagalog: isTagalog,
          amount: amount,
          commuterName: name,
          commuterId: commuterId,
          rfidTag: rfidTag,
          balanceBefore: balanceBefore,
          balanceAfter: balanceAfter,
          transactionId: transactionId,
          createdDt: createdDt,
          plateNumber: plateNumber,
          scheduleDate: scheduleDate,
          bookingId: bookingId,
          tripScheduleId: tripScheduleId,
        ),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.lightBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.contactless,
            color: AppTheme.primaryBlue,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'PHP ${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.lightBlue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'RFID',
                style: TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          [
            name,
            if (dateStr.isNotEmpty) dateStr,
            if (plateNumber.isNotEmpty) plateNumber,
            if (rfidTag.isNotEmpty) 'RFID: $rfidTag',
            if (transactionId.isNotEmpty) 'TX: $transactionId',
            if (balanceAfter != null)
              'Wallet after: PHP ${balanceAfter.toStringAsFixed(2)}',
          ].join(' - '),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ),
    );
  }

  void _showFareTransactionDetail({
    required bool isTagalog,
    required double amount,
    required String commuterName,
    required String commuterId,
    required String rfidTag,
    required double? balanceBefore,
    required double? balanceAfter,
    required String transactionId,
    required DateTime? createdDt,
    required String plateNumber,
    required String scheduleDate,
    required String bookingId,
    required String tripScheduleId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              Text(
                transactionId.isNotEmpty ? 'TX: $transactionId' : 'TX: ---',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 4),
              Text(
                'PHP ${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _detailRow(Icons.person_outline,
                  isTagalog ? 'Pasahero' : 'Commuter', commuterName),
              if (commuterId.isNotEmpty)
                _detailRow(Icons.badge_outlined, 'Commuter ID', commuterId),
              if (rfidTag.isNotEmpty)
                _detailRow(Icons.contactless, 'RFID Tag', rfidTag),
              if (balanceBefore != null)
                _detailRow(
                  Icons.account_balance_wallet_outlined,
                  isTagalog ? 'Bago' : 'Wallet Before',
                  'PHP ${balanceBefore.toStringAsFixed(2)}',
                ),
              if (balanceAfter != null)
                _detailRow(
                  Icons.account_balance_wallet,
                  isTagalog ? 'Pagkatapos' : 'Wallet After',
                  'PHP ${balanceAfter.toStringAsFixed(2)}',
                ),
              if (createdDt != null)
                _detailRow(
                    Icons.access_time,
                    isTagalog ? 'Petsa at Oras' : 'Date & Time',
                    '${createdDt.month}/${createdDt.day}/${createdDt.year} '
                    '${createdDt.hour.toString().padLeft(2, '0')}:${createdDt.minute.toString().padLeft(2, '0')}'),
              if (plateNumber.isNotEmpty)
                _detailRow(Icons.directions_bus, 'Plate #', plateNumber),
              if (scheduleDate.isNotEmpty)
                _detailRow(Icons.calendar_today,
                    isTagalog ? 'Araw ng Biyahe' : 'Trip Date', scheduleDate),
              if (tripScheduleId.isNotEmpty)
                _detailRow(Icons.event_note, 'Schedule ID', tripScheduleId),
              if (bookingId.isNotEmpty)
                _detailRow(Icons.receipt_long, 'Booking ID', bookingId),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutHistory(bool isTagalog) {
    final payouts = _viewModel.payoutHistory;
    final previewPayouts = payouts.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isTagalog ? 'Kasaysayan ng Payout' : 'Payout History',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (payouts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  isTagalog ? 'Wala pang payout' : 'No payouts yet',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          )
        else
          ...previewPayouts.map((p) => _buildPayoutItem(p, isTagalog)),
        if (payouts.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildViewAllButton(
            label: isTagalog ? 'Tingnan lahat' : 'View All',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PayoutHistoryScreen(
                  payouts: _viewModel.payoutHistory,
                  driverId: _loadedDriverId ?? '',
                  isTagalog: isTagalog,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildViewAllButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: Text(label),
      ),
    );
  }

  Widget _buildPayoutItem(Map<String, dynamic> payout, bool isTagalog) {
    final amount = (payout['amount'] as num?)?.toDouble() ?? 0;
    final status = payout['status']?.toString() ?? 'processing';
    final requestedAt = payout['requestedAt'] as dynamic;
    final reviewedAt = payout['reviewedAt'] as dynamic;
    final paidAt = payout['paidAt'] as dynamic;
    final rejectionReason = payout['rejectionReason']?.toString().trim() ?? '';

    String dateStr = '';
    if (requestedAt is Timestamp) {
      final dt = requestedAt.toDate();
      dateStr = '${dt.month}/${dt.day}';
    }

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'completed':
      case 'paid':
        statusColor = Colors.green;
        statusLabel = isTagalog ? 'Na-approve' : 'Approved';
        break;
      case 'failed':
      case 'rejected':
        statusColor = Colors.red;
        statusLabel = isTagalog ? 'Tinanggihan' : 'Rejected';
        break;
      case 'cancelled':
      case 'canceled':
        statusColor = Colors.grey;
        statusLabel = isTagalog ? 'Nakansela' : 'Cancelled';
        break;
      default:
        statusColor = Colors.orange;
        statusLabel = isTagalog ? 'Hinihintay' : 'Requested';
    }

    DateTime? reviewedDate;
    if (paidAt is Timestamp) {
      reviewedDate = paidAt.toDate();
    } else if (reviewedAt is Timestamp) {
      reviewedDate = reviewedAt.toDate();
    }

    final isPaid = status == 'paid' || status == 'completed';
    final isRejected = status == 'rejected' || status == 'failed';
    final isCancelled = status == 'cancelled' || status == 'canceled';
    final detailParts = <String>[
      if (dateStr.isNotEmpty)
        isTagalog ? 'Na-request $dateStr' : 'Requested $dateStr',
      'Cash payout',
      if (reviewedDate != null && isPaid)
        '${isTagalog ? 'Bayad' : 'Paid'} ${reviewedDate.month}/${reviewedDate.day}',
      if (reviewedDate != null && isRejected)
        '${isTagalog ? 'Tinanggihan' : 'Rejected'} ${reviewedDate.month}/${reviewedDate.day}',
      if (isCancelled) (isTagalog ? 'Nakansela' : 'Cancelled'),
      if (rejectionReason.isNotEmpty && isRejected) rejectionReason,
    ];
    final amountPrefix = isPaid ? '-' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isPaid
                ? Icons.check_circle
                : isRejected
                    ? Icons.cancel
                    : isCancelled
                        ? Icons.block
                        : Icons.hourglass_empty,
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text('$amountPrefix PHP ${amount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(detailParts.join(' - ')),
        onTap: () => _showPayoutDetails(context, payout, isTagalog),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(statusLabel,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              )),
        ),
      ),
    );
  }
}

class RfidPaymentHistoryScreen extends StatefulWidget {
  const RfidPaymentHistoryScreen({
    super.key,
    required this.fares,
    required this.isTagalog,
  });

  final List<Map<String, dynamic>> fares;
  final bool isTagalog;

  @override
  State<RfidPaymentHistoryScreen> createState() =>
      _RfidPaymentHistoryScreenState();
}

class _RfidPaymentHistoryScreenState extends State<RfidPaymentHistoryScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fares = _filteredFares();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isTagalog ? 'Lahat ng RFID Bayad' : 'All RFID Payments',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HistoryFilters(
            searchCtrl: _searchCtrl,
            dateRange: _dateRange,
            isTagalog: widget.isTagalog,
            hintText:
                widget.isTagalog ? 'Hanapin ang ref o ID' : 'Search ref or ID',
            onDateRangeChanged: (range) => setState(() => _dateRange = range),
            onClear: () {
              _searchCtrl.clear();
              setState(() => _dateRange = null);
            },
          ),
          const SizedBox(height: 12),
          if (fares.isEmpty)
            _HistoryEmptyState(
              text: widget.isTagalog
                  ? 'Walang tugmang RFID payment'
                  : 'No matching RFID payments',
            )
          else
            ...fares.map((fare) => _RfidHistoryItem(fare: fare)),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredFares() {
    final query = _searchCtrl.text.trim().toLowerCase();
    return widget.fares.where((fare) {
      if (_dateRange != null) {
        final createdAt = fare['createdAt'];
        if (createdAt is! Timestamp) return false;
        if (!_dateInRange(createdAt.toDate(), _dateRange!)) return false;
      }

      if (query.isEmpty) return true;
      final haystack = [
        fare['id'],
        fare['transactionId'],
        fare['referenceId'],
        fare['gcashReference'],
        fare['bookingId'],
        fare['commuterName'],
        fare['commuterId'],
        fare['rfidTag'],
        fare['plateNumber'],
        fare['tripScheduleId'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(query);
    }).toList();
  }
}

class PayoutHistoryScreen extends StatefulWidget {
  const PayoutHistoryScreen({
    super.key,
    required this.payouts,
    required this.driverId,
    required this.isTagalog,
  });

  final List<Map<String, dynamic>> payouts;
  final String driverId;
  final bool isTagalog;

  @override
  State<PayoutHistoryScreen> createState() => _PayoutHistoryScreenState();
}

class _PayoutHistoryScreenState extends State<PayoutHistoryScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isTagalog ? 'Lahat ng Payout' : 'All Payouts'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: widget.driverId.trim().isEmpty
            ? Stream.value(widget.payouts)
            : FirestoreService.driverPayoutsStream(widget.driverId),
        builder: (context, snapshot) {
          final sourcePayouts = snapshot.data ?? widget.payouts;
          final payouts = _filteredPayouts(sourcePayouts);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HistoryFilters(
                searchCtrl: _searchCtrl,
                dateRange: _dateRange,
                isTagalog: widget.isTagalog,
                hintText: widget.isTagalog
                    ? 'Hanapin ang status o ID'
                    : 'Search status or ID',
                onDateRangeChanged: (range) =>
                    setState(() => _dateRange = range),
                onClear: () {
                  _searchCtrl.clear();
                  setState(() => _dateRange = null);
                },
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  sourcePayouts.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (payouts.isEmpty)
                _HistoryEmptyState(
                  text: widget.isTagalog
                      ? 'Walang tugmang payout'
                      : 'No matching payouts',
                )
              else
                ...payouts.map(
                  (payout) => _PayoutHistoryItem(
                    payout: payout,
                    isTagalog: widget.isTagalog,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _filteredPayouts(
    List<Map<String, dynamic>> payouts,
  ) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return payouts.where((payout) {
      final requestedAt = payout['requestedAt'];
      if (_dateRange != null) {
        if (requestedAt is! Timestamp) return false;
        if (!_dateInRange(requestedAt.toDate(), _dateRange!)) return false;
      }

      if (query.isEmpty) return true;
      final haystack = [
        payout['id'],
        payout['payoutId'],
        payout['driverId'],
        payout['method'],
        payout['status'],
        payout['reviewedBy'],
        payout['rejectionReason'],
        payout['amount'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(query);
    }).toList();
  }
}

class _HistoryFilters extends StatelessWidget {
  const _HistoryFilters({
    required this.searchCtrl,
    required this.dateRange,
    required this.isTagalog,
    required this.hintText,
    required this.onDateRangeChanged,
    required this.onClear,
  });

  final TextEditingController searchCtrl;
  final DateTimeRange? dateRange;
  final bool isTagalog;
  final String hintText;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final dateLabel = dateRange == null
        ? (isTagalog ? 'Petsa' : 'Date')
        : '${_shortDate(dateRange!.start)} - ${_shortDate(dateRange!.end)}';
    final shouldShowClear = searchCtrl.text.isNotEmpty || dateRange != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchCtrl,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: dateRange,
                  );
                  if (picked != null) onDateRangeChanged(picked);
                },
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(dateLabel),
              ),
            ),
            if (shouldShowClear)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ],
    );
  }
}

class _RfidHistoryItem extends StatelessWidget {
  const _RfidHistoryItem({required this.fare});

  final Map<String, dynamic> fare;

  @override
  Widget build(BuildContext context) {
    final amount = (fare['amount'] as num?)?.toDouble() ?? 0;
    final name = fare['commuterName']?.toString() ?? 'Unknown';
    final transactionId = fare['id']?.toString() ?? '';
    final rfidTag = fare['rfidTag']?.toString() ?? '';
    final balanceAfter = (fare['balanceAfter'] as num?)?.toDouble();
    final createdAt = fare['createdAt'];
    final plateNumber = fare['plateNumber']?.toString() ?? '';

    String dateStr = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      dateStr =
          '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.lightBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.contactless,
            color: AppTheme.primaryBlue,
            size: 20,
          ),
        ),
        title: Text(
          'PHP ${amount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [
            name,
            if (dateStr.isNotEmpty) dateStr,
            if (plateNumber.isNotEmpty) plateNumber,
            if (rfidTag.isNotEmpty) 'RFID: $rfidTag',
            if (transactionId.isNotEmpty) 'TX: $transactionId',
            if (balanceAfter != null)
              'Wallet after: PHP ${balanceAfter.toStringAsFixed(2)}',
          ].join(' - '),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.lightBlue,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'RFID',
            style: TextStyle(
              color: AppTheme.primaryBlue,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _PayoutHistoryItem extends StatelessWidget {
  const _PayoutHistoryItem({
    required this.payout,
    required this.isTagalog,
  });

  final Map<String, dynamic> payout;
  final bool isTagalog;

  @override
  Widget build(BuildContext context) {
    final amount = (payout['amount'] as num?)?.toDouble() ?? 0;
    final status = payout['status']?.toString() ?? 'processing';
    final requestedAt = payout['requestedAt'];
    final reviewedAt = payout['reviewedAt'];
    final paidAt = payout['paidAt'];
    final rejectionReason = payout['rejectionReason']?.toString().trim() ?? '';

    String dateStr = '';
    if (requestedAt is Timestamp) {
      final dt = requestedAt.toDate();
      dateStr = '${dt.month}/${dt.day}';
    }

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'completed':
      case 'paid':
        statusColor = Colors.green;
        statusLabel = isTagalog ? 'Na-approve' : 'Approved';
        break;
      case 'failed':
      case 'rejected':
        statusColor = Colors.red;
        statusLabel = isTagalog ? 'Tinanggihan' : 'Rejected';
        break;
      case 'cancelled':
      case 'canceled':
        statusColor = Colors.grey;
        statusLabel = isTagalog ? 'Nakansela' : 'Cancelled';
        break;
      default:
        statusColor = Colors.orange;
        statusLabel = isTagalog ? 'Hinihintay' : 'Requested';
    }

    DateTime? reviewedDate;
    if (paidAt is Timestamp) {
      reviewedDate = paidAt.toDate();
    } else if (reviewedAt is Timestamp) {
      reviewedDate = reviewedAt.toDate();
    }

    final isPaid = status == 'paid' || status == 'completed';
    final isRejected = status == 'rejected' || status == 'failed';
    final isCancelled = status == 'cancelled' || status == 'canceled';
    final detailParts = <String>[
      if (dateStr.isNotEmpty)
        isTagalog ? 'Na-request $dateStr' : 'Requested $dateStr',
      'Cash payout',
      if (reviewedDate != null && isPaid)
        '${isTagalog ? 'Bayad' : 'Paid'} ${reviewedDate.month}/${reviewedDate.day}',
      if (reviewedDate != null && isRejected)
        '${isTagalog ? 'Tinanggihan' : 'Rejected'} ${reviewedDate.month}/${reviewedDate.day}',
      if (isCancelled) (isTagalog ? 'Nakansela' : 'Cancelled'),
      if (rejectionReason.isNotEmpty && isRejected) rejectionReason,
    ];
    final amountPrefix = isPaid ? '-' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isPaid
                ? Icons.check_circle
                : isRejected
                    ? Icons.cancel
                    : isCancelled
                        ? Icons.block
                        : Icons.hourglass_empty,
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          '$amountPrefix PHP ${amount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(detailParts.join(' - ')),
        onTap: () => _showPayoutDetails(context, payout, isTagalog),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

bool _dateInRange(DateTime date, DateTimeRange range) {
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day)
      .add(const Duration(days: 1));
  return !date.isBefore(start) && date.isBefore(end);
}

void _showPayoutDetails(
  BuildContext context,
  Map<String, dynamic> payout,
  bool isTagalog,
) {
  final amount = (payout['amount'] as num?)?.toDouble() ?? 0;
  final status = payout['status']?.toString().trim().toLowerCase() ?? '';
  final payoutId = _firstNonEmpty([
    payout['id'],
    payout['payoutId'],
  ]);
  final method = payout['method']?.toString().trim() ?? 'cash';
  final rejectionReason = payout['rejectionReason']?.toString().trim() ?? '';

  final detailRows = <_PayoutDetailRow>[
    _PayoutDetailRow(
      isTagalog ? 'Halaga' : 'Amount',
      'PHP ${amount.toStringAsFixed(2)}',
    ),
    _PayoutDetailRow(
      isTagalog ? 'Status' : 'Status',
      _payoutStatusLabelForDetails(status, isTagalog),
    ),
    _PayoutDetailRow(
      isTagalog ? 'Paraan' : 'Method',
      method.toUpperCase(),
    ),
    if (_formatPayoutTimestamp(payout['requestedAt']).isNotEmpty)
      _PayoutDetailRow(
        isTagalog ? 'Na-request' : 'Requested',
        _formatPayoutTimestamp(payout['requestedAt']),
      ),
    if (_formatPayoutTimestamp(payout['reviewedAt']).isNotEmpty)
      _PayoutDetailRow(
        isTagalog ? 'Na-review' : 'Reviewed',
        _formatPayoutTimestamp(payout['reviewedAt']),
      ),
    if (_formatPayoutTimestamp(payout['paidAt']).isNotEmpty)
      _PayoutDetailRow(
        isTagalog ? 'Na-approve' : 'Approved',
        _formatPayoutTimestamp(payout['paidAt']),
      ),
    if (_formatPayoutTimestamp(payout['cancelledAt']).isNotEmpty)
      _PayoutDetailRow(
        isTagalog ? 'Nakansela' : 'Cancelled',
        _formatPayoutTimestamp(payout['cancelledAt']),
      ),
    if (rejectionReason.isNotEmpty)
      _PayoutDetailRow(
        isTagalog ? 'Dahilan' : 'Reason',
        rejectionReason,
      ),
    if (payoutId.isNotEmpty)
      _PayoutDetailRow(
        isTagalog ? 'Payout ID' : 'Payout ID',
        payoutId,
      ),
  ];

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isTagalog ? 'Detalye ng Payout' : 'Payout Details',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 14),
              ...detailRows.map((row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            row.label,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.value,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      );
    },
  );
}

String _formatPayoutTimestamp(dynamic value) {
  DateTime? date;
  if (value is Timestamp) {
    date = value.toDate();
  } else if (value is DateTime) {
    date = value;
  }
  if (date == null) return '';

  final hour = date.hour == 0
      ? 12
      : date.hour > 12
          ? date.hour - 12
          : date.hour;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.month}/${date.day}/${date.year} $hour:$minute $suffix';
}

String _payoutStatusLabelForDetails(String status, bool isTagalog) {
  switch (status) {
    case 'paid':
    case 'completed':
      return isTagalog ? 'Na-approve' : 'Approved';
    case 'rejected':
    case 'failed':
      return isTagalog ? 'Tinanggihan' : 'Rejected';
    case 'cancelled':
    case 'canceled':
      return isTagalog ? 'Nakansela' : 'Cancelled';
    default:
      return isTagalog ? 'Hinihintay' : 'Requested';
  }
}

String _firstNonEmpty(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

class _PayoutDetailRow {
  final String label;
  final String value;

  const _PayoutDetailRow(this.label, this.value);
}

String _shortDate(DateTime date) => '${date.month}/${date.day}/${date.year}';
