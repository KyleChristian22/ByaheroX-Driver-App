import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../data/services/discount_application_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../widgets/common/app_background.dart';

class DiscountApplicationScreen extends StatefulWidget {
  const DiscountApplicationScreen({super.key});

  @override
  State<DiscountApplicationScreen> createState() =>
      _DiscountApplicationScreenState();
}

class _DiscountApplicationScreenState extends State<DiscountApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idNumberCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();
  final _academicPeriodCtrl = TextEditingController();
  final _picker = ImagePicker();
  String _discountType = 'student';
  String _discountCategory = '';
  String _disabilityType = '';
  final List<DiscountDocumentUpload> _documents = <DiscountDocumentUpload>[];
  bool _declarationAccepted = false;
  bool _isSubmitting = false;
  final Set<String> _cancellingApplicationIds = <String>{};
  static const List<String> _disabilityTypes = [
    'Physical Disability',
    'Visual Impairment',
    'Hearing Impairment',
    'Speech and Language Impairment',
    'Intellectual Disability',
    'Psychosocial Disability',
    'Learning Disability',
    'Chronic Illness with Disability',
  ];

  @override
  void dispose() {
    _idNumberCtrl.dispose();
    _schoolCtrl.dispose();
    _academicPeriodCtrl.dispose();
    super.dispose();
  }

  void _leaveDiscount() {
    final auth = context.read<AuthViewModel>();
    context.go(auth.isGuest ? AppRouter.login : AppRouter.profile);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final user = auth.currentUser;

    if (auth.isGuest || user.id.trim().isEmpty || user.id == 'guest') {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leaveDiscount();
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Fare Discount'),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _leaveDiscount,
            ),
          ),
          body: Center(
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
                      Icons.login_outlined,
                      size: 56,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Sign in required',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Discount applications are connected to your commuter account and RFID profile.',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 14,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => context.go(AppRouter.login),
                    icon: const Icon(Icons.login),
                    label: const Text('Sign In'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leaveDiscount();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Fare Discount'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leaveDiscount,
          ),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: DiscountApplicationService.commuterDiscountStream(user.id),
          builder: (context, snapshot) {
            final commuterData = snapshot.data?.data();
            return ListView(
              padding: const EdgeInsets.all(AppDimensions.md),
              children: [
                _buildStatusCard(commuterData),
                const SizedBox(height: AppDimensions.md),
                _buildReminderCard(),
                const SizedBox(height: AppDimensions.md),
                _buildApplicationForm(
                  commuterId: user.id,
                  commuterName: user.displayName,
                  commuterData: commuterData,
                ),
                const SizedBox(height: AppDimensions.md),
                _buildRecentApplications(user.id),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusCard(Map<String, dynamic>? data) {
    final status = _status(data);
    final type = _typeLabelFromData(data);
    final expiresAt = _toDateTime(data?['discountExpiresAt']);
    final reason = data?['discountRejectionReason']?.toString().trim() ?? '';
    final isActive = DiscountApplicationService.isApprovedAndActive(data);
    final isExpiringSoon =
        isActive &&
        expiresAt != null &&
        expiresAt.difference(DateTime.now()).inDays <=
            DiscountApplicationService.renewalWindowDays;

    Color color;
    IconData icon;
    String title;
    String body;
    switch (status) {
      case 'approved':
        if (isActive) {
          color = isExpiringSoon ? AppColors.warning : AppColors.success;
          icon = isExpiringSoon
              ? Icons.event_busy_outlined
              : Icons.verified_outlined;
          title = isExpiringSoon
              ? '$type Discount Expiring Soon'
              : '$type Discount Approved';
          body = isExpiringSoon
              ? 'Your discount expires on ${_date(expiresAt)}. Upload updated documents to keep discounted RFID fares.'
              : 'Valid until ${_date(expiresAt)}. Your RFID fare is discounted automatically.';
        } else {
          color = AppColors.error;
          icon = Icons.event_busy_outlined;
          title = 'Discount Expired';
          body =
              'Your discount expired on ${_date(expiresAt)}. RFID payments now use regular fare until you apply again.';
        }
        break;
      case 'pending':
        color = Colors.orange;
        icon = Icons.hourglass_top_outlined;
        title = 'Application Pending';
        body =
            'Your application is waiting for treasurer review. RFID payments use regular fare until approved.';
        break;
      case 'needs_correction':
        color = AppColors.warning;
        icon = Icons.edit_document;
        title = 'Application Needs Correction';
        body =
            'Your application requires updated information or documents. Open your application to view the reviewer request.';
        break;
      case 'rejected':
        color = AppColors.error;
        icon = Icons.cancel_outlined;
        title = 'Application Denied';
        body = reason.isEmpty
            ? 'RFID payments will continue using regular fare. You may submit a new application.'
            : 'Reason: $reason';
        break;
      default:
        color = AppColors.primary;
        icon = Icons.badge_outlined;
        title = 'No Active Discount';
        body =
            'Students, PWD, and Senior passengers can apply for discounted RFID fares.';
    }

    return _InfoCard(color: color, icon: icon, title: title, body: body);
  }

  Widget _buildReminderCard() {
    return const _InfoCard(
      color: AppColors.primary,
      icon: Icons.notifications_active_outlined,
      title: 'One-Year Validity',
      body:
          'Approved discounts are valid for 1 year. The app will remind you when renewal is available 30 days before expiration.',
    );
  }

  Widget _buildApplicationForm({
    required String commuterId,
    required String commuterName,
    required Map<String, dynamic>? commuterData,
  }) {
    final canApply = DiscountApplicationService.canRenew(commuterData);
    final status = _status(commuterData);
    final buttonText = status == 'approved'
        ? 'Review Renewal'
        : 'Review Application';
    final selectedType = _selectedDiscountOption;
    final requirements = _requirements();

    return GlassSurface(
      padding: const EdgeInsets.all(AppDimensions.md),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Apply for Fare Discount',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                  EdgeInsets.symmetric(
                    horizontal: AppDimensions.xs,
                    vertical: AppDimensions.sm,
                  ),
                ),
                iconSize: const WidgetStatePropertyAll<double>(18),
                textStyle: const WidgetStatePropertyAll<TextStyle>(
                  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primaryBlueSurface.withValues(alpha: 0.72);
                  }
                  return AppColors.surface.withValues(alpha: 0.22);
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primaryBlue;
                  }
                  return AppColors.textPrimary;
                }),
                side: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return BorderSide(
                      color: AppColors.primaryBlue.withValues(alpha: 0.62),
                      width: 1.4,
                    );
                  }
                  return BorderSide(
                    color: AppColors.surface.withValues(alpha: 0.46),
                  );
                }),
              ),
              segments: const [
                ButtonSegment(
                  value: 'student',
                  label: Text(
                    'Student',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  icon: Icon(Icons.school_outlined),
                ),
                ButtonSegment(
                  value: 'pwd',
                  label: Text(
                    'PWD',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  icon: Icon(Icons.accessible_outlined),
                ),
                ButtonSegment(
                  value: 'senior',
                  label: Text(
                    'Senior',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  icon: Icon(Icons.elderly_outlined),
                ),
              ],
              selected: {selectedType},
              onSelectionChanged: canApply && !_isSubmitting
                  ? (values) => setState(() {
                        _setDiscountOption(values.first);
                      })
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _idNumberCtrl,
              enabled: canApply && !_isSubmitting,
              decoration: InputDecoration(
                labelText: '${_idFieldLabel} *',
                hintText: _idFieldHint,
                border: const OutlineInputBorder(),
              ),
              validator: (value) => DiscountApplicationService.validateIdNumber(
                value ?? '',
                label: _idFieldLabel,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_discountType == 'student') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _schoolCtrl,
                enabled: canApply && !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'School / University *',
                  hintText: 'Enter your school or university',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'School / university is required.';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _academicPeriodCtrl,
                enabled: canApply && !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Academic Year / Semester *',
                  hintText: 'Example: 2026-2027 / First Semester',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Academic year / semester is required.';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_discountType == 'pwd_senior' &&
                _discountCategory == 'pwd') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _disabilityType.isEmpty ? null : _disabilityType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Type of Disability *',
                  border: OutlineInputBorder(),
                ),
                items: _disabilityTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                          type,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Disability type is required.';
                  }
                  return null;
                },
                onChanged: canApply && !_isSubmitting
                    ? (value) => setState(() => _disabilityType = value ?? '')
                    : null,
              ),
            ],
            const SizedBox(height: 14),
            const _DocumentGuidanceCard(),
            const SizedBox(height: 12),
            for (final requirement in _documentRequirements()) ...[
              _DocumentUploadField(
                requirement: requirement,
                document: _documentFor(requirement.documentType),
                isSubmitting: _isSubmitting,
                canEdit: canApply && !_isSubmitting,
                onCamera: () =>
                    _pickDocument(requirement.documentType, ImageSource.camera),
                onGallery: () => _pickDocument(
                  requirement.documentType,
                  ImageSource.gallery,
                ),
                onPreview: () {
                  final document = _documentFor(requirement.documentType);
                  if (document != null) _previewSelectedDocument(document);
                },
                onRemove: () => setState(
                  () => _documents.removeWhere(
                    (doc) => doc.documentType == requirement.documentType,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            _ApplicationChecklist(items: requirements),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _declarationAccepted,
              onChanged: canApply && !_isSubmitting
                  ? (value) => setState(
                        () => _declarationAccepted = value ?? false,
                      )
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I certify that the information and documents I submitted are authentic, accurate, and belong to me.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canApply && !_isSubmitting
                  ? () => _reviewBeforeSubmit(commuterId, commuterName)
                  : null,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_isSubmitting ? 'Submitting...' : buttonText),
            ),
            if (!canApply) ...[
              const SizedBox(height: 10),
              Text(
                status == 'pending'
                    ? 'You already have a pending application.'
                    : 'Renewal opens 30 days before your discount expires.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _selectedDiscountOption {
    if (_discountType == 'student') return 'student';
    if (_discountCategory == 'senior') return 'senior';
    return 'pwd';
  }

  String get _idFieldLabel {
    if (_discountType == 'student') return 'Student ID Number';
    if (_discountCategory == 'senior') return 'Senior Citizen ID / OSCA Number';
    return 'PWD ID Number';
  }

  String get _idFieldHint {
    if (_discountType == 'student') {
      return 'Enter the ID number shown on your student ID';
    }
    if (_discountCategory == 'senior') {
      return 'Enter the number shown on your Senior Citizen ID';
    }
    return 'Enter the ID number shown on your PWD ID';
  }

  void _setDiscountOption(String option) {
    _documents.clear();
    _disabilityType = '';
    if (option == 'student') {
      _discountType = 'student';
      _discountCategory = '';
    } else if (option == 'senior') {
      _discountType = 'pwd_senior';
      _discountCategory = 'senior';
      _schoolCtrl.clear();
      _academicPeriodCtrl.clear();
    } else {
      _discountType = 'pwd_senior';
      _discountCategory = 'pwd';
      _schoolCtrl.clear();
      _academicPeriodCtrl.clear();
    }
  }

  DiscountDocumentUpload? _documentFor(String documentType) {
    for (final document in _documents) {
      if (document.documentType == documentType) return document;
    }
    return null;
  }

  List<_DocumentRequirement> _documentRequirements() {
    if (_discountType == 'student') {
      return const [
        _DocumentRequirement(
          documentType: 'student_id_front',
          label: 'Student ID - Front',
          required: true,
        ),
        _DocumentRequirement(
          documentType: 'student_id_back',
          label: 'Student ID - Back',
          required: true,
        ),
        _DocumentRequirement(
          documentType: 'enrollment_proof',
          label: 'Current Enrollment Proof',
          required: true,
        ),
      ];
    }
    if (_discountCategory == 'senior') {
      return const [
        _DocumentRequirement(
          documentType: 'senior_id_front',
          label: 'Senior Citizen ID - Front',
          required: true,
        ),
        _DocumentRequirement(
          documentType: 'senior_id_back',
          label: 'Senior Citizen ID - Back',
          required: true,
        ),
        _DocumentRequirement(
          documentType: 'senior_supporting_document',
          label: 'Supporting Proof',
        ),
      ];
    }
    return const [
      _DocumentRequirement(
        documentType: 'pwd_id_front',
        label: 'PWD ID - Front',
        required: true,
      ),
      _DocumentRequirement(
        documentType: 'pwd_id_back',
        label: 'PWD ID - Back',
        required: true,
      ),
      _DocumentRequirement(
        documentType: 'pwd_supporting_document',
        label: 'Supporting Document',
      ),
    ];
  }

  List<_ChecklistItem> _requirements() {
    final idValid = DiscountApplicationService.validateIdNumber(
          _idNumberCtrl.text,
          label: _idFieldLabel,
        ) ==
        null;
    final hasSchool =
        _discountType != 'student' || _schoolCtrl.text.trim().isNotEmpty;
    final hasAcademicPeriod = _discountType != 'student' ||
        _academicPeriodCtrl.text.trim().isNotEmpty;
    final hasDisability = _discountCategory != 'pwd' || _disabilityType.isNotEmpty;
    final items = <_ChecklistItem>[
      _ChecklistItem(label: 'Discount type selected', complete: true),
      _ChecklistItem(label: '$_idFieldLabel entered', complete: idValid),
      if (_discountType == 'student')
        _ChecklistItem(
          label: 'School / University entered',
          complete: hasSchool,
        ),
      if (_discountType == 'student')
        _ChecklistItem(
          label: 'Academic year / semester entered',
          complete: hasAcademicPeriod,
        ),
      if (_discountCategory == 'pwd')
        _ChecklistItem(
          label: 'Disability type selected',
          complete: hasDisability,
        ),
      for (final requirement in _documentRequirements())
        if (requirement.required)
          _ChecklistItem(
            label: '${requirement.label} uploaded',
            complete: _documentFor(requirement.documentType) != null,
          ),
      _ChecklistItem(
        label: 'Declaration accepted',
        complete: _declarationAccepted,
      ),
    ];
    return items;
  }

  bool _validateRequirements({bool showMessages = true}) {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    for (final requirement in _documentRequirements()) {
      if (requirement.required &&
          _documentFor(requirement.documentType) == null) {
        if (showMessages) {
          _showSnack(
            'Please upload ${requirement.label}.',
            isError: true,
          );
        }
        return false;
      }
    }
    if (!_declarationAccepted) {
      if (showMessages) {
        _showSnack('Please accept the declaration.', isError: true);
      }
      return false;
    }
    return true;
  }

  Future<void> _reviewBeforeSubmit(
    String commuterId,
    String commuterName,
  ) async {
    if (!_validateRequirements()) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ReviewApplicationSheet(
        applicationType: _typeLabelFromData({
          'discountType': _discountType,
          'discountCategory': _discountCategory,
        }),
        commuterName: commuterName,
        idLabel: _idFieldLabel,
        idNumber: _idNumberCtrl.text.trim(),
        schoolName: _schoolCtrl.text.trim(),
        academicPeriod: _academicPeriodCtrl.text.trim(),
        disabilityType: _disabilityType,
        declarationAccepted: _declarationAccepted,
        requirements: _documentRequirements(),
        documents: List<DiscountDocumentUpload>.unmodifiable(_documents),
      ),
    );
    if (confirmed != true) return;
    await _submit(commuterId, commuterName);
  }

  Future<void> _previewSelectedDocument(DiscountDocumentUpload document) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return GlassSurface(
              padding: EdgeInsets.zero,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              backgroundColor: AppColors.surface.withValues(alpha: 0.38),
              child: SafeArea(
                top: false,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.image_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            document.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: Colors.grey[100],
                        child: Image.memory(
                          document.bytes,
                          width: double.infinity,
                          fit: BoxFit.contain,
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

  Widget _buildRecentApplications(String commuterId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: DiscountApplicationService.applicationsStream(commuterId),
      builder: (context, snapshot) {
        final docs = [...(snapshot.data?.docs ?? [])]
          ..sort((a, b) {
            final aDate =
                _toDateTime(a.data()['submittedAt']) ?? DateTime(1970);
            final bDate =
                _toDateTime(b.data()['submittedAt']) ?? DateTime(1970);
            return bDate.compareTo(aDate);
          });
        if (docs.isEmpty) return const SizedBox.shrink();

        return GlassSurface(
          padding: const EdgeInsets.all(AppDimensions.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent Applications',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...docs.map((doc) {
                final data = doc.data();
                final status = _status(data);
                final isPending = status == 'pending';
                final isCancelling = _cancellingApplicationIds.contains(doc.id);
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(_typeLabelFromData(data)),
                    subtitle: Text(
                      '${_statusLabel(status)} - Submitted ${_date(_toDateTime(data['submittedAt']))}',
                    ),
                    trailing: isCancelling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isPending
                                ? Icons.pending_actions_outlined
                                : Icons.chevron_right,
                            color: isPending ? AppColors.warning : null,
                          ),
                    onTap: () => _showApplicationDetails(doc.id, data),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showApplicationDetails(
    String applicationId,
    Map<String, dynamic> data,
  ) async {
    final status = _status(data);
    final isPending = status == 'pending';
    final documents = _applicationDocuments(data);
    final reason = _reviewReason(data);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return GlassSurface(
              padding: EdgeInsets.zero,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              backgroundColor: AppColors.surface.withValues(alpha: 0.38),
              child: SafeArea(
                top: false,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(_statusIcon(status), color: _statusColor(status)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_typeLabelFromData(data)} Discount',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _detailRow('Status', _statusLabel(status)),
                    _detailRow('Discount Type', _typeLabelFromData(data)),
                    if (_disabilityLabel(data).isNotEmpty)
                      _detailRow('Disability', _disabilityLabel(data)),
                    if ((data['schoolName']?.toString().trim() ?? '').isNotEmpty)
                      _detailRow('School', data['schoolName'].toString()),
                    if ((data['academicPeriod']?.toString().trim() ?? '').isNotEmpty)
                      _detailRow(
                        'Academic',
                        data['academicPeriod'].toString(),
                      ),
                    _detailRow(
                      'ID Number',
                      DiscountApplicationService.maskIdNumber(
                        data['idNumber']?.toString() ?? '',
                      ),
                    ),
                    _detailRow(
                      'Submitted',
                      _date(_toDateTime(data['submittedAt'])),
                    ),
                    if (_toDateTime(data['reviewedAt']) != null)
                      _detailRow(
                        'Reviewed',
                        _date(_toDateTime(data['reviewedAt'])),
                      ),
                    if (_toDateTime(data['approvedAt']) != null)
                      _detailRow(
                        'Approved',
                        _date(_toDateTime(data['approvedAt'])),
                      ),
                    if (_toDateTime(data['expiresAt']) != null)
                      _detailRow(
                        status == 'expired' ? 'Expired' : 'Expires',
                        _date(_toDateTime(data['expiresAt'])),
                      ),
                    if (_toDateTime(data['cancelledAt']) != null)
                      _detailRow(
                        'Cancelled',
                        _date(_toDateTime(data['cancelledAt'])),
                      ),
                    if (reason.isNotEmpty) _detailRow('Reason', reason),
                    const SizedBox(height: 14),
                    _statusExplanation(status),
                    const SizedBox(height: 18),
                    const Text(
                      'Uploaded Documents',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (documents.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('No document preview is available.'),
                      )
                    else
                      ...documents.map(
                        (document) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      document.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (document.reviewStatus.isNotEmpty)
                                    Text(
                                      _documentStatusLabel(
                                        document.reviewStatus,
                                      ),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  document.url,
                                  height: 260,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  webHtmlElementStrategy:
                                      WebHtmlElementStrategy.fallback,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 120,
                                    alignment: Alignment.center,
                                    color: Colors.grey[100],
                                    child: const Text(
                                      'Unable to load document preview',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (isPending)
                      OutlinedButton.icon(
                        onPressed:
                            _cancellingApplicationIds.contains(applicationId)
                            ? null
                            : () async {
                                Navigator.pop(sheetContext);
                                await _cancelApplication(applicationId);
                              },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel Application'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: TextStyle(color: Colors.grey[700])),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusExplanation(String status) {
    String message;
    switch (status) {
      case 'pending':
        message =
            'Your request is waiting for treasurer review. RFID fares stay regular until approval, unless you already have an active previous discount.';
        break;
      case 'approved':
        message = 'Approved RFID discounts are valid for 1 year.';
        break;
      case 'expired':
        message =
            'This approval has expired. Upload updated documents to apply again.';
        break;
      case 'rejected':
        message =
            'This request was denied. You can submit a new application with clearer or updated documents.';
        break;
      case 'needs_correction':
        message =
            'The reviewer needs updated or clearer information before this application can be approved.';
        break;
      case 'cancelled':
        message =
            'You cancelled this request. It will not be reviewed by the treasurer.';
        break;
      default:
        message = 'This is your submitted discount application record.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _statusColor(status).withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_statusIcon(status), color: _statusColor(status), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(height: 1.35))),
        ],
      ),
    );
  }

  Future<void> _cancelApplication(String applicationId) async {
    final auth = context.read<AuthViewModel>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Application?'),
        content: const Text(
          'This pending request will be cancelled and will not be reviewed. You can submit a new one afterward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _cancellingApplicationIds.add(applicationId));
    try {
      await DiscountApplicationService.cancelApplication(
        commuterId: auth.currentUser.id,
        applicationId: applicationId,
      );
      if (!mounted) return;
      _showSnack('Discount application cancelled.');
    } catch (error) {
      if (!mounted) return;
      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _cancellingApplicationIds.remove(applicationId));
      }
    }
  }

  Future<void> _pickDocument(
    String documentType,
    ImageSource source,
  ) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1800,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final contentType = picked.mimeType ?? _contentTypeFromName(picked.name);
      final validationError = _validatePickedImage(
        bytes: bytes,
        contentType: contentType,
        replacingExisting: _documentFor(documentType) != null,
      );
      if (validationError != null) {
        _showSnack(validationError, isError: true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _documents.removeWhere((doc) => doc.documentType == documentType);
        _documents.add(
          DiscountDocumentUpload(
            bytes: bytes,
            fileName: picked.name,
            contentType: contentType,
            documentType: documentType,
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      _showSnack(
        'Could not select image. Please check permissions and try again.',
        isError: true,
      );
    }
  }

  String _contentTypeFromName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }

  String? _validatePickedImage({
    required List<int> bytes,
    required String contentType,
    required bool replacingExisting,
  }) {
    if (bytes.isEmpty) return 'Please upload a valid document image.';
    if (bytes.length > DiscountApplicationService.maxDocumentBytes) {
      return 'The selected image is too large.';
    }
    if (!DiscountApplicationService.isSupportedImageContentType(contentType)) {
      return 'Unsupported image format.';
    }
    if (!replacingExisting &&
        _documents.length >= DiscountApplicationService.maxDocumentImages) {
      return 'You can upload up to 5 document images only.';
    }
    return null;
  }

  Future<void> _submit(String commuterId, String commuterName) async {
    if (!_validateRequirements()) return;

    setState(() => _isSubmitting = true);
    try {
      await DiscountApplicationService.submitApplication(
        commuterId: commuterId,
        commuterName: commuterName,
        discountType: _discountType,
        discountCategory: _discountCategory,
        disabilityType: _disabilityType,
        idNumber: _idNumberCtrl.text,
        schoolName: _schoolCtrl.text,
        academicPeriod: _academicPeriodCtrl.text,
        declarationAccepted: _declarationAccepted,
        documents: List<DiscountDocumentUpload>.unmodifiable(_documents),
      );
      if (!mounted) return;
      setState(() {
        _idNumberCtrl.clear();
        _schoolCtrl.clear();
        _academicPeriodCtrl.clear();
        _documents.clear();
        _discountCategory = '';
        _disabilityType = '';
        _discountType = 'student';
        _declarationAccepted = false;
      });
      _showSnack('Discount application submitted for treasurer review.');
    } catch (error) {
      if (!mounted) return;
      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  static String _status(Map<String, dynamic>? data) {
    final raw = data?['discountStatus'] ?? data?['status'];
    final status = raw?.toString().trim().toLowerCase() ?? 'none';
    if (status == 'approved') {
      final expiresAt = _toDateTime(
        data?['discountExpiresAt'] ?? data?['expiresAt'],
      );
      if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
        return 'expired';
      }
    }
    return status.isEmpty ? 'none' : status;
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending Review';
      case 'approved':
        return 'Approved';
      case 'expired':
        return 'Expired';
      case 'rejected':
        return 'Denied';
      case 'needs_correction':
        return 'Needs Correction';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      default:
        return 'No Active Discount';
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'pending':
      case 'needs_correction':
        return Colors.orange;
      case 'rejected':
      case 'expired':
        return AppColors.error;
      case 'cancelled':
      case 'canceled':
        return Colors.grey;
      default:
        return AppColors.primary;
    }
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.verified_outlined;
      case 'pending':
        return Icons.hourglass_top_outlined;
      case 'needs_correction':
        return Icons.edit_document;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'expired':
        return Icons.event_busy_outlined;
      case 'cancelled':
      case 'canceled':
        return Icons.remove_circle_outline;
      default:
        return Icons.badge_outlined;
    }
  }

  static String _typeLabelFromData(Map<String, dynamic>? data) {
    final type = data?['discountType']?.toString().trim().toLowerCase();
    final category = data?['discountCategory']?.toString().trim().toLowerCase();
    if (type == 'pwd_senior' && category == 'senior') return 'Senior';
    if (type == 'pwd_senior' && category == 'pwd') return 'PWD';
    return _typeLabel(type);
  }

  static String _typeLabel(dynamic value) {
    final type = value?.toString().trim().toLowerCase();
    if (type == 'pwd') return 'PWD';
    if (type == 'pwd_senior') return 'PWD / Senior';
    if (type == 'student') return 'Student';
    return 'Discount';
  }

  static String _disabilityLabel(Map<String, dynamic> data) {
    final category = data['discountCategory']?.toString().trim().toLowerCase();
    if (category != 'pwd') return '';
    return data['disabilityType']?.toString().trim() ?? '';
  }

  static String _reviewReason(Map<String, dynamic> data) {
    final values = [
      data['reviewReason'],
      data['reviewerNotes'],
      data['rejectionReason'],
    ];
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static List<_ApplicationDocumentView> _applicationDocuments(
    Map<String, dynamic> data,
  ) {
    final structured = data['documents'];
    if (structured is List) {
      final documents = structured
          .whereType<Map>()
          .map((raw) {
            final map = raw.cast<String, dynamic>();
            final url = map['url']?.toString().trim() ?? '';
            if (url.isEmpty) return null;
            final type = map['documentType']?.toString().trim() ?? '';
            return _ApplicationDocumentView(
              label: map['label']?.toString().trim().isNotEmpty == true
                  ? map['label'].toString()
                  : DiscountApplicationService.documentTypeLabels[type] ??
                        'Uploaded Document',
              url: url,
              reviewStatus: map['reviewStatus']?.toString().trim() ?? '',
            );
          })
          .whereType<_ApplicationDocumentView>()
          .toList();
      if (documents.isNotEmpty) return documents;
    }

    final urls = (data['documentUrls'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList();
    return [
      for (var index = 0; index < urls.length; index++)
        _ApplicationDocumentView(
          label: 'Photo ${index + 1}',
          url: urls[index],
          reviewStatus: '',
        ),
    ];
  }

  static String _documentStatusLabel(String status) {
    final clean = status.trim().toLowerCase();
    if (clean.isEmpty) return '';
    return clean
        .split('_')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _date(DateTime? value) {
    if (value == null) return 'not set';
    return DateFormat('MMM d, yyyy').format(value);
  }
}

class _SelectedDocumentTile extends StatelessWidget {
  const _SelectedDocumentTile({
    required this.document,
    required this.index,
    this.title,
    required this.isSubmitting,
    required this.onPreview,
    required this.onRemove,
    this.onReplace,
  });

  final DiscountDocumentUpload document;
  final int index;
  final String? title;
  final bool isSubmitting;
  final VoidCallback onPreview;
  final VoidCallback onRemove;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPreview,
          borderRadius: BorderRadius.circular(10),
          child: GlassSurface(
            padding: const EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    document.bytes,
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 54,
                      height: 54,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? 'Photo ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        document.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Preview image',
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                ),
                if (onReplace != null)
                  IconButton(
                    tooltip: 'Replace image',
                    onPressed: isSubmitting ? null : onReplace,
                    icon: const Icon(Icons.swap_horiz_outlined, size: 20),
                  ),
                IconButton(
                  tooltip: 'Remove image',
                  onPressed: isSubmitting ? null : onRemove,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplicationDocumentView {
  const _ApplicationDocumentView({
    required this.label,
    required this.url,
    required this.reviewStatus,
  });

  final String label;
  final String url;
  final String reviewStatus;
}

class _DocumentRequirement {
  const _DocumentRequirement({
    required this.documentType,
    required this.label,
    this.required = false,
  });

  final String documentType;
  final String label;
  final bool required;
}

class _ChecklistItem {
  const _ChecklistItem({required this.label, required this.complete});

  final String label;
  final bool complete;
}

class _DocumentGuidanceCard extends StatelessWidget {
  const _DocumentGuidanceCard();

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      color: AppColors.primary,
      icon: Icons.tips_and_updates_outlined,
      title: 'Document quality',
      body:
          'Make sure your ID is clear and readable. Avoid glare, blur, cropped edges, dark photos, or covered details. Name, ID number, photo, issuing school/LGU, and validity should be visible when applicable.',
    );
  }
}

class _DocumentUploadField extends StatelessWidget {
  const _DocumentUploadField({
    required this.requirement,
    required this.document,
    required this.isSubmitting,
    required this.canEdit,
    required this.onCamera,
    required this.onGallery,
    required this.onPreview,
    required this.onRemove,
  });

  final _DocumentRequirement requirement;
  final DiscountDocumentUpload? document;
  final bool isSubmitting;
  final bool canEdit;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onPreview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final uploaded = document != null;
    return GlassSurface(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(14),
      backgroundColor: AppColors.surface.withValues(alpha: 0.24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                uploaded
                    ? Icons.check_circle_outline
                    : Icons.image_outlined,
                color: uploaded ? AppColors.success : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${requirement.label}${requirement.required ? ' *' : ' (optional)'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (document == null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: canEdit ? onCamera : null,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take Photo'),
                ),
                OutlinedButton.icon(
                  onPressed: canEdit ? onGallery : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from Gallery'),
                ),
              ],
            )
          else
            _SelectedDocumentTile(
              document: document!,
              index: 0,
              title: requirement.label,
              isSubmitting: isSubmitting,
              onPreview: onPreview,
              onRemove: onRemove,
              onReplace: canEdit ? onGallery : null,
            ),
        ],
      ),
    );
  }
}

class _ApplicationChecklist extends StatelessWidget {
  const _ApplicationChecklist({required this.items});

  final List<_ChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(14),
      backgroundColor: AppColors.surface.withValues(alpha: 0.24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Application Requirements',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    item.complete
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 18,
                    color: item.complete ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: item.complete
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewApplicationSheet extends StatelessWidget {
  const _ReviewApplicationSheet({
    required this.applicationType,
    required this.commuterName,
    required this.idLabel,
    required this.idNumber,
    required this.schoolName,
    required this.academicPeriod,
    required this.disabilityType,
    required this.declarationAccepted,
    required this.requirements,
    required this.documents,
  });

  final String applicationType;
  final String commuterName;
  final String idLabel;
  final String idNumber;
  final String schoolName;
  final String academicPeriod;
  final String disabilityType;
  final bool declarationAccepted;
  final List<_DocumentRequirement> requirements;
  final List<DiscountDocumentUpload> documents;

  DiscountDocumentUpload? _documentFor(String type) {
    for (final document in documents) {
      if (document.documentType == type) return document;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.76,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return GlassSurface(
          padding: EdgeInsets.zero,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          backgroundColor: AppColors.surface.withValues(alpha: 0.38),
          child: SafeArea(
            top: false,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Fare Discount Application',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _ReviewRow(label: 'Application Type', value: applicationType),
                _ReviewRow(label: 'Applicant', value: commuterName),
                _ReviewRow(label: idLabel, value: idNumber),
                if (schoolName.isNotEmpty)
                  _ReviewRow(label: 'School / University', value: schoolName),
                if (academicPeriod.isNotEmpty)
                  _ReviewRow(
                    label: 'Academic Year / Semester',
                    value: academicPeriod,
                  ),
                if (disabilityType.isNotEmpty)
                  _ReviewRow(label: 'Disability Type', value: disabilityType),
                const SizedBox(height: 12),
                const Text(
                  'Documents',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final requirement in requirements)
                  _ReviewRow(
                    label: requirement.label,
                    value: _documentFor(requirement.documentType) == null
                        ? 'Not provided'
                        : 'Uploaded',
                  ),
                const SizedBox(height: 8),
                _ReviewRow(
                  label: 'Declaration',
                  value: declarationAccepted ? 'Accepted' : 'Not accepted',
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Confirm & Submit'),
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
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(AppDimensions.md),
      backgroundColor: color.withValues(alpha: 0.1),
      borderColor: color.withValues(alpha: 0.28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
