import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String apiKey = "AIzaSyA-DsUGNFOHWfNV5DmgFUkva2JaPyLLHHg";

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final GenerativeModel _model;
  late final ChatSession _chat;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  String _speechText = '';
  bool _isConnectedToWifi = true;

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(model: 'gemini-pro', apiKey: apiKey);
    _chat = _model.startChat();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    requestMicrophonePermission();
    _checkConnectivity();
    Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('chat_history') ?? [];
    setState(() {
      _messages.addAll(
        history.map((msg) {
          final parts = msg.split('::');
          return ChatMessage(
            text: parts[0],
            isUser: parts[1] == 'user',
            time: parts[2],
          );
        }).toList(),
      );
    });
  }

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = _messages
        .map(
            (msg) => '${msg.text}::${msg.isUser ? 'user' : 'bot'}::${msg.time}')
        .toList();
    await prefs.setStringList('chat_history', history);
  }

  Future<void> requestMicrophonePermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  Future<void> _checkConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    _updateConnectionStatus(connectivityResult);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    setState(() {
      _isConnectedToWifi = result == ConnectivityResult.wifi;
    });
  }

  void _scrollDown() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(text);
  }

  Future<void> _sendChatMessage(String message) async {
    String formattedTime = DateFormat('kk:mm').format(DateTime.now());
    setState(() {
      _messages
          .add(ChatMessage(text: message, isUser: true, time: formattedTime));
    });
    try {
      _messages
          .add(ChatMessage(text: '...', isUser: false, time: formattedTime));
      final response = await _chat.sendMessage(Content.text(message));
      final text = response.text ?? 'No se recibió respuesta';
      setState(() {
        _messages.removeLast();
        _messages
            .add(ChatMessage(text: text, isUser: false, time: formattedTime));
      });
      _scrollDown();
      await _speak(text);
      _saveChatHistory();
    } catch (e) {
      setState(() {
        _messages.add(
            ChatMessage(text: 'Error: $e', isUser: false, time: formattedTime));
      });
    } finally {
      _textController.clear();
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done') {
          _stopListening();
        }
      },
      onError: (val) => print('Error del reconocimiento de voz: $val'),
    );

    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (val) {
          setState(() {
            _speechText = val.recognizedWords;
            _textController.text = _speechText;
          });
        },
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
      );
    }
  }

  void _stopListening() {
    setState(() => _isListening = false);
    _speech.stop();
  }

  void _showConversationHistory() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Historial de Conversación'),
          content: SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ListTile(
                  title: Text(
                    message.text,
                    style: TextStyle(
                        color: message.isUser ? Colors.blue : Colors.black),
                  ),
                  subtitle:
                      Text(message.time, style: const TextStyle(fontSize: 12)),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _clearConversation() {
    setState(() {
      _messages.clear();
    });
    _saveChatHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA),
      appBar: AppBar(
        title: const Text('Mi chat inteligente'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showConversationHistory,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clearConversation,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ChatBubble(message: _messages[index]);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic_off : Icons.mic,
                    color: Colors.blue,
                    size: 32,
                  ),
                  onPressed: _isListening ? _stopListening : _startListening,
                ),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 48),
                    child: TextField(
                      onSubmitted:
                          _isConnectedToWifi ? _sendChatMessage : null,
                      controller: _textController,
                      maxLines: 1,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12.0,
                          horizontal: 16.0,
                        ),
                        hintText: 'Envía un mensaje...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.blue,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isConnectedToWifi
                      ? () => _sendChatMessage(_textController.text)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final String time;

  ChatMessage({required this.text, required this.isUser, required this.time});
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) // Avatar del sistema
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: AssetImage('assets/UP.jpg'), // Imagen del sistema
                  fit: BoxFit.cover,
                ),
              ),
            ),
          if (!message.isUser) const SizedBox(width: 8.0), // Espacio entre avatar y mensaje

          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  vertical: 10.0, horizontal: 16.0),
              decoration: BoxDecoration(
                color: message.isUser ? Colors.blue[100] : Colors.grey[300],
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: const TextStyle(fontSize: 16.0),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    message.time,
                    style: const TextStyle(
                      fontSize: 10.0,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (message.isUser) const SizedBox(width: 8.0), // Espacio entre mensaje y avatar
          if (message.isUser) // Avatar del usuario
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: AssetImage('assets/usuario.jpg'), // Imagen del usuario
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
