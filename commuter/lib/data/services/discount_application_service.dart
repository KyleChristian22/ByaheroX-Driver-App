import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class DiscountApplicationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static const int validityDays = 365;
  static const int renewalWindowDays = 30;
  static const int maxDocumentImages = 5;
  static const int maxDocumentBytes = 8 * 1024 * 1024;
  static final RegExp _allowedIdPattern = RegExp(r'^[A-Za-z0-9\-/ ]+$');
  static const Map<String, String> documentTypeLabels = {
    'student_id_front': 'Student ID Front',
    'student_id_back': 'Student ID Back',
    'enrollment_proof': 'Current Enrollment Proof',
    'pwd_id_front': 'PWD ID Front',
    'pwd_id_back': 'PWD ID Back',
    'pwd_supporting_document': 'PWD Supporting Document',
    'senior_id_front': 'Senior Citizen ID Front',
    'senior_id_back': 'Senior Citizen ID Back',
    'senior_supporting_document': 'Senior Supporting Document',
  };

  static String normalizeIdNumber(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-/]+'), '');
  }

  static String? validateIdNumber(String value, {required String label}) {
    final trimmed = value.trim();
    final normalized = normalizeIdNumber(trimmed);
    if (trimmed.isEmpty) return '$label is required.';
    if (normalized.length < 4) return 'Enter a valid ID number.';
    if (trimmed.length > 50) return 'ID number is too long.';
    if (!_allowedIdPattern.hasMatch(trimmed)) {
      return 'Only letters, numbers, spaces, hyphen, and slash are allowed.';
    }
    return null;
  }

  static String maskIdNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final visibleCount = trimmed.length < 4 ? trimmed.length : 4;
    final visible = trimmed.substring(trimmed.length - visibleCount);
    final maskedLength = (trimmed.length - visibleCount).clamp(0, 24).toInt();
    return '${List.filled(maskedLength, '*').join()}$visible';
  }

  static bool isSupportedImageContentType(String contentType) {
    final clean = contentType.trim().toLowerCase();
    return clean == 'image/jpeg' ||
        clean == 'image/jpg' ||
        clean == 'image/png' ||
        clean == 'image/webp';
  }

  static List<String> requiredDocumentTypes({
    required String discountType,
    required String discountCategory,
  }) {
    final cleanType = discountType.trim().toLowerCase();
    final cleanCategory = discountCategory.trim().toLowerCase();
    if (cleanType == 'student') {
      return const [
        'student_id_front',
        'student_id_back',
        'enrollment_proof',
      ];
    }
    if (cleanType == 'pwd_senior' && cleanCategory == 'pwd') {
      return const ['pwd_id_front', 'pwd_id_back'];
    }
    if (cleanType == 'pwd_senior' && cleanCategory == 'senior') {
      return const ['senior_id_front', 'senior_id_back'];
    }
    return const [];
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> commuterDiscountStream(
    String commuterId,
  ) {
    return _firestore.collection('commuters').doc(commuterId).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> applicationsStream(
    String commuterId,
  ) {
    return _firestore
        .collection('discount_applications')
        .where('commuterId', isEqualTo: commuterId)
        .limit(10)
        .snapshots();
  }

  static bool isApprovedAndActive(Map<String, dynamic>? data) {
    if (data == null) return false;
    final status = data['discountStatus']?.toString().trim().toLowerCase();
    final expiresAt = _toDateTime(data['discountExpiresAt']);
    return status == 'approved' &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now());
  }

  static bool canRenew(Map<String, dynamic>? data) {
    if (data == null) return true;
    final status = data['discountStatus']?.toString().trim().toLowerCase();
    final renewalStatus = data['discountRenewalStatus']
        ?.toString()
        .trim()
        .toLowerCase();
    if (renewalStatus == 'pending') return false;
    if (status == null ||
        status.isEmpty ||
        status == 'none' ||
        status == 'rejected' ||
        status == 'expired') {
      return true;
    }
    if (status == 'pending') return false;
    final expiresAt = _toDateTime(data['discountExpiresAt']);
    if (expiresAt == null) return true;
    return expiresAt
        .subtract(const Duration(days: renewalWindowDays))
        .isBefore(DateTime.now());
  }

  static Future<void> submitApplication({
    required String commuterId,
    required String commuterName,
    required String discountType,
    required String discountCategory,
    required String disabilityType,
    required String idNumber,
    required String schoolName,
    required String academicPeriod,
    required bool declarationAccepted,
    required List<DiscountDocumentUpload> documents,
  }) async {
    final cleanCommuterId = commuterId.trim();
    final cleanType = discountType.trim().toLowerCase();
    final cleanCategory = discountCategory.trim().toLowerCase();
    final cleanDisabilityType = disabilityType.trim();
    final cleanIdNumber = idNumber.trim();
    final cleanSchoolName = schoolName.trim();
    final cleanAcademicPeriod = academicPeriod.trim();
    final normalizedIdNumber = normalizeIdNumber(cleanIdNumber);
    if (cleanCommuterId.isEmpty || cleanCommuterId == 'guest') {
      throw Exception('Please sign in before applying for a discount.');
    }
    if (cleanType != 'student' && cleanType != 'pwd_senior') {
      throw Exception('Please choose Student or PWD / Senior discount.');
    }
    if (cleanType == 'pwd_senior' &&
        cleanCategory != 'pwd' &&
        cleanCategory != 'senior') {
      throw Exception('Please choose PWD or Senior.');
    }
    if (cleanType == 'pwd_senior' &&
        cleanCategory == 'pwd' &&
        cleanDisabilityType.isEmpty) {
      throw Exception('Please choose the type of disability.');
    }
    if (cleanIdNumber.isEmpty) {
      throw Exception('Please enter the ID number shown on your document.');
    }
    final idError = validateIdNumber(
      cleanIdNumber,
      label: _idLabel(cleanType, cleanCategory),
    );
    if (idError != null) throw Exception(idError);
    if (cleanType == 'student' && cleanSchoolName.isEmpty) {
      throw Exception('School / university is required.');
    }
    if (cleanType == 'student' && cleanAcademicPeriod.isEmpty) {
      throw Exception('Academic year / semester is required.');
    }
    if (!declarationAccepted) {
      throw Exception('Please accept the declaration before submitting.');
    }
    if (documents.isEmpty) {
      throw Exception('Please upload at least 1 document image.');
    }
    if (documents.length > maxDocumentImages) {
      throw Exception('You can upload up to 5 document images only.');
    }
    if (documents.any((document) => document.bytes.isEmpty)) {
      throw Exception('Please upload valid document images.');
    }
    if (documents.any((document) => document.bytes.length > maxDocumentBytes)) {
      throw Exception('The selected image is too large.');
    }
    if (documents.any(
      (document) => !isSupportedImageContentType(document.contentType),
    )) {
      throw Exception('Unsupported image format.');
    }
    final uploadedTypes = documents
        .map((document) => document.documentType)
        .toSet();
    for (final requiredType in requiredDocumentTypes(
      discountType: cleanType,
      discountCategory: cleanCategory,
    )) {
      if (!uploadedTypes.contains(requiredType)) {
        throw Exception(
          'Please upload ${documentTypeLabels[requiredType] ?? 'the required ID document'}.',
        );
      }
    }

    final applicationRef = _firestore.collection('discount_applications').doc();
    final uploadedRefs = <Reference>[];
    final documentUrls = <String>[];
    final documentPaths = <String>[];
    final documentRecords = <Map<String, dynamic>>[];
    try {
      for (var index = 0; index < documents.length; index++) {
        final document = documents[index];
        final safeFileName = document.fileName
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
            .trim();
        final fallbackName = 'discount-document-${index + 1}.jpg';
        final storageRef = _storage.ref(
          'discount_applications/$cleanCommuterId/${applicationRef.id}_${index + 1}_${safeFileName.isEmpty ? fallbackName : safeFileName}',
        );
        await storageRef.putData(
          document.bytes,
          SettableMetadata(contentType: document.contentType),
        );
        uploadedRefs.add(storageRef);
        final downloadUrl = await storageRef.getDownloadURL();
        documentUrls.add(downloadUrl);
        documentPaths.add(storageRef.fullPath);
        documentRecords.add({
          'documentType': document.documentType,
          'label':
              documentTypeLabels[document.documentType] ?? document.documentType,
          'fileName': safeFileName.isEmpty ? fallbackName : safeFileName,
          'contentType': document.contentType,
          'url': downloadUrl,
          'path': storageRef.fullPath,
          'reviewStatus': 'pending',
          'uploadedAt': Timestamp.now(),
        });
      }

      final duplicateQuery = await _firestore
          .collection('discount_applications')
          .where('normalizedIdNumber', isEqualTo: normalizedIdNumber)
          .where('status', whereIn: ['pending', 'approved', 'needs_correction'])
          .limit(10)
          .get();
      final hasDuplicate = duplicateQuery.docs.any((doc) {
        final data = doc.data();
        final ownerId = data['commuterId']?.toString().trim() ?? '';
        if (ownerId == cleanCommuterId) return false;
        return true;
      });
      if (hasDuplicate) {
        throw Exception(
          'This ID number is already being used for another fare discount application.',
        );
      }

      await _firestore.runTransaction((transaction) async {
        final commuterRef = _firestore
            .collection('commuters')
            .doc(cleanCommuterId);
        final commuterDoc = await transaction.get(commuterRef);
        if (!commuterDoc.exists) {
          throw Exception('Commuter account was not found.');
        }

        final commuterData = commuterDoc.data() ?? <String, dynamic>{};
        final currentStatus =
            commuterData['discountStatus']?.toString().trim().toLowerCase() ??
            '';
        final hasActiveApprovedDiscount = isApprovedAndActive(commuterData);
        if (currentStatus == 'pending') {
          throw Exception('You already have a pending discount application.');
        }
        if (!canRenew(commuterData)) {
          throw Exception(
            'You can renew your discount 30 days before it expires.',
          );
        }
        final submittedAt = FieldValue.serverTimestamp();
        transaction.set(applicationRef, {
          'commuterId': cleanCommuterId,
          'commuterName': commuterName.trim().isEmpty
              ? (commuterData['displayName'] ??
                    commuterData['name'] ??
                    cleanCommuterId)
              : commuterName.trim(),
          'discountType': cleanType,
          if (cleanType == 'pwd_senior') 'discountCategory': cleanCategory,
          if (cleanType == 'pwd_senior' && cleanCategory == 'pwd')
            'disabilityType': cleanDisabilityType,
          'idNumber': cleanIdNumber,
          'normalizedIdNumber': normalizedIdNumber,
          if (cleanType == 'student') 'schoolName': cleanSchoolName,
          if (cleanAcademicPeriod.isNotEmpty)
            'academicPeriod': cleanAcademicPeriod,
          'status': 'pending',
          'documentUrls': documentUrls,
          'documentPaths': documentPaths,
          'documents': documentRecords,
          'declarationAccepted': true,
          'declarationAcceptedAt': submittedAt,
          'submittedAt': submittedAt,
          'createdAt': submittedAt,
          'updatedAt': submittedAt,
          'validityDays': validityDays,
          if (hasActiveApprovedDiscount) ...{
            'renewalForApplicationId': commuterData['discountApplicationId'],
            'previousDiscountType': commuterData['discountType'],
            'previousDiscountExpiresAt': commuterData['discountExpiresAt'],
          },
        });

        transaction.set(
          commuterRef,
          hasActiveApprovedDiscount
              ? {
                  'discountRenewalApplicationId': applicationRef.id,
                  'discountRenewalStatus': 'pending',
                  'discountRenewalType': cleanType,
                  if (cleanType == 'pwd_senior')
                    'discountRenewalCategory': cleanCategory,
                  if (cleanType == 'pwd_senior' && cleanCategory == 'pwd')
                    'discountRenewalDisabilityType': cleanDisabilityType,
                  if (cleanType != 'pwd_senior')
                    'discountRenewalCategory': FieldValue.delete(),
                  if (cleanType != 'pwd_senior' || cleanCategory != 'pwd')
                    'discountRenewalDisabilityType': FieldValue.delete(),
                  'discountRenewalSubmittedAt': submittedAt,
                  'discountUpdatedAt': submittedAt,
                  'discountRejectionReason': FieldValue.delete(),
                }
              : {
                  'discountStatus': 'pending',
                  'discountType': cleanType,
                  if (cleanType == 'pwd_senior')
                    'discountCategory': cleanCategory,
                  if (cleanType == 'pwd_senior' && cleanCategory == 'pwd')
                    'discountDisabilityType': cleanDisabilityType,
                  if (cleanType != 'pwd_senior')
                    'discountCategory': FieldValue.delete(),
                  if (cleanType != 'pwd_senior' || cleanCategory != 'pwd')
                    'discountDisabilityType': FieldValue.delete(),
                  'discountApplicationId': applicationRef.id,
                  'discountNormalizedIdNumber': normalizedIdNumber,
                  'discountSubmittedAt': submittedAt,
                  'discountUpdatedAt': submittedAt,
                  'discountRejectionReason': FieldValue.delete(),
                },
          SetOptions(merge: true),
        );
      });
    } catch (error) {
      for (final ref in uploadedRefs) {
        await ref.delete().catchError((_) {});
      }
      rethrow;
    }
  }

  static Future<void> cancelApplication({
    required String commuterId,
    required String applicationId,
  }) async {
    final cleanCommuterId = commuterId.trim();
    final cleanApplicationId = applicationId.trim();
    if (cleanCommuterId.isEmpty || cleanApplicationId.isEmpty) {
      throw Exception('Application details are incomplete.');
    }

    final applicationRef = _firestore
        .collection('discount_applications')
        .doc(cleanApplicationId);
    final commuterRef = _firestore.collection('commuters').doc(cleanCommuterId);

    await _firestore.runTransaction((transaction) async {
      final appDoc = await transaction.get(applicationRef);
      if (!appDoc.exists) {
        throw Exception('Discount application was not found.');
      }
      final appData = appDoc.data() ?? <String, dynamic>{};
      final ownerId = appData['commuterId']?.toString().trim() ?? '';
      if (ownerId != cleanCommuterId) {
        throw Exception('You can only cancel your own application.');
      }
      final status = appData['status']?.toString().trim().toLowerCase() ?? '';
      if (status != 'pending') {
        throw Exception('Only pending applications can be cancelled.');
      }

      final commuterDoc = await transaction.get(commuterRef);
      final commuterData = commuterDoc.data() ?? <String, dynamic>{};
      final now = FieldValue.serverTimestamp();

      transaction.update(applicationRef, {
        'status': 'cancelled',
        'cancelledAt': now,
        'updatedAt': now,
      });

      final activeApplicationId =
          commuterData['discountApplicationId']?.toString().trim() ?? '';
      final renewalApplicationId =
          commuterData['discountRenewalApplicationId']?.toString().trim() ?? '';

      if (activeApplicationId == cleanApplicationId) {
        transaction.set(commuterRef, {
          'discountStatus': 'none',
          'discountType': FieldValue.delete(),
          'discountCategory': FieldValue.delete(),
          'discountDisabilityType': FieldValue.delete(),
          'discountApplicationId': FieldValue.delete(),
          'discountSubmittedAt': FieldValue.delete(),
          'discountRejectionReason': FieldValue.delete(),
          'discountUpdatedAt': now,
        }, SetOptions(merge: true));
      }

      if (renewalApplicationId == cleanApplicationId) {
        transaction.set(commuterRef, {
          'discountRenewalApplicationId': FieldValue.delete(),
          'discountRenewalStatus': FieldValue.delete(),
          'discountRenewalType': FieldValue.delete(),
          'discountRenewalCategory': FieldValue.delete(),
          'discountRenewalDisabilityType': FieldValue.delete(),
          'discountRenewalSubmittedAt': FieldValue.delete(),
          'discountUpdatedAt': now,
        }, SetOptions(merge: true));
      }
    });
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _idLabel(String discountType, String discountCategory) {
    if (discountType == 'student') return 'Student ID number';
    if (discountType == 'pwd_senior' && discountCategory == 'pwd') {
      return 'PWD ID number';
    }
    if (discountType == 'pwd_senior' && discountCategory == 'senior') {
      return 'Senior Citizen ID number';
    }
    return 'ID number';
  }
}

class DiscountDocumentUpload {
  const DiscountDocumentUpload({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.documentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final String documentType;
}
