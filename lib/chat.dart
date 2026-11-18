import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'cloud.dart';
import 'auth.dart' show apiBaseUrl, apiUrlAllowed, secureStorage;
import 'package:signalr_netcore/signalr_client.dart';

const chatBurgundy = Color(0xFF812A46);

class ChatPhotoViewer extends StatefulWidget {
  const ChatPhotoViewer({super.key, required this.bytes, required this.name, required this.type});
  final Uint8List bytes;
  final String name, type;
  @override State<ChatPhotoViewer> createState() => _ChatPhotoViewerState();
}

class _ChatPhotoViewerState extends State<ChatPhotoViewer> {
  bool saving = false;
  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final saved = await const MethodChannel('catchit/photos').invokeMethod<bool>('save', {
        'bytes': widget.bytes, 'name': widget.name, 'type': widget.type,
      });
      if (mounted && saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo saved to your selected location.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the photo. Please try again.')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [TextButton.icon(
        onPressed: saving ? null : save,
        icon: const Icon(Icons.download, color: Colors.white),
        label: Text(saving ? 'Saving…' : 'Save', style: const TextStyle(color: Colors.white)),
      )],
    ),
    body: SafeArea(child: Center(child: InteractiveViewer(
      minScale: 1, maxScale: 5,
      child: Image.memory(widget.bytes, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Text('Photo unavailable', style: TextStyle(color: Colors.white))),
    ))),
  );
}

Widget chatAvatar(Future<Uint8List> photo, {double radius = 20}) =>
    FutureBuilder<Uint8List>(
      future: photo,
      builder: (context, snapshot) => CircleAvatar(
        radius: radius,
        backgroundImage: snapshot.hasData ? MemoryImage(snapshot.data!) : null,
        child: snapshot.hasData ? null : const Icon(Icons.person_outline, size: 18),
      ),
    );

class ChatInbox extends StatefulWidget {
  const ChatInbox({super.key, required this.currentUserId, this.embedded = false, this.startNewChat = false});
  final String currentUserId;
  final bool embedded;
  final bool startNewChat;
  @override State<ChatInbox> createState() => _ChatInboxState();
}
class _ChatInboxState extends State<ChatInbox> {
  final api = CloudApi();
  final photos = <String, Future<Uint8List>>{};
  List<Map<String, dynamic>> groups = [], directs = [];
  bool busy = true;
  Map<String, int> unreadDirect = {}, unreadGroups = {};
  String? error;
  @override void initState() {
    super.initState();
    load();
    if (widget.startNewChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) findUser();
      });
    }
  }
  Future<void> load() async {
    try {
      final data = Map<String, dynamic>.from(await api.request('GET', 'chat/conversations') as Map);
      final counts = Map<String, dynamic>.from(await api.request('GET', 'notifications/unread') as Map);
      if (mounted) setState(() {
        photos.clear();
        groups = (data['groups'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
        directs = (data['directs'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
        unreadDirect = {for (final x in (counts['directs'] as List)) x['id'].toString(): (x['unread'] as num).toInt()};
        unreadGroups = {for (final x in (counts['groups'] as List)) x['id'].toString(): (x['unread'] as num).toInt()};
        busy = false; error = null;
      });
    } catch (e) { if (mounted) setState(() { busy = false; error = '$e'; }); }
  }
  Future<void> findUser() async {
    String email = '';
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Throw a pitch'),
      content: TextFormField(keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Exact email address'), onChanged: (text) => email = text),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, email.trim()), child: const Text('Find'))],
    ));
    if (value == null || value.isEmpty) return;
    try {
      final result = await api.list('chat/users?email=${Uri.encodeQueryComponent(value)}');
      if (!mounted) return;
      if (result.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matching user.'))); return; }
      await openChat(result.first, false);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Future<void> openChat(Map<String, dynamic> item, bool group) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(
      id: item['id'].toString(), title: item['name'].toString(), isGroup: group, currentUserId: widget.currentUserId,
    )));
    if (mounted) load();
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded ? null : AppBar(title: const Text('Messages'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: findUser, icon: const Icon(Icons.edit_square), label: const Text('Throw a pitch')),
    body: busy ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: TextButton(onPressed: load, child: Text('${error!}\nTap to retry'))) :
    RefreshIndicator(onRefresh: load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
      const ListTile(title: Text('Private conversations', style: TextStyle(fontWeight: FontWeight.bold))),
      if (directs.isEmpty) const ListTile(title: Text('No private conversations yet')),
      ...directs.map((u) => ListTile(leading: chatAvatar(photos.putIfAbsent(u['id'].toString(), () => api.downloadAvatar(userId: u['id'].toString()))), title: Text(u['name'].toString()), trailing: unreadDirect.containsKey(u['id'].toString()) ? CircleAvatar(radius: 14, backgroundColor: chatBurgundy, child: Text('${unreadDirect[u['id'].toString()]}', style: const TextStyle(color: Colors.white, fontSize: 12))) : null, onTap: () => openChat(u, false))),
      const Divider(), const ListTile(title: Text('Group conversations', style: TextStyle(fontWeight: FontWeight.bold))),
      if (groups.isEmpty) const ListTile(title: Text('Join or create a group to start chatting')),
      ...groups.map((g) => ListTile(leading: const CircleAvatar(child: Icon(Icons.groups)), title: Text(g['name'].toString()), trailing: unreadGroups.containsKey(g['id'].toString()) ? CircleAvatar(radius: 14, backgroundColor: chatBurgundy, child: Text('${unreadGroups[g['id'].toString()]}', style: const TextStyle(color: Colors.white, fontSize: 12))) : null, onTap: () => openChat(g, true))),
    ])),
  );
}

