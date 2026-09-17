import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class DriverPayoutService {
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
    return token;
  }

  static Future<Map<String, dynamic>> requestCashPayout({
    required String driverId,
    required double amount,
  }) async {
    final token = await _getIdToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/requestDriverCashPayout'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'driverId': driverId,
        'amount': amount,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Failed to request cash payout');
    }

    _cachedIdToken = null;
    return body;
  }

  static Future<Map<String, dynamic>> cancelCashPayout({
    required String payoutId,
  }) async {
    final token = await _getIdToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/cancelDriverPayout'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'payoutId': payoutId,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Failed to cancel cash payout');
    }

    _cachedIdToken = null;
    return body;
  }
}
