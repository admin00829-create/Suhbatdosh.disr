import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Emulator: http://10.0.2.2:3000 | Haqiqiy telefon: https://sizning-server.uz
const serverUrl = 'http://10.0.2.2:3000';
const cyan = Color(0xFF19D3FF);

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'SUHBATDOSH AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF050B14)),
        home: const ChatPage(),
      );
}

class Msg {
  final String role, text;
  Msg(this.role, this.text);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final stt = SpeechToText();
  final tts = FlutterTts();
  final msgs = <Msg>[Msg('assistant', "Salom! Men SUHBATDOSH AI. Bilganimni aytaman, bilmaganimni sizdan so'rab o'rganaman.")];
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  bool voice = false, busy = false, speaking = false, ready = false;
  String deviceId = '', status = 'TIZIM FAOL', sttLocale = '';

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    deviceId = p.getString('id') ?? 'd${Random().nextInt(1 << 31)}${DateTime.now().millisecondsSinceEpoch}';
    await p.setString('id', deviceId);

    ready = await stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (voice && !busy && !speaking) Future.delayed(const Duration(milliseconds: 500), listen);
        }
      },
      onError: (e) {
        if (e.errorMsg.contains('permission')) setState(() => voice = false);
      },
    );
    if (ready) {
      final locs = await stt.locales();
      final uz = locs.where((l) => l.localeId.toLowerCase().startsWith('uz')).toList();
      sttLocale = uz.isNotEmpty ? uz.first.localeId : '';
    }
    final ttsUz = await tts.isLanguageAvailable('uz-UZ');
    await tts.setLanguage(ttsUz == true ? 'uz-UZ' : 'ru-RU');
    await tts.awaitSpeakCompletion(true);
    setState(() {});
  }

  Future<void> listen() async {
    if (!ready || busy || speaking || stt.isListening || !mounted) return;
    setState(() => status = 'TINGLAYAPMAN…');
    await stt.listen(
      localeId: sttLocale.isEmpty ? null : sttLocale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        if (r.finalResult) send(r.recognizedWords);
      },
    );
  }

  Future<void> send(String t) async {
    t = t.trim();
    if (t.isEmpty || busy) return;
    setState(() {
      msgs.add(Msg('user', t));
      busy = true;
      status = "O'YLAYAPMAN…";
    });
    _down();
    String reply;
    try {
      final hist = msgs.sublist(max(0, msgs.length - 10));
      final r = await http
          .post(Uri.parse('$serverUrl/chat'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'deviceId': deviceId,
                'messages': hist.map((m) => {'role': m.role, 'content': m.text}).toList(),
              }))
          .timeout(const Duration(seconds: 60));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      reply = (j['reply'] ?? "Javob olinmadi.").toString();
      if ((j['learned'] ?? 0) > 0) msgs.add(Msg('note', '🧠 Yangi bilim eslab qolindi'));
    } catch (e) {
      reply = "Serverga ulanib bo'lmadi. Qayta urinib ko'ring.";
    }
    setState(() {
      msgs.add(Msg('assistant', reply));
      busy = false;
      speaking = true;
      status = 'GAPIRYAPMAN…';
    });
    _down();
    await tts.speak(reply);
    if (!mounted) return;
    setState(() {
      speaking = false;
      status = voice ? 'TINGLAYAPMAN…' : 'TIZIM FAOL';
    });
    if (voice) listen();
  }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  void toggleVoice() {
    setState(() => voice = !voice);
    if (voice) {
      listen();
    } else {
      stt.stop();
      tts.stop();
      setState(() {
        speaking = false;
        status = 'TIZIM FAOL';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = busy || speaking || stt.isListening;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cyan, width: 2),
                  boxShadow: [BoxShadow(color: cyan.withOpacity(active ? .9 : .4), blurRadius: active ? 24 : 12)],
                ),
                child: Center(child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: cyan, shape: BoxShape.circle))),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SUHBATDOSH AI', style: TextStyle(color: cyan, letterSpacing: 3, fontWeight: FontWeight.bold)),
                Text(status, style: const TextStyle(color: Color(0xFF6B8AA3), fontSize: 11, letterSpacing: 1)),
              ]),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF12304D)),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(14),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                if (m.role == 'note') {
                  return Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(m.text, style: const TextStyle(color: Color(0xFF6B8AA3), fontSize: 12))));
                }
                final me = m.role == 'user';
                return Align(
                  alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
                    decoration: BoxDecoration(
                      color: me ? const Color(0xFF0A3A55) : const Color(0xFF0B1626),
                      border: me ? null : Border.all(color: const Color(0xFF12304D)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(m.text, style: const TextStyle(fontSize: 15, height: 1.4)),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF12304D)))),
            child: Row(children: [
              _btn(Icons.headset_mic, voice, toggleVoice),
              const SizedBox(width: 6),
              _btn(Icons.mic, stt.isListening, listen),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  onSubmitted: (t) {
                    ctrl.clear();
                    send(t);
                  },
                  decoration: InputDecoration(
                    hintText: "Savol bering yoki o'rgating…",
                    filled: true,
                    fillColor: const Color(0xFF0B1626),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF12304D))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _btn(Icons.send, true, () {
                final t = ctrl.text;
                ctrl.clear();
                send(t);
              }),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _btn(IconData i, bool on, VoidCallback f) => InkWell(
        onTap: f,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? cyan : null, border: Border.all(color: cyan)),
          child: Icon(i, color: on ? const Color(0xFF001018) : cyan, size: 20),
        ),
      );
}