class ChatThread extends StatefulWidget {
  const ChatThread({super.key, required this.id, required this.title, required this.isGroup, required this.currentUserId, this.focusedMessageId});
  final String id, title, currentUserId;
  final bool isGroup;
  final String? focusedMessageId;
  @override State<ChatThread> createState() => _ChatThreadState();
}
class _ChatThreadState extends State<ChatThread> {
  final api = CloudApi();
  final photos = <String, Future<Uint8List>>{};
  final receipts = <String, bool>{};
  final hiddenHere = <String>{};
  bool deletingMessage = false;
  String? pendingHiddenMessageId;
  String? deleteError;
  bool deletingConversation = false;

  Future<void> deleteConversation() async {
    if (deletingConversation) return;
    setState(() => deletingConversation = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete conversation for me?'),
          content: const Text('This hides the existing messages from your account. Other participants can still see them. A new message can bring the conversation back to your Messages list.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete for me')),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await api.request('DELETE', path);
      if (!mounted) return;
      if (widget.focusedMessageId != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ChatInbox(currentUserId: widget.currentUserId),
        ));
      } else {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => deleteError = 'Could not delete this conversation for you. $error');
    } finally {
      if (mounted) setState(() => deletingConversation = false);
    }
  }

  Future<void> deleteForMe(String id) async {
    if (deletingMessage) return;
    deletingMessage = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete for me?'),
          content: const Text('Other people in the conversation will still be able to see this message.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete for me')),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      setState(() {
        pendingHiddenMessageId = id;
        deleteError = null;
      });
      await api.request('DELETE', 'chat/messages/$id/mine');
      if (!mounted) return;
      setState(() {
        hiddenHere.add(id);
        pendingHiddenMessageId = null;
        messages.removeWhere((message) => message['id'] == id);
        if (id == widget.focusedMessageId) viewingFocusedMessage = false;
      });
      await load();
    } catch (error) {
      if (mounted) setState(() {
        pendingHiddenMessageId = null;
        deleteError = 'Could not delete this message for you. $error';
      });
    } finally {
      deletingMessage = false;
    }
  }
  bool checkingReceipts = false;

  Future<void> updateReceipts() async {
    if (!mounted || checkingReceipts) return;
    checkingReceipts = true;
    final received = <String>[];
    final outgoing = <String>[];
    final reading = ModalRoute.of(context)?.isCurrent == true &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    for (final message in messages) {
      final mine = message['senderId'] == widget.currentUserId;
      (mine ? outgoing : received).add(message['id'].toString());
    }
    try {
      final result = await api.request('POST', 'chat/receipts', {
        'received': received, 'outgoing': outgoing, 'read': reading,
      }) as List;
      if (mounted) setState(() {
        for (final item in result) {
          final id = item['id'].toString();
          receipts[id] = receipts[id] == true || item['read'] == true;
        }
      });
    } catch (_) {
      // Older servers still support sending and reading chat.
    } finally {
      checkingReceipts = false;
    }
  }

  Widget receiptIcon(String id) {
    final read = receipts[id];
    final label = read == true ? 'Read' : read == false ? 'Received' : 'Sent';
    return Tooltip(
      message: widget.isGroup && read != null ? '$label by a group recipient' : label,
      child: Icon(read == null ? Icons.check : Icons.done_all,
        color: read == true ? const Color(0xFF9DE9FF) : Colors.white70, size: 16),
    );
  }
  final message = TextEditingController();
  final scroll = ScrollController();
  final GlobalKey newestMessageKey = GlobalKey();
  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = newestMessageKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, alignment: 1.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      } else if (scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    });
  }
  Timer? refreshTimer;
  HubConnection? liveConnection;
  bool liveConnected = false;
  List<Map<String, dynamic>> messages = [];
  bool sending = false;
  bool uploading = false;
  final List<PlatformFile> pendingAttachments = [];
  final Map<String, List<Map<String,dynamic>>> attachmentCache = {};
  final Map<String, Future<Uint8List>> imageDownloadCache = {};
  String? error;
  bool viewingFocusedMessage = false;
  String get path => widget.isGroup ? 'chat/groups/${widget.id}' : 'chat/direct/${widget.id}';
  @override void initState() {
    super.initState();
    viewingFocusedMessage = widget.focusedMessageId != null;
    load();
    connectLive();
    // Resilience: refresh periodically when disconnected, including after app resume.
    refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!liveConnected) { connectLive(); load(); }
      updateReceipts();
    });
  }
  Future<void> connectLive() async {
    if (liveConnected || !mounted) return;
    try {
      final token = await secureStorage.read(key: 'access_token');
      if (token == null || !apiUrlAllowed) return;
      final url = '${apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/hubs/chat';
      final connection = HubConnectionBuilder().withUrl(url,
        options: HttpConnectionOptions(accessTokenFactory: () async =>
          await secureStorage.read(key: 'access_token') ?? '')).build();
      connection.on('messageReceived', (arguments) {
        if (!mounted || arguments == null || arguments.isEmpty) return;
        final payload = arguments.first;
        if (payload is! Map) return;
        final m = Map<String, dynamic>.from(payload);
        final group = m['groupId']?.toString().toLowerCase();
        final sender = m['senderId']?.toString().toLowerCase();
        final recipient = m['recipientId']?.toString().toLowerCase();
        final threadId = widget.id.toLowerCase();
        final mine = widget.currentUserId.toLowerCase();
        if ((widget.isGroup && group == threadId) ||
            (!widget.isGroup && group == null &&
              ((sender == threadId && recipient == mine) ||
               (sender == mine && recipient == threadId)))) {
          load(); // Server remains source of truth; read watermark updated after fetch.
        }
      });
      connection.onclose(({error}) {
        liveConnected = false;
        if (mounted) load();
      });
      await connection.start();
      if (!mounted) { await connection.stop(); return; }
      liveConnection = connection;
      liveConnected = true;
      await load();
    } catch (_) { liveConnected = false; }
  }
  @override void dispose() {
    refreshTimer?.cancel();
    liveConnection?.stop();
    message.dispose(); scroll.dispose(); super.dispose();
  }
  Future<void> load() async {
    try {
      final focused = viewingFocusedMessage;
      final data = await api.list(focused ? '$path?focus=${widget.focusedMessageId}' : path);
      if (focused != viewingFocusedMessage) return;
      if (mounted) { setState(() {
        messages = data.where((message) => !hiddenHere.contains(message['id'])).toList();
        error = null;
      });
        updateReceipts();
        if (focused) {
          scrollToBottom();
        } else {
          await api.request('POST', 'chat/${widget.isGroup ? 'group' : 'direct'}/${widget.id}/read');
        }
      }
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  Future<void> attach() async {
    if (uploading || sending) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg','jpeg','png','webp','pdf','txt'], allowMultiple: true, withData: true);
    if (picked == null || !mounted) return;
    final combined = [...pendingAttachments, ...picked.files];
    final totalBytes = combined.fold<int>(0, (sum, f) => sum + f.size);
    if (combined.length > 5 || combined.any((f) => f.bytes == null || f.size > 20 * 1024 * 1024) || totalBytes > 25 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 5 files, 20 MB each, 25 MB total.')));
      return;
    }
    setState(() { pendingAttachments..clear()..addAll(combined); });
  }
  Future<List<Map<String,dynamic>>> attachments(String id) async {
    if (attachmentCache.containsKey(id)) return attachmentCache[id]!;
    final found = await api.list('chat/messages/$id/attachments');
    attachmentCache[id] = found;
    return found;
  }
  Widget attachmentView(Map<String,dynamic> a, bool mine) {
    final id = a['id'].toString();
    final name = a['fileName'].toString();
    final type = a['contentType'].toString();
    if (type.startsWith('image/')) {
      return FutureBuilder<Uint8List>(future: imageDownloadCache.putIfAbsent(id, () => api.downloadAttachment(id)), builder: (ctx, snapshot) {
        if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(8), child: Text('Image unavailable'));
        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
        return Semantics(
          button: true, label: 'Open photo full screen',
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
              ChatPhotoViewer(bytes: snapshot.data!, name: name, type: type))),
            child: Image.memory(snapshot.data!, width: 240, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('Image unavailable')),
          ),
        );
      });
    }
    return ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.description, color: mine ? Colors.white : chatBurgundy), title: Text(name, style: TextStyle(color: mine ? Colors.white : Colors.black87)), subtitle: Text('Document attachment', style: TextStyle(color: mine ? Colors.white70 : Colors.black54)), onTap: () async {
      try {
        final bytes = await api.downloadAttachment(id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded ${bytes.length} bytes. Saving/opening documents is coming next.')));
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    });
  }
  Future<void> send() async {
    final text = message.text.trim();
    if (sending || text.length > 4000 || (text.isEmpty && pendingAttachments.isEmpty)) return;
    setState(() => sending = true);
    try {
      if (pendingAttachments.isEmpty) {
        await api.add(path, {'text': text});
      } else {
        final files = pendingAttachments.map((f) => http.MultipartFile.fromBytes('files', f.bytes!, filename: f.name)).toList();
        await api.sendCombinedMessage(widget.isGroup ? 'group' : 'direct', widget.id, text, files);
      }
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      message.clear();
      setState(() => pendingAttachments.clear());
      await load();
      scrollToBottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), actions: [
      if (viewingFocusedMessage)
        TextButton(onPressed: () async {
          setState(() => viewingFocusedMessage = false);
          await load();
          scrollToBottom();
        }, child: const Text('Latest')),
        PopupMenuButton<String>(
          tooltip: 'Conversation options',
          enabled: !deletingConversation,
          onSelected: (_) => deleteConversation(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'delete', child: Text('Delete conversation for me')),
          ],
        ),
    ]),
    body: Column(children: [
      if (deleteError != null) Padding(padding: const EdgeInsets.all(8), child: Text(deleteError!, style: const TextStyle(color: Colors.red))),
      if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: const TextStyle(color: Colors.red))),
      Expanded(child: Builder(builder: (context) {
        final visible = messages.where((message) => message['id'].toString() != pendingHiddenMessageId).toList();
        return ListView.builder(controller: scroll, reverse: viewingFocusedMessage, padding: const EdgeInsets.all(12), itemCount: visible.length, itemBuilder: (context, index) {
        final i = viewingFocusedMessage ? visible.length - 1 - index : index;
        final m = visible[i], mine = m['senderId'].toString().toLowerCase() == widget.currentUserId.toLowerCase();
        final time = DateTime.tryParse(m['createdUtc']?.toString() ?? '')?.toLocal();
        return Align(key: i == visible.length - 1 ? newestMessageKey : null, alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: GestureDetector(
          onLongPress: () => deleteForMe(m['id'].toString()),
          child: Container(
          constraints: const BoxConstraints(maxWidth: 310), margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: mine ? chatBurgundy : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: m['id'] == widget.focusedMessageId ? Border.all(color: Colors.amber.shade700, width: 2) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Flexible(child: Padding(padding: const EdgeInsets.fromLTRB(12, 12, 0, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine) chatAvatar(photos.putIfAbsent(m['senderId'].toString(), () => api.downloadAvatar(userId: m['senderId'].toString())), radius: 13),
            if (widget.isGroup && !mine) Text('Member ${m['senderId'].toString().substring(0, 8)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (m['text'].toString().isNotEmpty) Text(m['text'].toString(), style: TextStyle(color: mine ? Colors.white : Colors.black87)),
             FutureBuilder<List<Map<String,dynamic>>>(future: attachments(m['id'].toString()), builder: (ctx, snapshot) => snapshot.hasData ? Column(children: snapshot.data!.map((a) => attachmentView(a, mine)).toList()) : const SizedBox.shrink()),
            if (time != null) Text('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : Colors.grey)),
            if (mine) receiptIcon(m['id'].toString()),
          ]))),
          PopupMenuButton<String>(
            tooltip: 'Message options',
            iconColor: mine ? Colors.white : Colors.black87,
            onSelected: (_) => deleteForMe(m['id'].toString()),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete for me')),
            ],
          ),
          ]),
        )));
      }); })),
      if (pendingAttachments.isNotEmpty) SizedBox(height: 105, child: ListView(scrollDirection: Axis.horizontal, children: pendingAttachments.map((f) => Padding(padding: const EdgeInsets.all(4), child: SizedBox(width: 95, child: Stack(children: [Positioned.fill(child: Column(children: [Expanded(child: f.bytes != null && ['jpg','jpeg','png','webp'].contains(f.extension?.toLowerCase()) ? Image.memory(f.bytes!, fit: BoxFit.cover, cacheWidth: 200, cacheHeight: 200, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)) : const Icon(Icons.description, size: 48)), Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))])), Positioned(right: 0, top: 0, child: IconButton(onPressed: sending ? null : () => setState(() => pendingAttachments.remove(f)), icon: const Icon(Icons.cancel, color: Colors.red), tooltip: 'Remove attachment'))])))).toList())),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        IconButton(tooltip: 'Attach photo or file', onPressed: uploading ? null : attach, icon: const Icon(Icons.attach_file, color: chatBurgundy)),
        Expanded(child: TextField(controller: message, maxLines: 3, minLines: 1, maxLength: 4000, decoration: const InputDecoration(hintText: 'Write a message...', counterText: ''))),
        IconButton(onPressed: sending ? null : send, icon: const Icon(Icons.send, color: chatBurgundy)),
      ]))),
    ]),
  );
}




















