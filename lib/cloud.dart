import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'auth.dart' show apiBaseUrl, apiUrlAllowed, secureStorage;

class CloudApi {
  Future<dynamic> request(String method, String path, [Map<String, dynamic>? body]) async {
    final token = await secureStorage.read(key: 'access_token');
    if (token == null) throw Exception('Please sign in again.');
    if (!apiUrlAllowed) throw Exception('Configure HTTPS API_BASE_URL.');
    final uri = Uri.parse('$apiBaseUrl/api/$path');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    late http.Response response;
    switch (method) {
      case 'GET': response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20)); break;
      case 'POST': response = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20)); break;
      case 'PUT': response = await http.put(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20)); break;
      case 'DELETE': response = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 20)); break;
      default: throw ArgumentError('Unsupported HTTP method');
    }
    if (response.statusCode >= 400) {
      String message = 'Request failed (${response.statusCode}).';
      try { message = (jsonDecode(response.body) as Map<String, dynamic>)['error']?.toString() ?? message; } catch (_) {}
      throw Exception(message);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }
  Future<Map<String, dynamic>> uploadAttachment(String resource, String filename, Uint8List bytes) async {
    final token = await secureStorage.read(key: 'access_token');
    if (token == null) throw Exception('Please sign in again.');
    if (!apiUrlAllowed) throw Exception('HTTPS required.');
    final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/api/$resource/attachments'));
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send().timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 400) throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
  Future<void> sendCombinedMessage(String kind, String peerId, String text, List<http.MultipartFile> files) async {
    final token = await secureStorage.read(key: 'access_token');
    if (token == null) throw Exception('Please sign in again.');
    if (!apiUrlAllowed) throw Exception('HTTPS required.');
    final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/api/chat/$kind/$peerId/combined'));
    req.headers['Authorization'] = 'Bearer $token';
    req.fields['text'] = text;
    req.files.addAll(files);
    final streamed = await req.send().timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 400) throw Exception('Message failed (${response.statusCode}): ${response.body}');
  }
  Future<Map<String, dynamic>> uploadAvatar(
    String filename,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw Exception('Profile picture must be between 1 byte and 5 MB.');
    }

    final token = await secureStorage.read(key: 'access_token');
    if (token == null) throw Exception('Please sign in again.');
    if (!apiUrlAllowed) throw Exception('HTTPS required.');

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBaseUrl/api/account/avatar'),
    );

    req.headers['Authorization'] = 'Bearer $token';

    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ),
    );

    final streamed = await req.send().timeout(
      const Duration(minutes: 2),
    );

    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
        'Avatar upload failed (${response.statusCode}): ${response.body}',
      );
    }

    return Map<String, dynamic>.from(
      jsonDecode(response.body) as Map,
    );
  }
  Future<Uint8List> downloadAttachment(String attachmentId) async {
    final token = await secureStorage.read(key: 'access_token');
    if (token == null) throw Exception('Please sign in again.');
    final response = await http.get(Uri.parse('$apiBaseUrl/api/chat/attachments/$attachmentId'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) throw Exception('Download failed (${response.statusCode}).');
    return response.bodyBytes;
  }
  Future<Uint8List> downloadAvatar({String? userId}) async {
    final token = await secureStorage.read(key: 'access_token');

    if (token == null) {
      throw Exception('Please sign in again.');
    }

    if (!apiUrlAllowed) {
      throw Exception('HTTPS required.');
    }

    final response = await http.get(
      Uri.parse(userId == null ? '$apiBaseUrl/api/account/avatar' : '$apiBaseUrl/api/chat/avatar/$userId'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'Avatar download failed (${response.statusCode}).',
      );
    }

    return response.bodyBytes;
  }
  Future<List<Map<String, dynamic>>> list(String resource) async => (await request('GET', resource) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Future<void> add(String resource, Map<String, dynamic> data) async { await request('POST', resource, data); }
  Future<void> update(String resource, String id, Map<String, dynamic> data) async { await request('PUT', '$resource/$id', data); }
  Future<void> delete(String resource, String id) async { await request('DELETE', '$resource/$id'); }
}

