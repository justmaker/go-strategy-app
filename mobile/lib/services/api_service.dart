/// API service for communicating with the Go Strategy backend.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Exception thrown when API call fails
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}

/// Service for communicating with the Go Strategy REST API
class ApiService {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  ApiService({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  /// Check if the server is healthy
  Future<bool> healthCheck() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Analyze a position (may invoke KataGo if not cached)
  Future<AnalysisResult> analyze({
    required int boardSize,
    List<String> moves = const [],
    int handicap = 0,
    double komi = 7.5,
    int? visits,
  }) async {
    final request = AnalysisRequest(
      boardSize: boardSize,
      moves: moves,
      handicap: handicap,
      komi: komi,
      visits: visits,
    );

    final response = await _post('/analyze', request.toJson());
    return AnalysisResult.fromJson(response);
  }

  /// Query cache only (fast, no KataGo invocation)
  Future<AnalysisResult?> query({
    required int boardSize,
    List<String> moves = const [],
    int handicap = 0,
    double komi = 7.5,
    int? visits,
  }) async {
    final request = AnalysisRequest(
      boardSize: boardSize,
      moves: moves,
      handicap: handicap,
      komi: komi,
      visits: visits,
    );

    try {
      final response = await _post('/query', request.toJson());

      // Check if we got a cache hit
      if (response['found'] == true && response['result'] != null) {
        return AnalysisResult.fromJson(response['result']);
      }
      return null;
    } on ApiException catch (e) {
      // 404 means not in cache, which is expected
      if (e.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getStats() async {
    final response = await _get('/stats');
    return response;
  }

  /// Generic GET request
  Future<Map<String, dynamic>> _get(String endpoint) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    try {
      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Generic POST request
  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Handle HTTP response
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw ApiException('Invalid JSON response');
      }
    }

    String message;
    try {
      final error = jsonDecode(response.body);
      message = error['detail'] ?? error['message'] ?? 'Unknown error';
    } catch (e) {
      message = response.body;
    }

    throw ApiException(message, statusCode: response.statusCode);
  }

  /// Dispose the HTTP client
  void dispose() {
    _client.close();
  }
}
