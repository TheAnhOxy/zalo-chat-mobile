import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'auth_service.dart';
import 'contacts_api_service.dart';
import 'api_service.dart';

/// SocialApiService: Add friend / requests / suggested / search (v1 endpoints)
class SocialApiService {
  SocialApiService._();
  static final SocialApiService instance = SocialApiService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  String get _baseUrl => ApiService().baseUrl; // reuse dynamic baseUrl

  Options _authOptions() {
    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('MISSING_ACCESS_TOKEN');
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  ApiUserModel _parseUser(Map<String, dynamic> j) {
    return ContactsApiService.parseUser(j);
  }

  Future<List<ApiUserModel>> getSuggestedFriends({int limit = 20}) async {
    try {
      final res = await _dio.get(
        '$_baseUrl/v1/suggested-friends',
        queryParameters: {'limit': limit},
        options: _authOptions(),
      );
      final items = (res.data as Map)['items'] as List? ?? [];
      return items
          .map((e) => _parseUser(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      dev.log('❌ suggestedFriends: $e');
      return [];
    }
  }

  Future<List<ApiUserModel>> searchUsers(String q, {int limit = 20, String? cursor}) async {
    try {
      final res = await _dio.get(
        '$_baseUrl/v1/search/users',
        queryParameters: {'q': q, 'limit': limit, if (cursor != null) 'cursor': cursor},
        options: _authOptions(),
      );
      final items = (res.data as Map)['items'] as List? ?? [];
      return items
          .map((e) => _parseUser(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      dev.log('❌ searchUsers: $e');
      return [];
    }
  }

  Future<bool> sendFriendRequest(String targetUserId) async {
    try {
      await _dio.post(
        '$_baseUrl/v1/friend-requests',
        data: {'userId': targetUserId},
        options: _authOptions(),
      );
      return true;
    } catch (e) {
      dev.log('❌ sendFriendRequest: $e');
      return false;
    }
  }

  Future<List<ApiFriendRequest>> getInboundRequests() async {
    return _getRequests(kind: 'inbound');
  }

  Future<List<ApiFriendRequest>> getOutboundRequests() async {
    return _getRequests(kind: 'outbound');
  }

  Future<List<ApiFriendRequest>> _getRequests({required String kind}) async {
    try {
      final res = await _dio.get(
        '$_baseUrl/v1/friend-requests/$kind',
        options: _authOptions(),
      );
      final list = res.data as List? ?? [];
      final out = <ApiFriendRequest>[];
      for (final r in list) {
        final m = Map<String, dynamic>.from(r as Map);
        final createdAt = m['createdAt'] != null
            ? DateTime.tryParse(m['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now();
        final requesterId = (m['requesterId'] ?? '').toString();
        final addresseeId = (m['addresseeId'] ?? '').toString();
        final otherId = kind == 'inbound' ? requesterId : addresseeId;
        // fetch other user profile (minimal)
        final uRes = await _dio.get(
          '$_baseUrl/v1/users/$otherId',
          options: _authOptions(),
        );
        final user = _parseUser(Map<String, dynamic>.from(uRes.data as Map));
        out.add(ApiFriendRequest(
          friendshipId: (m['_id'] ?? m['id'] ?? '').toString(),
          user: user,
          createdAt: createdAt,
        ));
      }
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (e) {
      dev.log('❌ friendRequests($kind): $e');
      return [];
    }
  }

  Future<bool> acceptRequest(String requestId) async {
    try {
      await _dio.post(
        '$_baseUrl/v1/friend-requests/$requestId/accept',
        options: _authOptions(),
      );
      return true;
    } catch (e) {
      dev.log('❌ acceptRequest: $e');
      return false;
    }
  }

  Future<bool> declineRequest(String requestId) async {
    try {
      await _dio.post(
        '$_baseUrl/v1/friend-requests/$requestId/decline',
        options: _authOptions(),
      );
      return true;
    } catch (e) {
      dev.log('❌ declineRequest: $e');
      return false;
    }
  }

  Future<bool> cancelRequest(String requestId) async {
    try {
      await _dio.delete(
        '$_baseUrl/v1/friend-requests/$requestId',
        options: _authOptions(),
      );
      return true;
    } catch (e) {
      dev.log('❌ cancelRequest: $e');
      return false;
    }
  }

  Future<String> getRelationshipStatus(String otherUserId) async {
    try {
      final res = await _dio.get(
        '$_baseUrl/v1/relationships/$otherUserId',
        options: _authOptions(),
      );
      return (res.data as Map)['status']?.toString() ?? 'none';
    } catch (e) {
      dev.log('❌ relationship: $e');
      return 'none';
    }
  }

  Future<List<ApiUserModel>> getMutualFriends(String otherUserId, {int limit = 20, String? cursor}) async {
    try {
      final res = await _dio.get(
        '$_baseUrl/v1/users/$otherUserId/mutual-friends',
        queryParameters: {'limit': limit, if (cursor != null) 'cursor': cursor},
        options: _authOptions(),
      );
      final items = (res.data as Map)['items'] as List? ?? [];
      return items
          .map((e) => _parseUser(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      dev.log('❌ mutualFriends: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> listBlocks() async {
    try {
      final res = await _dio.get('$_baseUrl/v1/blocks', options: _authOptions());
      final list = res.data as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      dev.log('❌ listBlocks: $e');
      return [];
    }
  }

  Future<bool> blockUser(String targetUserId) async {
    try {
      await _dio.post(
        '$_baseUrl/v1/blocks',
        data: {'userId': targetUserId},
        options: _authOptions(),
      );
      return true;
    } catch (e) {
      dev.log('❌ blockUser: $e');
      return false;
    }
  }

  Future<bool> unblockUser(String targetUserId) async {
    try {
      await _dio.delete(
        '$_baseUrl/v1/blocks/$targetUserId',
        options: _authOptions(),
      );
      return true;
    } catch (e) {
      dev.log('❌ unblockUser: $e');
      return false;
    }
  }

  Future<ApiUserModel?> getUserById(String userId) async {
    try {
      final res = await _dio.get('$_baseUrl/v1/users/$userId', options: _authOptions());
      return _parseUser(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      dev.log('❌ getUserById: $e');
      return null;
    }
  }
}

