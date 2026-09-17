import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GcashReceiptTopupException implements Exception {
  const GcashReceiptTopupException(
    this.message, {
    this.errorCode,
    this.retryable = true,
    this.topupRequestId,
    this.transactionId,
  });

  final String message;
  final String? errorCode;
  final bool retryable;
  final String? topupRequestId;
  final String? transactionId;

  @override
  String toString() => message;
}

class GcashReceiptTopupService {
  static const String _baseUrl =
      'https://us-central1-byaheroxperience.cloudfunctions.net';

  static String? _cachedIdToken;

  static Future<String> _getIdToken() async {
    if (_cachedIdToken != null) return _cachedIdToken!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    if (token == null) throw Exception('Not authenticated');
    _cachedIdToken = token;
    return _cachedIdToken!;
  }

  static Future<Map<String, dynamic>> analyzeReceiptTopup({
    required String commuterId,
    required Uint8List receiptBytes,
    String mimeType = 'image/jpeg',
    String? rfidCard,
    Map<String, dynamic>? confirmedExtraction,
  }) async {
    const maxUploadBytes = 90 * 1024;
    if (receiptBytes.length > maxUploadBytes) {
      throw GcashReceiptTopupException(
        'Receipt image is too large. Please crop the screenshot or retake it closer to the receipt',
        errorCode: 'receipt_image_too_large',
      );
    }

    final token = await _getIdToken();
    http.Response response;
    try {
      debugPrint(
        '[GCashTopup] Uploading receipt: ${receiptBytes.length} bytes, $mimeType',
      );
      response = await http
          .post(
            Uri.parse('$_baseUrl/analyzeGcashReceiptTopup'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'commuterId': commuterId,
              'rfidCard': rfidCard,
              'mimeType': mimeType,
              'receiptImageBase64': base64Encode(receiptBytes),
              if (confirmedExtraction != null)
                'confirmedExtraction': confirmedExtraction,
            }),
          )
          .timeout(const Duration(seconds: 140));
    } catch (error) {
      _cachedIdToken = null;
      debugPrint('[GCashTopup] Upload failed before response: $error');
      throw GcashReceiptTopupException(
        'Receipt upload failed before the server responded. Please try again with a clearer cropped receipt image',
        errorCode: 'network_or_timeout',
      );
    }

    debugPrint(
      '[GCashTopup] Response ${response.statusCode}: ${response.body}',
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = {
        'message': response.body.isNotEmpty
            ? response.body
            : 'Receipt service returned an empty response',
      };
    }

    if (response.statusCode != 200) {
      final errorCode = body['errorCode']?.toString();
      throw GcashReceiptTopupException(
        errorCode == 'openai_quota_exceeded'
            ? 'Receipt scanner is temporarily unavailable. Please try again later'
            : body['message']?.toString() ?? 'Failed to analyze GCash receipt',
        errorCode: errorCode,
        retryable: body['retryable'] != false,
        topupRequestId: body['topupRequestId']?.toString(),
        transactionId: body['transactionId']?.toString(),
      );
    }

    _cachedIdToken = null;
    return body;
  }

  static Future<Map<String, dynamic>> cancelTopupRequest({
    required String commuterId,
    required String topupRequestId,
  }) async {
    final token = await _getIdToken();
    http.Response response;
    try {
      debugPrint('[GCashTopup] Cancelling request: $topupRequestId');
      response = await http
          .post(
            Uri.parse('$_baseUrl/cancelCommuterTopupRequest'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'commuterId': commuterId,
              'topupRequestId': topupRequestId,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      _cachedIdToken = null;
      debugPrint('[GCashTopup] Cancel failed before response: $error');
      throw const GcashReceiptTopupException(
        'Failed to cancel top-up request. Please check your connection and try again',
        errorCode: 'network_or_timeout',
      );
    }

    debugPrint(
      '[GCashTopup] Cancel response ${response.statusCode}: ${response.body}',
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = {
        'message': response.body.isNotEmpty
            ? response.body
            : 'Cancel service returned an empty response',
      };
    }

    if (response.statusCode != 200) {
      throw GcashReceiptTopupException(
        body['message']?.toString() ?? 'Failed to cancel top-up request',
        errorCode: body['errorCode']?.toString(),
        retryable: body['retryable'] != false,
      );
    }

    _cachedIdToken = null;
    return body;
  }

  static Future<Map<String, dynamic>> previewReceiptTopup({
    required String commuterId,
    required Uint8List receiptBytes,
    String mimeType = 'image/jpeg',
  }) async {
    const maxUploadBytes = 90 * 1024;
    if (receiptBytes.length > maxUploadBytes) {
      throw GcashReceiptTopupException(
        'Receipt image is too large. Please crop the screenshot or retake it closer to the receipt',
        errorCode: 'receipt_image_too_large',
      );
    }

    final token = await _getIdToken();
    http.Response response;
    try {
      debugPrint(
        '[GCashTopup] Previewing receipt: ${receiptBytes.length} bytes, $mimeType',
      );
      response = await http
          .post(
            Uri.parse('$_baseUrl/previewGcashReceiptTopup'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'commuterId': commuterId,
              'mimeType': mimeType,
              'receiptImageBase64': base64Encode(receiptBytes),
            }),
          )
          .timeout(const Duration(seconds: 140));
    } catch (error) {
      _cachedIdToken = null;
      debugPrint('[GCashTopup] Preview failed before response: $error');
      throw GcashReceiptTopupException(
        'Receipt scan failed before the server responded. Please try again with a clearer cropped receipt image',
        errorCode: 'network_or_timeout',
      );
    }

    debugPrint(
      '[GCashTopup] Preview response ${response.statusCode}: ${response.body}',
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = {
        'message': response.body.isNotEmpty
            ? response.body
            : 'Receipt service returned an empty response',
      };
    }

    if (response.statusCode != 200) {
      final errorCode = body['errorCode']?.toString();
      final isMissingFunction =
          response.statusCode == 404 ||
          body['message']?.toString().contains('Page not found') == true;
      throw GcashReceiptTopupException(
        isMissingFunction
            ? 'Receipt scanner is not available yet. Please deploy the latest commuter Cloud Functions and try again'
            : errorCode == 'openai_quota_exceeded'
            ? 'Receipt scanner is temporarily unavailable. Please try again later'
            : body['message']?.toString() ?? 'Failed to preview GCash receipt',
        errorCode: isMissingFunction
            ? 'receipt_scanner_not_deployed'
            : errorCode,
        retryable: body['retryable'] != false,
      );
    }

    return body;
  }
}
