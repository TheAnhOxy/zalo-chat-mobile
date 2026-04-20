import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../core/config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ContactsApiService — URL lấy từ AppConfig.baseUrl (tự động theo platform)
// ─────────────────────────────────────────────────────────────────────────────

class ContactsApiService {
  static String get baseUrl => AppConfig.baseUrl;
  static ContactsApiService? _instance;
  static ContactsApiService get instance =>
      _instance ??= ContactsApiService._();
  ContactsApiService._();

  final _client = http.Client();

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Lấy string ID an toàn từ field MongoDB.
  /// MongoDB đôi khi trả về ObjectId dưới dạng Map {"$oid": "..."} thay vì string.
  static String _extractId(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is Map) {
      return (raw['\$oid'] ?? raw['oid'] ?? raw['_id'] ?? '').toString();
    }
    return raw.toString();
  }

  // ── Models ──────────────────────────────────────────────────────────────────

  static ApiUserModel _parseUser(Map<String, dynamic> j) {
    DateTime? dob;
    final dobRaw = j['dob'];
    if (dobRaw != null && dobRaw.toString().isNotEmpty) {
      dob = DateTime.tryParse(dobRaw.toString());
    }
    bool isOnline = false;
    DateTime? lastSeen;
    final status = j['status'];
    if (status is Map) {
      isOnline = status['isOnline'] == true;
      final rawLastSeen = status['lastSeen'] ?? status['lastActiveAt'] ?? status['lastOnlineAt'];
      if (rawLastSeen != null) {
        lastSeen = DateTime.tryParse(rawLastSeen.toString());
      }
    } else if (status is String) {
      isOnline = status == 'ONLINE';
    }
    return ApiUserModel(
      id: _extractId(j['_id'] ?? j['id']),
      fullName: (j['fullName'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      avatar: (j['avatar'] ?? '').toString(),
      isOnline: isOnline,
      lastSeen: lastSeen,
      dob: dob,
    );
  }

  static ApiGroupModel _parseGroup(Map<String, dynamic> j) {
    final members = (j['members'] as List? ?? [])
        .map(
          (m) => ApiGroupMember(
            userId: _extractId(m['userId'] ?? m['_id']),
            role: (m['role'] ?? 'MEMBER').toString(),
          ),
        )
        .toList();

    final rawDesc = j['description'] ?? j['about'] ?? j['mota'] ?? j['groupDescription'];
    final lm = j['lastMessage'] as Map<String, dynamic>?;
    return ApiGroupModel(
      id: _extractId(j['_id'] ?? j['id']),
      name: (j['name'] ?? '').toString(),
      avatar: (j['avatar'] ?? '').toString(),
      members: members,
      description: rawDesc == null ? null : rawDesc.toString(),
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
  Future<ContactsResult<List<ApiUserModel>>> fetchFriends(String userId) async {
    try {
      // Bước 1: lấy danh sách friendship
      final fsRes = await _client
          .get(Uri.parse('$baseUrl/friendships/user/$userId'))
          .timeout(const Duration(seconds: 10));

      if (fsRes.statusCode != 200) {
        return ContactsResult.error(
          'Lỗi ${fsRes.statusCode}: Không thể tải danh sách bạn bè',
        );
      }

      final List<dynamic> fsJson = jsonDecode(fsRes.body) as List;

      // Bước 2: chỉ lấy ACCEPTED
      final accepted = fsJson
          .where((f) => f['status'] == 'ACCEPTED')
          .map((f) {
            final rid = _extractId(f['requesterId']);
            final aid = _extractId(f['addresseeId']);
            return rid == userId ? aid : rid;
          })
          .where((id) => id.isNotEmpty)
          .toList();

      if (accepted.isEmpty) return ContactsResult.success([]);

      // Bước 3: lấy thông tin từng user song song
      final futures = accepted
          .map(
            (id) => _client
                .get(Uri.parse('$baseUrl/users/$id'))
                .timeout(const Duration(seconds: 10)),
          )
          .toList();

      final responses = await Future.wait(futures, eagerError: false);

      final users = <ApiUserModel>[];
      for (final res in responses) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          users.add(_parseUser(data));
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
  Future<ContactsResult<List<ApiGroupModel>>> fetchGroups(String userId) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/conversations/member/$userId'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        return ContactsResult.error(
          'Lỗi ${res.statusCode}: Không thể tải danh sách nhóm',
        );
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

      if (res.statusCode == 404 ||
          res.body == 'null' ||
          res.body.trim() == 'null') {
        return const ContactsResult.success(null);
      }

      if (res.statusCode != 200) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }

      final data = jsonDecode(res.body);
      if (data == null) return const ContactsResult.success(null);
      return ContactsResult.success(_parseUser(data as Map<String, dynamic>));
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
          .where(
            (f) =>
                f['status'] == 'PENDING' &&
                _extractId(f['addresseeId']) == userId,
          )
          .length;
    } catch (_) {
      return 0;
    }
  }

  // ── Fetch Received Friend Requests ───────────────────────────────────────────

  /// Lời mời kết bạn ĐÃ NHẬN (PENDING, addresseeId == userId).
  Future<ContactsResult<List<ApiFriendRequest>>> fetchReceivedRequests(
    String userId,
  ) async {
    return _fetchRequests(userId, received: true);
  }

  /// Lời mời kết bạn ĐÃ GỬI (PENDING, requesterId == userId).
  Future<ContactsResult<List<ApiFriendRequest>>> fetchSentRequests(
    String userId,
  ) async {
    return _fetchRequests(userId, received: false);
  }

  Future<ContactsResult<List<ApiFriendRequest>>> _fetchRequests(
    String userId, {
    required bool received,
  }) async {
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
        final aid = _extractId(f['addresseeId']);
        final rid = _extractId(f['requesterId']);
        return received ? aid == userId : rid == userId;
      }).toList();

      if (pending.isEmpty) return ContactsResult.success([]);

      // Lấy thông tin user đối diện song song
      final futures = pending.map((f) {
        final otherId = received
            ? _extractId(f['requesterId'])
            : _extractId(f['addresseeId']);
        return _client
            .get(Uri.parse('$baseUrl/users/$otherId'))
            .timeout(const Duration(seconds: 10));
      }).toList();

      final responses = await Future.wait(futures, eagerError: false);
      final requests = <ApiFriendRequest>[];

      for (int i = 0; i < pending.length; i++) {
        final f = pending[i];
        final res = responses[i];
        dev.log('[FR] user fetch status=${res.statusCode}');

        final otherId = received
            ? _extractId(f['requesterId'])
            : _extractId(f['addresseeId']);

        // Nếu fetch profile thất bại → vẫn hiện request với thông tin fallback
        final ApiUserModel user;
        if (res.statusCode == 200) {
          user = _parseUser(jsonDecode(res.body) as Map<String, dynamic>);
        } else {
          dev.log(
            '[FR] profile not found for $otherId (${res.statusCode}), using fallback',
          );
          user = ApiUserModel(
            id: otherId,
            fullName: 'Người dùng',
            phone: '',
            avatar: '',
            isOnline: false,
          );
        }

        final createdAt = f['createdAt'] != null
            ? DateTime.tryParse(f['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now();

        requests.add(
          ApiFriendRequest(
            friendshipId: _extractId(f['_id'] ?? f['id']),
            user: user,
            createdAt: createdAt,
          ),
        );
      }

      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ContactsResult.success(requests);
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }

  // ── Send Friend Request ──────────────────────────────────────────────────────

  /// Gửi lời mời kết bạn từ [requesterId] đến [receiverId].
  /// [message] là lời nhắn kèm theo (tùy chọn).
  /// Trả về message nếu thành công; nếu đã tồn tại thì cũng trả về message phù hợp.
  Future<ContactsResult<String>> sendFriendRequest({
    required String requesterId,
    required String receiverId,
    String message = '',
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/friendships'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'requesterId': requesterId,
              'addresseeId': receiverId, // backend field name
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 201) {
        return const ContactsResult.success('Đã gửi lời mời kết bạn');
      }

      // 409 = đã tồn tại quan hệ friendship (PENDING/ACCEPTED)
      if (res.statusCode == 409) {
        final rel = await getFriendshipBetween(
          myUserId: requesterId,
          otherUserId: receiverId,
        );
        final status = rel.data?['status'];
        if (status == 'ACCEPTED') {
          return const ContactsResult.success('Hai bạn đã là bạn bè');
        }
        if (status == 'PENDING') {
          return const ContactsResult.success('Lời mời kết bạn đã tồn tại');
        }
        return const ContactsResult.success('Quan hệ kết bạn đã tồn tại');
      }

      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      dev.log('❌ sendFriendRequest error: $e');
      return ContactsResult.error('Không kết nối được: $e');
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

  Future<bool> cancelSentRequest(String friendshipId) =>
      rejectFriendRequest(friendshipId);

  /// Lấy quan hệ friendship giữa [myUserId] và [otherUserId] (nếu có).
  /// Trả về: { id, status } hoặc null nếu chưa có.
  Future<ContactsResult<Map<String, String>?>> getFriendshipBetween({
    required String myUserId,
    required String otherUserId,
  }) async {
    try {
      if (myUserId.isEmpty || otherUserId.isEmpty) {
        return const ContactsResult.success(null);
      }
      final res = await _client
          .get(Uri.parse('$baseUrl/friendships/user/$myUserId'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }

      final List<dynamic> list = jsonDecode(res.body) as List;
      for (final f in list) {
        if (f is! Map) continue;
        final rid = _extractId(f['requesterId']);
        final aid = _extractId(f['addresseeId']);
        final match = (rid == myUserId && aid == otherUserId) ||
            (rid == otherUserId && aid == myUserId);
        if (!match) continue;

        final id = _extractId(f['_id'] ?? f['id']);
        final status = (f['status'] ?? '').toString();
        if (id.isEmpty) continue;
        return ContactsResult.success({'id': id, 'status': status});
      }
      return const ContactsResult.success(null);
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

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
    String userId,
  ) async {
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
        final ta =
            DateTime.tryParse((a['updatedAt'] ?? '').toString()) ??
            DateTime(2000);
        final tb =
            DateTime.tryParse((b['updatedAt'] ?? '').toString()) ??
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

        final user = _parseUser(jsonDecode(uRes.body) as Map<String, dynamic>);
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

    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/conversations/avatar/upload'),
          )
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: fileName,
              contentType: MediaType.parse(mimeType),
            ),
          );

    final streamedRes = await request.send().timeout(
      const Duration(seconds: 30),
    );
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

  /// Cập nhật ảnh đại diện nhóm (PATCH conversation).
  Future<ContactsResult<bool>> updateConversationAvatar({
    required String conversationId,
    required String avatarUrl,
  }) async {
    try {
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/conversations/$conversationId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'avatar': avatarUrl}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return const ContactsResult.success(true);
      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  /// Cập nhật mô tả nhóm (PATCH conversation).
  Future<ContactsResult<bool>> updateGroupDescription({
    required String conversationId,
    required String description,
  }) async {
    try {
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/conversations/$conversationId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'description': description}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 204) {
        return const ContactsResult.success(true);
      }
      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  // ── Group chat background (sync toàn nhóm) ──────────────────────────────────

  /// Lấy groupSettings (raw) của conversation theo ID.
  Future<ContactsResult<Map<String, dynamic>>> fetchConversationRaw(
    String conversationId,
  ) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/conversations/$conversationId'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        return ContactsResult.success(data);
      }
      return const ContactsResult.error('Dữ liệu không hợp lệ');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  /// Cập nhật hình nền nhóm (áp dụng cho tất cả thành viên) qua groupSettings.
  Future<ContactsResult<bool>> updateGroupChatBackground({
    required String conversationId,
    required String type, // 'PRESET' | 'CUSTOM'
    required int index,
    String? customBase64,
  }) async {
    try {
      final payload = <String, dynamic>{
        'groupSettings': <String, dynamic>{
          'chatBackgroundType': type,
          'chatBackgroundIndex': index,
          'chatBackgroundCustomBase64': customBase64 ?? '',
        },
      };
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/conversations/$conversationId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return const ContactsResult.success(true);
      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  /// Lấy/tạo link mời vào nhóm.
  Future<ContactsResult<Map<String, dynamic>>> getGroupInviteLink(
    String conversationId,
  ) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/conversations/$conversationId/invite-link'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        return ContactsResult.success(data);
      }
      return const ContactsResult.error('Dữ liệu không hợp lệ');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  /// Tạo mới link mời (đổi code).
  Future<ContactsResult<Map<String, dynamic>>> regenerateGroupInviteLink(
    String conversationId,
  ) async {
    try {
      final res = await _client
          .post(
            Uri.parse(
              '$baseUrl/conversations/$conversationId/invite-link/regenerate',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 && res.statusCode != 201) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        return ContactsResult.success(data);
      }
      return const ContactsResult.error('Dữ liệu không hợp lệ');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  /// Bật/tắt link mời nhóm qua groupSettings.allowInviteLink.
  Future<ContactsResult<bool>> setGroupInviteLinkEnabled({
    required String conversationId,
    required bool enabled,
  }) async {
    try {
      final payload = <String, dynamic>{
        'groupSettings': <String, dynamic>{'allowInviteLink': enabled},
      };
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/conversations/$conversationId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 204) {
        return const ContactsResult.success(true);
      }
      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
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
          .map(
            (id) => {
              'userId': id,
              'role': id == creatorId ? 'ADMIN' : 'MEMBER',
            },
          )
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

      return ContactsResult.error('Lỗi ${res.statusCode}: Không thể tạo nhóm');
    } catch (e) {
      return ContactsResult.error('Không kết nối được backend: $e');
    }
  }

  // ── Group Member Management ──────────────────────────────────────────────────

  /// Lấy thông tin user theo ID
  Future<ApiUserModel?> fetchUserById(String userId) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/users/$userId'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic>) {
          return _parseUser(body);
        }
      } else {
        dev.log('⚠️ fetchUserById $userId → ${res.statusCode}');
      }
    } catch (e) {
      dev.log('❌ fetchUserById $userId error: $e');
    }
    return null;
  }

  /// Lấy thông tin nhiều user cùng lúc (song song)
  Future<Map<String, ApiUserModel>> fetchUsersByIds(List<String> ids) async {
    final result = <String, ApiUserModel>{};
    await Future.wait(ids.map((id) async {
      final u = await fetchUserById(id);
      if (u != null) {
        result[id] = u;
      } else {
        dev.log('⚠️ fetchUsersByIds: không lấy được user $id');
      }
    }));
    dev.log('✅ fetchUsersByIds: ${result.length}/${ids.length} users loaded');
    return result;
  }

  /// Kick thành viên ra khỏi nhóm
  Future<ContactsResult<bool>> kickMember({
    required String conversationId,
    required String targetUserId,
    required List<ApiGroupMember> currentMembers,
  }) async {
    try {
      final remaining = currentMembers
          .where((m) => m.userId != targetUserId)
          .map((m) => {'userId': m.userId, 'role': m.role})
          .toList();
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/conversations/$conversationId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'members': remaining}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return const ContactsResult.success(true);
      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  /// Cập nhật role của thành viên (ADMIN / MODERATOR / MEMBER)
  Future<ContactsResult<bool>> updateMemberRole({
    required String conversationId,
    required String targetUserId,
    required String newRole,
    required List<ApiGroupMember> currentMembers,
  }) async {
    try {
      final updated = currentMembers
          .map((m) => {
                'userId': m.userId,
                'role': m.userId == targetUserId ? newRole : m.role,
              })
          .toList();
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/conversations/$conversationId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'members': updated}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return const ContactsResult.success(true);
      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  /// Thêm thành viên vào nhóm
  Future<ContactsResult<bool>> addMembersToGroup({
    required String conversationId,
    required List<ApiGroupMember> currentMembers,
    required List<String> newUserIds,
  }) async {
    try {
      final updated = [
        ...currentMembers.map((m) => {'userId': m.userId, 'role': m.role}),
        ...newUserIds
            .where((id) => currentMembers.every((m) => m.userId != id))
            .map((id) => {'userId': id, 'role': 'MEMBER'}),
      ];
      final res = await _client
          .patch(
            Uri.parse('$baseUrl/conversations/$conversationId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'members': updated}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return const ContactsResult.success(true);
      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  /// Rời khỏi nhóm (tự remove mình)
  Future<ContactsResult<bool>> leaveGroup({
    required String conversationId,
    required String myUserId,
    required List<ApiGroupMember> currentMembers,
  }) =>
      kickMember(
        conversationId: conversationId,
        targetUserId: myUserId,
        currentMembers: currentMembers,
      );

  /// Giải tán nhóm: xóa conversation (chỉ nên gọi nếu là ADMIN).
  Future<ContactsResult<bool>> dissolveGroup({
    required String conversationId,
  }) async {
    try {
      final res = await _client
          .delete(Uri.parse('$baseUrl/conversations/$conversationId'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 204) {
        return const ContactsResult.success(true);
      }
      return ContactsResult.error('Lỗi ${res.statusCode}');
    } catch (e) {
      return ContactsResult.error('Không kết nối được: $e');
    }
  }

  // ── Fetch Birthday Contacts ───────────────────────────────────────────────────

  /// Lấy tất cả user (trừ mình) có dob, dùng cho màn hình Sinh nhật.
  Future<ContactsResult<List<ApiUserModel>>> fetchBirthdayContacts(
    String currentUserId,
  ) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/users'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        return ContactsResult.error('Lỗi ${res.statusCode}');
      }

      final List<dynamic> json = jsonDecode(res.body) as List;
      final users = json
          .map((u) => _parseUser(u as Map<String, dynamic>))
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

  const ContactsResult.success(T d) : data = d, error = null;
  const ContactsResult.error(String e) : error = e, data = null;
}

// ── Data models ───────────────────────────────────────────────────────────────

class ApiUserModel {
  final String id;
  final String fullName;
  final String phone;
  final String avatar;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? dob;

  const ApiUserModel({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.avatar,
    required this.isOnline,
    this.lastSeen,
    this.dob,
  });
}

class ApiGroupModel {
  final String id;
  final String name;
  final String avatar;
  final List<ApiGroupMember> members;
  final String? description;
  final String? lastMessageContent;
  final DateTime? lastMessageAt;
  final DateTime updatedAt;

  const ApiGroupModel({
    required this.id,
    required this.name,
    required this.avatar,
    required this.members,
    this.description,
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
