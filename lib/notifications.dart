import 'dart:convert';
import 'package:http/http.dart' as http;

/// Notification inbox API. Call with the current authenticated bearer token.
class NotificationApi {
  NotificationApi(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  Map<String, String> get headers => {'Authorization': 'Bearer $token'};
  Future<List<dynamic>> list() async {
    final r = await http.get(Uri.parse('$baseUrl/api/notifications'), headers: headers);
    if (r.statusCode != 200) throw Exception('Unable to load notifications (${r.statusCode})');
    return jsonDecode(r.body) as List<dynamic>;
  }
  Future<int> unreadCount() async {
    final r = await http.get(Uri.parse('$baseUrl/api/notifications/unread-count'), headers: headers);
    if (r.statusCode != 200) throw Exception('Unable to load unread count');
    return (jsonDecode(r.body) as Map<String, dynamic>)['count'] as int;
  }
  Future<void> markRead(String id) async {
    final r = await http.post(Uri.parse('$baseUrl/api/notifications/$id/read'), headers: headers);
    if (r.statusCode != 204) throw Exception('Unable to mark notification read');
  }
  Future<void> markAllRead() async {
    final r = await http.post(Uri.parse('$baseUrl/api/notifications/read-all'), headers: headers);
    if (r.statusCode != 204) throw Exception('Unable to mark notifications read');
  }
}
