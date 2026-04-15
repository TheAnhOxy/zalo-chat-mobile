import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ContactsApiService — Gọi backend tại http://localhost:8081
//
// Endpoints sử dụng:
//   GET /friendships/user/:userId → danh sách friendship (filter ACCEPTED)
//   GET /users/:id                → lấy thông tin từng user
//   GET /conversations/member/:userId → filter type=GROUP → danh sách nhóm
// ─────────────────────────────────────────────────────────────────────────────

class ContactsApiService {
  static const String baseUrl = 'http://localhost:8081';

  static ContactsApiService? _instance;
  static ContactsApiService get instance =>
      _instance ??= ContactsApiService._();
  ContactsApiService._();

  final _client = http.Client();

  // ── Models ──────────────────────────────────────────────────────────────────

  static ApiUserModel parseUser(Map<String, dynamic> j) {
    DateTime? dob;
    final dobRaw = j['dob'];
    if (dobRaw != null && dobRaw.toString().isNotEmpty) {
      dob = DateTime.tryParse(dobRaw.toString());
    }
      return ApiUserModel(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      fullName: (j['fullName'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      avatar: (j['avatar'] ?? '').toString(),
      isOnline: (j['status'] as Map<String, dynamic>?)?['isOnline'] == true,
      dob: dob,
    );
  }

  static ApiGroupModel _parseGroup(Map<String, dynamic> j) {
    final members = (j['members'] as List? ?? [])
        .map((m) => ApiGroupMember(
              userId: (m['userId'] ?? '').toString(),
              role: (m['role'] ?? 'MEMBER').toString(),
            ))
        .toList();

    final lm = j['lastMessage'] as Map<String, dynamic>?;
    return ApiGroupModel(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      avatar: (j['avatar'] ?? '').toString(),
      members: members,
      lastMessageContent: lm?['content']?.toString(),
      lastMessageAt: lm?['createdAt'] != null
          ? DateTime.tryParse(lm!['createdAt'].toString())
          : null,
      updatedAt: j['updatedAt'] != null
          ? DateTime.tryParse(j['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  // ── Fetch Friends ────────────────────────────────────────────────────────────

  /// Trả về danh sách User là bạn bè ACCEPTED của [userId].
  Future<ContactsResult<List<ApiUserModel>>> fetchFriends(
      String userId) async {
    try {
      // Bước 1: lấy danh sách friendship
      final fsRes = await _client
          .get(Uri.parse('$baseUrl/friendships/user/$userId'))
          .timeout(const Duration(seconds: 10));

      if (fsRes.statusCode != 200) {
        return ContactsResult.error(
            'Lỗi ${fsRes.statusCode}: Không thể tải danh sách bạn bè');
      }

      final List<dynamic> fsJson = jsonDecode(fsRes.body) as List;

      // Bước 2: chỉ lấy ACCEPTED
      final accepted = fsJson
          .where((f) => f['status'] == 'ACCEPTED')
          .map((f) {
            final rid = (f['requesterId'] ?? '').toString();
            final aid = (f['addresseeId'] ?? '').toString();
            return rid == userId ? aid : rid;
          })
          .where((id) => id.isNotEmpty)
          .toList();

      if (accepted.isEmpty) return ContactsResult.success([]);

      // Bước 3: lấy thông tin từng user song song
      final futures = accepted
          .map((id) => _client
              .get(Uri.parse('$baseUrl/users/$id'))
              .timeout(const Duration(seconds: 10)))
          .toList();

      final responses = await Future.wait(futures, eagerError: false);

      final users = <ApiUserModel>[];
      for (final res in responses) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          users.add(parseUser(data));
        }
      }

      users.sort((a, b) => a.fullName.compareTo(b.fullName));
      return ContactsResult.success(users);
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }

  // ── Fetch Groups ─────────────────────────────────────────────────────────────

  /// Trả về danh sách nhóm (type=GROUP) mà [userId] là thành viên.
  Future<ContactsResult<List<ApiGroupModel>>> fetchGroups(
      String userId) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/conversations/member/$userId'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        return ContactsResult.error(
            'Lỗi ${res.statusCode}: Không thể tải danh sách nhóm');
      }

      final List<dynamic> json = jsonDecode(res.body) as List;
      final groups = json
          .where((c) => c['type'] == 'GROUP')
          .map((c) => _parseGroup(c as Map<String, dynamic>))
          .toList();

      groups.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return ContactsResult.success(groups);
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }

  // ── Search User By Phone ─────────────────────────────────────────────────────

  /// Tìm kiếm user theo số điện thoại. Trả về null nếu không tìm thấy.
  Future<ContactsResult<ApiUserModel?>> searchByPhone(String phone) async {
    try {
      final normalized = phone.trim().replaceAll(RegExp(r'\s+'), '');
      final res = await _client
          .get(Uri.parse('$baseUrl/users/phone/$normalized'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 404 || res.body == 'null' || res.body.trim() == 'null') {
        return const ContactsResult.success(null);
      }

      if (res.statusCode != 200) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }

      final data = jsonDecode(res.body);
      if (data == null) return const ContactsResult.success(null);
      return ContactsResult.success(parseUser(data as Map<String, dynamic>));
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }

  // ── Fetch Pending Friend Requests ────────────────────────────────────────────

  /// Số lời mời kết bạn đang chờ (addressee là mình, status=PENDING).
  Future<int> fetchPendingRequestCount(String userId) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/friendships/user/$userId'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return 0;
      final List<dynamic> list = jsonDecode(res.body) as List;
      return list
          .where((f) =>
              f['status'] == 'PENDING' &&
              (f['addresseeId'] ?? '').toString() == userId)
          .length;
    } catch (_) {
      return 0;
    }
  }

  // ── Fetch Received Friend Requests ───────────────────────────────────────────

  /// Lời mời kết bạn ĐÃ NHẬN (PENDING, addresseeId == userId).
  Future<ContactsResult<List<ApiFriendRequest>>> fetchReceivedRequests(
      String userId) async {
    return _fetchRequests(userId, received: true);
  }

  /// Lời mời kết bạn ĐÃ GỬI (PENDING, requesterId == userId).
  Future<ContactsResult<List<ApiFriendRequest>>> fetchSentRequests(
      String userId) async {
    return _fetchRequests(userId, received: false);
  }

  Future<ContactsResult<List<ApiFriendRequest>>> _fetchRequests(
      String userId, {required bool received}) async {
    try {
      final fsRes = await _client
          .get(Uri.parse('$baseUrl/friendships/user/$userId'))
          .timeout(const Duration(seconds: 10));

      if (fsRes.statusCode != 200) {
        return ContactsResult.error('Lỗi ${fsRes.statusCode}');
      }

      final List<dynamic> list = jsonDecode(fsRes.body) as List;
      final pending = list.where((f) {
        if (f['status'] != 'PENDING') return false;
        final aid = (f['addresseeId'] ?? '').toString();
        final rid = (f['requesterId'] ?? '').toString();
        return received ? aid == userId : rid == userId;
      }).toList();

      if (pending.isEmpty) return ContactsResult.success([]);

      // Lấy thông tin user đối diện song song
      final futures = pending.map((f) {
        final otherId = received
            ? (f['requesterId'] ?? '').toString()
            : (f['addresseeId'] ?? '').toString();
        return _client
            .get(Uri.parse('$baseUrl/users/$otherId'))
            .timeout(const Duration(seconds: 10));
      }).toList();

      final responses = await Future.wait(futures, eagerError: false);
      final requests = <ApiFriendRequest>[];

      for (int i = 0; i < pending.length; i++) {
        final f = pending[i];
        final res = responses[i];
        if (res.statusCode != 200) continue;
        final userData = jsonDecode(res.body) as Map<String, dynamic>;
        final createdAt = f['createdAt'] != null
            ? DateTime.tryParse(f['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now();
          requests.add(ApiFriendRequest(
          friendshipId: (f['_id'] ?? f['id'] ?? '').toString(),
          user: parseUser(userData),
          createdAt: createdAt,
        ));
      }

      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ContactsResult.success(requests);
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }

  // ── Accept / Reject Friend Request ───────────────────────────────────────────

  Future<bool> acceptFriendRequest(String friendshipId) async {
    try {
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/friendships/$friendshipId'),
            headers: {'Content-Type': 'application/json'},
            body: '{"status":"ACCEPTED"}',
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectFriendRequest(String friendshipId) async {
    try {
      final res = await _client
          .delete(Uri.parse('$baseUrl/friendships/$friendshipId'))
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelSentRequest(String friendshipId) => rejectFriendRequest(friendshipId);

  // ── Privacy: findByPhone ──────────────────────────────────────────────────────

  /// Lấy giá trị privacy.findByPhone của user từ backend.
  Future<bool?> fetchUserPrivacy(String userId) async {
    try {
      if (userId.isEmpty) return null;
      final res = await _client
          .get(Uri.parse('$baseUrl/users/$userId'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final privacy = data['privacy'] as Map<String, dynamic>?;
      return privacy?['findByPhone'] as bool? ?? true;
    } catch (_) {
      return null;
    }
  }

  /// Cập nhật privacy.findByPhone lên backend.
  Future<bool> updateFindByPhone(String userId, bool value) async {
    try {
      if (userId.isEmpty) return false;
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/users/$userId/privacy'),
            headers: {'Content-Type': 'application/json'},
            body: '{"findByPhone":$value}',
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Fetch Recent Contacts ────────────────────────────────────────────────────

  /// Lấy danh sách người dùng gần đây (từ conversation PRIVATE), sắp xếp theo thời gian.
  Future<ContactsResult<List<RecentContact>>> fetchRecentContacts(
      String userId) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/conversations/member/$userId'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }

      final List<dynamic> json = jsonDecode(res.body) as List;
      final privates = json.where((c) => c['type'] == 'PRIVATE').toList();
      privates.sort((a, b) {
        final ta = DateTime.tryParse((a['updatedAt'] ?? '').toString()) ??
            DateTime(2000);
        final tb = DateTime.tryParse((b['updatedAt'] ?? '').toString()) ??
            DateTime(2000);
        return tb.compareTo(ta);
      });

      // Lấy thông tin người kia trong mỗi cuộc trò chuyện
      final results = <RecentContact>[];
      for (final c in privates) {
        final members = (c['members'] as List? ?? []);
        final otherMember = members.firstWhere(
          (m) => (m['userId'] ?? '').toString() != userId,
          orElse: () => null,
        );
        if (otherMember == null) continue;
        final otherId = otherMember['userId'].toString();

        final uRes = await _client
            .get(Uri.parse('$baseUrl/users/$otherId'))
            .timeout(const Duration(seconds: 8));
        if (uRes.statusCode != 200) continue;

        final user =
            parseUser(jsonDecode(uRes.body) as Map<String, dynamic>);
        final lastAt = c['updatedAt'] != null
            ? DateTime.tryParse(c['updatedAt'].toString())
            : null;
        results.add(RecentContact(user: user, lastAt: lastAt));
      }

      return ContactsResult.success(results);
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }

  // ── Create Group ─────────────────────────────────────────────────────────────

  // ── Upload group avatar lên S3 via presign ──────────────────────────────────

  /// Upload ảnh nhóm qua backend → S3, tránh CORS trên web.
  /// Ném [Exception] với message cụ thể nếu thất bại.
  Future<String> uploadGroupAvatar({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    dev.log('[Upload] Gửi $fileName (${bytes.length} bytes) lên backend...');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/conversations/avatar/upload'),
    )..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ));

    final streamedRes = await request.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamedRes);

    dev.log('[Upload] Response: ${res.statusCode} ${res.body}');

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Upload thất bại (${res.statusCode}): ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final fileUrl = data['fileUrl'] as String?;
    if (fileUrl == null || fileUrl.isEmpty) {
      throw Exception('Backend không trả về fileUrl');
    }

    dev.log('[Upload] Thành công: $fileUrl');
    return fileUrl;
  }

  /// Tạo cuộc trò chuyện nhóm mới.
  Future<ContactsResult<ApiGroupModel>> createGroup({
    required String name,
    required List<String> memberIds,
    required String creatorId,
    String? avatar,
  }) async {
    try {
      final members = memberIds
          .map((id) => {
                'userId': id,
                'role': id == creatorId ? 'ADMIN' : 'MEMBER',
              })
          .toList();

      final payload = <String, dynamic>{
        'type': 'GROUP',
        'name': name,
        'members': members,
      };
      if (avatar != null && avatar.isNotEmpty) payload['avatar'] = avatar;
      final body = jsonEncode(payload);

      final res = await _client
          .post(
            Uri.parse('$baseUrl/conversations'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return ContactsResult.success(_parseGroup(data));
      }

      return ContactsResult.error(
          'Lỗi ${res.statusCode}: Không thể tạo nhóm');
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }

  // ── Fetch Birthday Contacts ───────────────────────────────────────────────────

  /// Lấy tất cả user (trừ mình) có dob, dùng cho màn hình Sinh nhật.
  Future<ContactsResult<List<ApiUserModel>>> fetchBirthdayContacts(
      String currentUserId) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/users'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }

      final List<dynamic> json = jsonDecode(res.body) as List;
      final users = json
          .map((u) => parseUser(u as Map<String, dynamic>))
          .where((u) => u.id != currentUserId && u.dob != null)
          .toList();

      return ContactsResult.success(users);
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }
}

// ── Result wrapper ────────────────────────────────────────────────────────────

class ContactsResult<T> {
  final T? data;
  final String? error;
  bool get isSuccess => error == null;

  const ContactsResult.success(T d)
      : data = d,
        error = null;
  const ContactsResult.error(String e)
      : error = e,
        data = null;
}

// ── Data models ───────────────────────────────────────────────────────────────

class ApiUserModel {
  final String id;
  final String fullName;
  final String phone;
  final String avatar;
  final bool isOnline;
  final DateTime? dob;

  const ApiUserModel({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.avatar,
    required this.isOnline,
    this.dob,
  });
}

class ApiGroupModel {
  final String id;
  final String name;
  final String avatar;
  final List<ApiGroupMember> members;
  final String? lastMessageContent;
  final DateTime? lastMessageAt;
  final DateTime updatedAt;

  const ApiGroupModel({
    required this.id,
    required this.name,
    required this.avatar,
    required this.members,
    this.lastMessageContent,
    this.lastMessageAt,
    required this.updatedAt,
  });
}

class ApiGroupMember {
  final String userId;
  final String role;
  const ApiGroupMember({required this.userId, required this.role});
}

class ApiFriendRequest {
  final String friendshipId;
  final ApiUserModel user;
  final DateTime createdAt;

  const ApiFriendRequest({
    required this.friendshipId,
    required this.user,
    required this.createdAt,
  });
}

class RecentContact {
  final ApiUserModel user;
  final DateTime? lastAt;
  const RecentContact({required this.user, this.lastAt});
}
