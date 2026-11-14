import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart'
    show MobileScanner, BarcodeCapture;
import 'package:qr_flutter/qr_flutter.dart'
    show QrImageView, QrErrorCorrectLevel;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OakApp());
}

const MethodChannel _appsChannel = MethodChannel('oak/apps');
/// Home-screen widget / Quick Settings tile bridge (see scripts/patch_android.sh)
const MethodChannel _ctlChannel = MethodChannel('oak/ctl');

// ---------------------------------------------------------------------------
// App + theme
// ---------------------------------------------------------------------------

class OakApp extends StatefulWidget {
  const OakApp({super.key});

  @override
  State<OakApp> createState() => _OakAppState();
}

class _OakAppState extends State<OakApp> {
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('theme');
      if (!mounted) return;
      setState(() {
        _mode = s == 'light'
            ? ThemeMode.light
            : s == 'dark'
                ? ThemeMode.dark
                : ThemeMode.system;
      });
    } catch (_) {}
  }

  Future<void> _setTheme(ThemeMode m) async {
    setState(() => _mode = m);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme', m.name);
    } catch (_) {}
  }

  ThemeData _theme(Brightness b) {
    final cs = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: b,
    );
    return ThemeData(useMaterial3: true, colorScheme: cs);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tulip VPN',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      home: HomePage(themeMode: _mode, onTheme: _setTheme),
    );
  }
}

// ---------------------------------------------------------------------------
// Liquid Glass look
// ---------------------------------------------------------------------------

const LinearGradient _accentGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF3B82F6), Color(0xFF22D3EE)],
);

class _P {
  _P(this.dark);
  final bool dark;

  static _P of(BuildContext c) =>
      _P(Theme.of(c).brightness == Brightness.dark);

  Color get base =>
      dark ? const Color(0xFF0B1030) : const Color(0xFFEEF0FB);
  Color get blob1 => dark
      ? const Color(0xFF3B82F6).withOpacity(.55)
      : const Color(0xFF9FD0FF);
  Color get blob2 => dark
      ? const Color(0xFF8B5CF6).withOpacity(.5)
      : const Color(0xFFC9C3FA);
  Color get blob3 => dark
      ? const Color(0xFF14B8A6).withOpacity(.45)
      : const Color(0xFF9BF0EE);
  Color get text => dark ? Colors.white : const Color(0xFF111322);
  Color get sub =>
      dark ? const Color(0xCCFFFFFF) : const Color(0xFF4A4F6A);
  Color get glassA => dark
      ? Colors.white.withOpacity(.22)
      : Colors.white.withOpacity(.92);
  Color get glassB => dark
      ? Colors.white.withOpacity(.08)
      : Colors.white.withOpacity(.55);
  Color get border => dark
      ? Colors.white.withOpacity(.3)
      : Colors.white.withOpacity(.95);
  Color get line => dark
      ? Colors.white.withOpacity(.16)
      : const Color(0xFF505A96).withOpacity(.14);
  Color get chipBg => dark
      ? Colors.white.withOpacity(.18)
      : const Color(0xFF3B82F6).withOpacity(.13);
  Color get chipText => dark ? Colors.white : const Color(0xFF1D4ED8);
  Color get inner => dark
      ? Colors.black.withOpacity(.2)
      : Colors.white.withOpacity(.7);
  Color get panel => dark
      ? Colors.white.withOpacity(.1)
      : Colors.white.withOpacity(.75);
  Color get blue =>
      dark ? const Color(0xFF7DB4FF) : const Color(0xFF1D4ED8);
  Color get good =>
      dark ? const Color(0xFF4ADE80) : const Color(0xFF047857);
  Color get warn =>
      dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  Color get bad =>
      dark ? const Color(0xFFFDA4AF) : const Color(0xFFBE123C);
  /// Delay colour coding: green = fast, yellow = slow, red = very slow/timeout
  Color pingColor(int ms) {
    if (ms < 0 || ms >= 700) {
      return dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    }
    if (ms >= 300) {
      return dark ? const Color(0xFFFACC15) : const Color(0xFFCA8A04);
    }
    return dark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  }

  Color get off =>
      dark ? Colors.white.withOpacity(.22) : const Color(0xFFC3C7DD);
  Color get ring =>
      dark ? const Color(0x99FFFFFF) : const Color(0xFF8A90B0);
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = _P.of(context);
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.glassA, p.glassB],
            ),
            border: Border.all(color: p.border, width: 1.5),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.p});
  final _P p;

  Widget _blob(Color c, double s) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, c.withOpacity(0)]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: p.base,
      child: Stack(
        children: [
          Positioned(top: -90, left: -90, child: _blob(p.blob1, 360)),
          Positioned(top: 200, right: -140, child: _blob(p.blob2, 380)),
          Positioned(bottom: -110, left: -70, child: _blob(p.blob3, 360)),
        ],
      ),
    );
  }
}

Widget _checkDot(_P p, bool on) {
  return on
      ? Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, gradient: _accentGrad),
          child:
              const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        )
      : Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.ring, width: 1.5),
          ),
        );
}

// ---------------------------------------------------------------------------
// Models + key parsing
// ---------------------------------------------------------------------------

const List<String> _schemes = [
  'vmess://',
  'vless://',
  'trojan://',
  'ss://',
  'socks://',
  'hysteria2://',
  'hy2://',
  'hysteria://',
];

const String _ssconf = 'ssconf://';

class Server {
  Server(
      {required this.id,
      required this.name,
      required this.link,
      this.ping,
      this.subId});

  final String id;
  String name;
  String link;

  /// Subscription this server came from (null = added by hand)
  String? subId;

  /// null = not tested, -1 = failed, otherwise milliseconds
  int? ping;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'link': link,
        if (subId != null) 'subId': subId,
      };

  factory Server.fromJson(Map<String, dynamic> j) => Server(
        id: j['id'] as String,
        name: j['name'] as String,
        link: j['link'] as String,
        subId: j['subId'] as String?,
      );

  /// Server address taken from the key (null if it can't be read).
  String? get host {
    final t = link.trim();
    try {
      if (t.startsWith('{')) {
        final j = jsonDecode(t) as Map<String, dynamic>;
        for (final o in (j['outbounds'] as List? ?? const [])) {
          final st = (o as Map)['settings'] as Map?;
          if (st == null) continue;
          final v = (st['vnext'] as List?)?.first as Map?;
          if (v?['address'] != null) return v!['address'].toString();
          final sv = (st['servers'] as List?)?.first as Map?;
          if (sv?['address'] != null) return sv!['address'].toString();
        }
        return null;
      }
      final low = t.toLowerCase();
      if (low.startsWith('vmess://')) {
        final body = t.substring(8).split('#').first;
        final j = jsonDecode(_b64(body)) as Map<String, dynamic>;
        return j['add']?.toString();
      }
      if (low.startsWith('ss://')) {
        var body = t.substring(5).split('#').first.split('?').first;
        if (!body.contains('@')) body = _b64(body);
        body = body.substring(body.lastIndexOf('@') + 1);
        final i = body.lastIndexOf(':');
        return (i > 0 ? body.substring(0, i) : body).replaceAll(RegExp(r'[\[\]/]'), '');
      }
      final u = Uri.parse(t);
      return u.host.isEmpty ? null : u.host;
    } catch (_) {
      return null;
    }
  }

  /// Country flag emoji (🌐 when the country can't be told).
  String get flag {
    final cc = countryCodeOf(name, host);
    return cc == null ? '\u{1F310}' : flagEmoji(cc);
  }

  /// Name without a leading/embedded flag emoji (the flag is drawn separately).
  String get displayName {
    final r = name.runes.where((c) => c < 0x1F1E6 || c > 0x1F1FF);
    final out = String.fromCharCodes(r).trim();
    return out.isEmpty ? name : out;
  }

  String get type {
    final t = link.trim();
    if (t.startsWith('{')) return 'JSON';
    final i = t.indexOf('://');
    return i > 0 ? t.substring(0, i).toUpperCase() : 'KEY';
  }
}


// ---------------------------------------------------------------------------
// Country flag detection (offline: flag emoji / country name / code in the
// server name, otherwise the domain's country TLD)
// ---------------------------------------------------------------------------

const String _isoCodes =
    'AD AE AF AG AL AM AO AR AT AU AZ BA BB BD BE BF BG BH BI BJ BN BO BR BS BT '
    'BW BY BZ CA CD CF CG CH CI CL CM CN CO CR CU CV CY CZ DE DJ DK DM DO DZ EC '
    'EE EG ER ES ET FI FJ FR GA GB GE GH GM GN GQ GR GT GY HK HN HR HT HU ID IE '
    'IL IN IQ IR IS IT JM JO JP KE KG KH KM KP KR KW KZ LA LB LI LK LR LS LT LU '
    'LV LY MA MC MD ME MG MK ML MM MN MO MR MT MU MV MW MX MY MZ NA NE NG NI NL '
    'NO NP NZ OM PA PE PG PH PK PL PT PY QA RO RS RU RW SA SC SD SE SG SI SK SL '
    'SN SO SR SV SY TG TH TJ TM TN TR TT TW TZ UA UG US UY UZ VE VN YE ZA ZM ZW';
final Set<String> _isoSet = _isoCodes.split(' ').toSet();

/// 2-letter tokens that are common in key names but are not countries.
const Set<String> _notCountry = {'WS', 'IP', 'VM', 'TV', 'OK', 'XX', 'NA', 'ID'};

/// TLDs that are generic in practice.
const Set<String> _genericTld = {
  'io', 'co', 'me', 'tv', 'cc', 'ws', 'to', 'ai', 'fm', 'ly', 'gg', 'sh',
  'la', 'am',
};

const Map<String, String> _countryWords = {
  'singapore': 'SG', 'japan': 'JP', 'tokyo': 'JP', 'osaka': 'JP',
  'united states': 'US', 'america': 'US', 'los angeles': 'US',
  'new york': 'US', 'seattle': 'US', 'dallas': 'US', 'chicago': 'US',
  'miami': 'US', 'united kingdom': 'GB', 'england': 'GB', 'london': 'GB',
  'germany': 'DE', 'frankfurt': 'DE', 'berlin': 'DE', 'france': 'FR',
  'paris': 'FR', 'netherlands': 'NL', 'amsterdam': 'NL', 'hong kong': 'HK',
  'hongkong': 'HK', 'korea': 'KR', 'seoul': 'KR', 'india': 'IN',
  'mumbai': 'IN', 'thailand': 'TH', 'bangkok': 'TH', 'myanmar': 'MM',
  'burma': 'MM', 'yangon': 'MM', 'malaysia': 'MY', 'kuala lumpur': 'MY',
  'indonesia': 'ID', 'jakarta': 'ID', 'vietnam': 'VN', 'philippines': 'PH',
  'taiwan': 'TW', 'china': 'CN', 'russia': 'RU', 'moscow': 'RU',
  'turkey': 'TR', 'istanbul': 'TR', 'canada': 'CA', 'toronto': 'CA',
  'australia': 'AU', 'sydney': 'AU', 'brazil': 'BR', 'dubai': 'AE',
  'emirates': 'AE', 'finland': 'FI', 'helsinki': 'FI', 'sweden': 'SE',
  'stockholm': 'SE', 'norway': 'NO', 'poland': 'PL', 'warsaw': 'PL',
  'italy': 'IT', 'milan': 'IT', 'spain': 'ES', 'madrid': 'ES',
  'switzerland': 'CH', 'zurich': 'CH', 'ireland': 'IE', 'israel': 'IL',
  'ukraine': 'UA', 'romania': 'RO', 'bulgaria': 'BG', 'cambodia': 'KH',
  'laos': 'LA', 'bangladesh': 'BD', 'pakistan': 'PK', 'nepal': 'NP',
  'sri lanka': 'LK', 'mexico': 'MX', 'argentina': 'AR', 'chile': 'CL',
  'south africa': 'ZA', 'egypt': 'EG', 'kazakhstan': 'KZ', 'austria': 'AT',
  'belgium': 'BE', 'denmark': 'DK', 'portugal': 'PT', 'greece': 'GR',
  'czech': 'CZ', 'hungary': 'HU', 'lithuania': 'LT', 'latvia': 'LV',
  'estonia': 'EE', 'iceland': 'IS', 'new zealand': 'NZ', 'saudi': 'SA',
  'qatar': 'QA', 'iran': 'IR', 'iraq': 'IQ',
};

const Map<String, String> _countryAliases = {
  'USA': 'US', 'UK': 'GB', 'UAE': 'AE', 'KOR': 'KR', 'JPN': 'JP',
  'SGP': 'SG', 'GER': 'DE', 'DEU': 'DE', 'FRA': 'FR', 'NLD': 'NL',
  'THA': 'TH', 'MMR': 'MM', 'IND': 'IN', 'CAN': 'CA', 'AUS': 'AU',
  'RUS': 'RU', 'TUR': 'TR', 'HKG': 'HK', 'TWN': 'TW', 'VNM': 'VN',
  'MYS': 'MY', 'IDN': 'ID', 'PHL': 'PH', 'BRA': 'BR',
};

String flagEmoji(String cc) => String.fromCharCodes(
    cc.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 65));

String? countryCodeOf(String name, String? host) {
  // 1) a flag emoji already in the name
  final runes = name.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final a = runes[i], b = runes[i + 1];
    if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
      return String.fromCharCodes([a - 0x1F1E6 + 65, b - 0x1F1E6 + 65]);
    }
  }
  // 2) country / city name
  final low = name.toLowerCase();
  for (final e in _countryWords.entries) {
    if (low.contains(e.key)) return e.value;
  }
  // 3) UPPERCASE code token: "SG-01", "US_West", "JPN"
  for (final t in name.split(RegExp(r'[^A-Za-z]+'))) {
    if (t.length < 2 || t != t.toUpperCase()) continue;
    if (_countryAliases.containsKey(t)) return _countryAliases[t];
    if (t.length == 2 && _isoSet.contains(t) && !_notCountry.contains(t)) {
      return t;
    }
  }
  // 4) country TLD of the server address
  if (host != null && host.contains('.')) {
    final tld = host.split('.').last.toLowerCase();
    if (tld.length == 2 && !_genericTld.contains(tld)) {
      final up = tld == 'uk' ? 'GB' : tld.toUpperCase();
      if (_isoSet.contains(up)) return up;
    }
  }
  return null;
}

class Resolved {
  Resolved(this.remark, this.config);
  final String remark;
  final String config;
}

/// Turns any supported key (vmess/vless/trojan/ss/... link or raw JSON config)
/// into a full Xray configuration. Throws if the key is invalid.
Resolved resolveKey(String key) {
  final t = key.trim();
  if (t.startsWith('{')) {
    jsonDecode(t); // validate
    return Resolved('Custom config', t);
  }
  final p = V2ray.parseFromURL(t);
  final remark = p.remark.trim().isEmpty ? 'Tulip VPN' : p.remark.trim();
  return Resolved(remark, p.getFullConfiguration());
}

/// Outline static keys end with "?outline=1" which the parser does not need.
String normalizeKey(String k) {
  final t = k.trim();
  if (t.toLowerCase().startsWith('ss://')) {
    return t.replaceAll('/?outline=1', '').replaceAll('?outline=1', '');
  }
  return t;
}

/// Picks every supported key (and subscription URL) out of pasted text.
List<String> extractKeys(String text) {
  final t = text.trim();
  if (t.isEmpty) return [];
  if (t.startsWith('{')) return [t];
  final out = <String>[];
  for (final raw in t.split(RegExp(r'\s+'))) {
    final w = raw.trim();
    if (w.isEmpty) continue;
    final lw = w.toLowerCase();
    if (_schemes.any(lw.startsWith) ||
        lw.startsWith(_ssconf) ||
        lw.startsWith('http://') ||
        lw.startsWith('https://')) {
      out.add(w);
    }
  }
  return out;
}

class Sub {
  Sub(
      {required this.id,
      required this.url,
      this.name,
      this.used,
      this.total,
      this.expire});

  final String id;
  String url;
  String? name;
  int? used;
  int? total;

  /// expiry as milliseconds since epoch (null = unknown / none)
  int? expire;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'used': used,
        'total': total,
        'expire': expire,
      };

  factory Sub.fromJson(Map<String, dynamic> j) => Sub(
        id: j['id'] as String,
        url: j['url'] as String,
        name: j['name'] as String?,
        used: (j['used'] as num?)?.toInt(),
        total: (j['total'] as num?)?.toInt(),
        expire: (j['expire'] as num?)?.toInt(),
      );

  int? get daysLeft {
    if (expire == null || expire! <= 0) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(expire!)
        .difference(DateTime.now())
        .inDays;
    return d < 0 ? 0 : d;
  }
}

class SubFetch {
  SubFetch(this.body, {this.used, this.total, this.expire, this.title});
  final String body;
  final int? used;
  final int? total;
  final int? expire;
  final String? title;
}

/// Hides the middle of a host: sorexyz.example.com -> sore****.com
String maskHost(String? h) {
  if (h == null || h.isEmpty) return '';
  if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(h)) {
    final x = h.split('.');
    return '${x[0]}.${x[1]}.*.*';
  }
  final i = h.lastIndexOf('.');
  if (i <= 0) return h.length <= 4 ? h : '${h.substring(0, 4)}****';
  final label = h.substring(0, i);
  final tld = h.substring(i);
  return label.length <= 4 ? h : '${label.substring(0, 4)}****$tld';
}

Future<SubFetch> fetchSubscriptionFull(String url) async {
  final r = await http
      .get(Uri.parse(url), headers: {'User-Agent': 'Tulip-VPN/1.0'})
      .timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) {
    throw Exception('HTTP ${r.statusCode}');
  }
  int? up, down, total, exp;
  final info = r.headers['subscription-userinfo'];
  if (info != null) {
    int? g(String k) {
      final m = RegExp('$k=(\\d+)').firstMatch(info);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    up = g('upload');
    down = g('download');
    total = g('total');
    exp = g('expire');
  }
  String? title = r.headers['profile-title'];
  if (title != null && title.startsWith('base64:')) {
    try {
      title = utf8.decode(base64.decode(base64.normalize(title.substring(7))));
    } catch (_) {
      title = null;
    }
  }
  final body = r.body.trim();
  final lower = body.toLowerCase();
  var out = body;
  if (!_schemes.any(lower.contains)) {
    try {
      final clean = body
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      out = utf8.decode(base64.decode(base64.normalize(clean)));
    } catch (_) {
      out = body;
    }
  }
  return SubFetch(
    out,
    used: (up == null && down == null) ? null : (up ?? 0) + (down ?? 0),
    total: total,
    expire: (exp == null || exp == 0) ? null : exp * 1000,
    title: (title == null || title.trim().isEmpty) ? null : title.trim(),
  );
}

Future<String> fetchSubscription(String url) async =>
    (await fetchSubscriptionFull(url)).body;

/// Outline dynamic access key: ssconf://host/path#Name
/// The server answers with either a JSON config or an ss:// link.
Future<List<String>> fetchOutlineDynamic(String link) async {
  final rest = link.substring(_ssconf.length);
  final hash = rest.indexOf('#');
  final path = hash >= 0 ? rest.substring(0, hash) : rest;
  var name = 'Outline';
  if (hash >= 0) {
    try {
      name = Uri.decodeComponent(rest.substring(hash + 1));
    } catch (_) {}
  }
  final r = await http
      .get(Uri.parse('https://$path'), headers: {'User-Agent': 'Tulip-VPN/1.0'})
      .timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) {
    throw Exception('HTTP ${r.statusCode}');
  }
  final body = r.body.trim();
  if (body.startsWith('{')) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final method = j['method'];
    final password = j['password'];
    final server = j['server'];
    final port = j['server_port'];
    if (method == null || password == null || server == null || port == null) {
      throw Exception('Outline config မပြည့်စုံပါ');
    }
    final user = base64Url
        .encode(utf8.encode('$method:$password'))
        .replaceAll('=', '');
    return ['ss://$user@$server:$port#${Uri.encodeComponent(name)}'];
  }
  return extractKeys(body)
      .where((k) => k.toLowerCase().startsWith('ss://'))
      .map(normalizeKey)
      .toList();
}

String formatBytes(num b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = b.toDouble();
  int i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

// ---------------------------------------------------------------------------
// Key <-> editable fields (VLESS / VMess / Trojan / Shadowsocks)
// ---------------------------------------------------------------------------

String _dec(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

String _decQ(String s) {
  try {
    return Uri.decodeQueryComponent(s);
  } catch (_) {
    return s;
  }
}

String _b64(String s) {
  final c = s
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll('-', '+')
      .replaceAll('_', '/');
  return utf8.decode(base64.decode(base64.normalize(c)));
}

class KeyForm {
  KeyForm(this.kind, this.data, [Map<String, bool>? nums])
      : nums = nums ?? {};

  /// vless | trojan | vmess | ss
  final String kind;

  /// remarks, address, port, id (uuid / password), method, password and
  /// every other query parameter / json entry of the key.
  final Map<String, String> data;

  /// vmess: which json entries were numbers originally
  final Map<String, bool> nums;

  String get netKey => kind == 'vmess' ? 'net' : 'type';
  String get hdrKey => kind == 'vmess' ? 'type' : 'headerType';

  static KeyForm? parse(String link) {
    try {
      return _parse(link.trim());
    } catch (_) {
      return null;
    }
  }

  static KeyForm? _parse(String s) {
    final i = s.indexOf('://');
    if (i <= 0) return null;
    final kind = s.substring(0, i).toLowerCase();
    var rest = s.substring(i + 3);
    if (kind == 'vmess') return _parseVmess(rest);
    if (kind != 'vless' && kind != 'trojan' && kind != 'ss') return null;

    var remark = '';
    final h = rest.indexOf('#');
    if (h >= 0) {
      remark = _dec(rest.substring(h + 1));
      rest = rest.substring(0, h);
    }
    var query = '';
    final qi = rest.indexOf('?');
    if (qi >= 0) {
      query = rest.substring(qi + 1);
      rest = rest.substring(0, qi);
    }
    while (rest.endsWith('/')) {
      rest = rest.substring(0, rest.length - 1);
    }

    String user;
    String hostPort;
    final at = rest.lastIndexOf('@');
    if (at < 0) {
      if (kind != 'ss') return null;
      final dec = _b64(rest); // method:password@host:port
      final a2 = dec.lastIndexOf('@');
      if (a2 < 0) return null;
      user = dec.substring(0, a2);
      hostPort = dec.substring(a2 + 1);
    } else {
      user = _dec(rest.substring(0, at));
      hostPort = rest.substring(at + 1);
    }

    String host;
    var port = '';
    if (hostPort.startsWith('[')) {
      final e = hostPort.indexOf(']');
      if (e < 0) return null;
      host = hostPort.substring(1, e);
      final r = hostPort.substring(e + 1);
      if (r.startsWith(':')) port = r.substring(1);
    } else {
      final c = hostPort.lastIndexOf(':');
      if (c < 0) {
        host = hostPort;
      } else {
        host = hostPort.substring(0, c);
        port = hostPort.substring(c + 1);
      }
    }

    final data = <String, String>{};
    if (query.isNotEmpty) {
      for (final pair in query.split('&')) {
        if (pair.isEmpty) continue;
        final e = pair.indexOf('=');
        final k = _decQ(e < 0 ? pair : pair.substring(0, e));
        final v = e < 0 ? '' : _decQ(pair.substring(e + 1));
        data[k] = v;
      }
    }
    data['remarks'] = remark;
    data['address'] = host;
    data['port'] = port;
    if (kind == 'ss') {
      var up = user;
      if (!up.contains(':')) up = _b64(up);
      final c = up.indexOf(':');
      if (c < 0) return null;
      data['method'] = up.substring(0, c);
      data['password'] = up.substring(c + 1);
    } else {
      data['id'] = user;
    }
    return KeyForm(kind, data);
  }

  static KeyForm? _parseVmess(String payload) {
    var rest = payload;
    final h = rest.indexOf('#');
    if (h >= 0) rest = rest.substring(0, h);
    final j = jsonDecode(_b64(rest));
    if (j is! Map) return null;
    final data = <String, String>{};
    final nums = <String, bool>{};
    j.forEach((k, v) {
      final key = k.toString();
      nums[key] = v is num;
      data[key] = v?.toString() ?? '';
    });
    data['remarks'] = data.remove('ps') ?? '';
    data['address'] = data.remove('add') ?? '';
    return KeyForm('vmess', data, nums);
  }

  String build() {
    final d = Map<String, String>.from(data);
    final remarks = (d.remove('remarks') ?? '').trim();
    final address = (d.remove('address') ?? '').trim();

    if (kind == 'vmess') {
      final m = <String, dynamic>{};
      m['v'] = '2';
      d.forEach((k, v) {
        final n = num.tryParse(v);
        m[k] = (nums[k] == true && n != null) ? n : v;
      });
      m['ps'] = remarks;
      m['add'] = address;
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(m)))}';
    }

    final port = (d.remove('port') ?? '').trim();
    String user;
    if (kind == 'ss') {
      final method = d.remove('method') ?? '';
      final pw = d.remove('password') ?? '';
      user = base64Url
          .encode(utf8.encode('$method:$pw'))
          .replaceAll('=', '');
    } else {
      user = Uri.encodeComponent(d.remove('id') ?? '');
    }
    final host = address.contains(':') ? '[$address]' : address;
    final qs = d.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final q = qs.isEmpty ? '' : '${kind == 'ss' ? '/?' : '?'}$qs';
    final frag = remarks.isEmpty ? '' : '#${Uri.encodeComponent(remarks)}';
    return '$kind://$user@$host${port.isEmpty ? '' : ':$port'}$q$frag';
  }
}

class _F {
  const _F(this.key, this.label,
      {this.choices, this.number = false, this.hint});
  final String key;
  final String label;
  final List<String>? choices;
  final bool number;
  final String? hint;
}

class _Sec {
  _Sec(this.title, this.fields);
  final String title;
  final List<_F> fields;
}

// ---------------------------------------------------------------------------
// Edit server page
// ---------------------------------------------------------------------------

class EditServerPage extends StatefulWidget {
  const EditServerPage({super.key, required this.server});
  final Server server;

  @override
  State<EditServerPage> createState() => _EditServerPageState();
}

class _EditServerPageState extends State<EditServerPage> {
  KeyForm? _form;
  bool _raw = false;
  final Map<String, TextEditingController> _ctrls = {};
  late final TextEditingController _rawCtrl;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _form = KeyForm.parse(widget.server.link);
    _raw = _form == null;
    _rawCtrl = TextEditingController(text: widget.server.link);
    _nameCtrl = TextEditingController(text: widget.server.name);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _rawCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String key) => _ctrls.putIfAbsent(
      key, () => TextEditingController(text: _form!.data[key] ?? ''));

  void _clearCtrls() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  String _val(String k) {
    final f = _form!;
    final v = f.data[k];
    if (v != null) return v;
    if (k == f.netKey) return 'tcp';
    if (k == f.hdrKey) return 'none';
    switch (k) {
      case 'security':
        return f.kind == 'trojan' ? 'tls' : 'none';
      case 'encryption':
        return 'none';
      case 'scy':
        return 'auto';
      case 'mode':
        return 'gun';
      default:
        return '';
    }
  }

  List<_Sec> _sections() {
    final f = _form!;
    final k = f.kind;
    final net = _val(f.netKey);
    final hdr = _val(f.hdrKey);
    final sec = k == 'vmess'
        ? (_val('tls') == 'tls' ? 'tls' : 'none')
        : _val('security');

    final server = <_F>[
      const _F('remarks', 'Remarks'),
      const _F('address', 'Address'),
      const _F('port', 'Port', number: true),
    ];
    if (k == 'vless') {
      server.addAll(const [
        _F('id', 'ID (UUID)'),
        _F('flow', 'Flow', choices: [
          '',
          'xtls-rprx-vision',
          'xtls-rprx-vision-udp443',
        ]),
        _F('encryption', 'Encryption'),
      ]);
    } else if (k == 'trojan') {
      server.add(const _F('id', 'Password'));
    } else if (k == 'vmess') {
      server.addAll(const [
        _F('id', 'ID (UUID)'),
        _F('aid', 'Alter ID', number: true),
        _F('scy', 'Cipher', choices: [
          'auto',
          'aes-128-gcm',
          'chacha20-poly1305',
          'none',
          'zero',
        ]),
      ]);
    } else {
      server.addAll(const [
        _F('method', 'Method', choices: [
          'aes-128-gcm',
          'aes-256-gcm',
          'chacha20-ietf-poly1305',
          'xchacha20-ietf-poly1305',
          '2022-blake3-aes-128-gcm',
          '2022-blake3-aes-256-gcm',
          '2022-blake3-chacha20-poly1305',
        ]),
        _F('password', 'Password'),
      ]);
    }

    final out = <_Sec>[_Sec('SERVER', server)];
    if (k == 'ss') return out;

    final tr = <_F>[
      _F(f.netKey, 'Network', choices: const [
        'tcp',
        'ws',
        'grpc',
        'kcp',
        'h2',
        'httpupgrade',
        'xhttp',
      ]),
    ];
    const hostPath = [_F('host', 'Host'), _F('path', 'Path')];
    if (net == 'ws' || net == 'h2' || net == 'httpupgrade' || net == 'xhttp') {
      tr.addAll(hostPath);
    } else if (net == 'tcp') {
      tr.add(_F(f.hdrKey, 'Header type', choices: const ['none', 'http']));
      if (hdr == 'http') tr.addAll(hostPath);
    } else if (net == 'kcp') {
      tr.add(_F(f.hdrKey, 'Header type', choices: const [
        'none',
        'srtp',
        'utp',
        'wechat-video',
        'dtls',
        'wireguard',
      ]));
    } else if (net == 'grpc') {
      if (k == 'vmess') {
        tr.add(const _F('path', 'Service name'));
      } else {
        tr.addAll(const [
          _F('serviceName', 'Service name'),
          _F('mode', 'Mode', choices: ['gun', 'multi']),
        ]);
      }
    }
    out.add(_Sec('TRANSPORT', tr));

    final sc = <_F>[
      k == 'vmess'
          ? const _F('tls', 'TLS', choices: ['', 'tls'])
          : const _F('security', 'Security',
              choices: ['none', 'tls', 'reality']),
    ];
    if (sec != 'none') {
      sc.addAll(const [
        _F('sni', 'SNI'),
        _F('fp', 'Fingerprint', choices: [
          '',
          'chrome',
          'firefox',
          'safari',
          'ios',
          'android',
          'edge',
          '360',
          'qq',
          'random',
          'randomized',
        ]),
        _F('alpn', 'ALPN', hint: 'h2,http/1.1'),
      ]);
      if (sec == 'tls' && k != 'vmess') {
        sc.add(const _F('allowInsecure', 'Allow insecure',
            choices: ['', '0', '1']));
      }
      if (sec == 'reality') {
        sc.addAll(const [
          _F('pbk', 'Public key'),
          _F('sid', 'Short ID'),
          _F('spx', 'Spider X'),
        ]);
      }
    }
    out.add(_Sec('SECURITY', sc));
    return out;
  }

  InputDecoration _deco(_P p, String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: p.inner,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _field(_P p, _F f) {
    if (f.choices != null) {
      final cur = _val(f.key);
      final items = List<String>.from(f.choices!);
      if (!items.contains(cur)) items.add(cur);
      return PopupMenuButton<String>(
        onSelected: (v) => setState(() => _form!.data[f.key] = v),
        itemBuilder: (_) => [
          for (final c in items)
            PopupMenuItem<String>(
              value: c,
              child: Text(c.isEmpty ? '—' : c),
            ),
        ],
        child: InputDecorator(
          decoration: _deco(p, f.label),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  cur.isEmpty ? '—' : cur,
                  style: TextStyle(color: p.text, fontSize: 15),
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, color: p.sub),
            ],
          ),
        ),
      );
    }
    return TextField(
      controller: _ctrl(f.key),
      keyboardType: f.number ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: p.text, fontSize: 15),
      onChanged: (v) => _form!.data[f.key] = v,
      decoration: _deco(p, f.label, hint: f.hint),
    );
  }

  Widget _secLabel(_P p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: .7,
            color: p.sub,
          ),
        ),
      );

  List<Widget> _formBody(_P p) {
    final out = <Widget>[];
    for (final sec in _sections()) {
      out.add(_secLabel(p, sec.title));
      final kids = <Widget>[];
      for (var i = 0; i < sec.fields.length; i++) {
        if (i > 0) kids.add(const SizedBox(height: 12));
        kids.add(_field(p, sec.fields[i]));
      }
      out.add(Glass(
        radius: 24,
        padding: const EdgeInsets.all(14),
        child: Column(children: kids),
      ));
    }
    return out;
  }

  List<Widget> _rawBody(_P p) {
    return [
      _secLabel(p, 'RAW KEY'),
      Glass(
        radius: 24,
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              style: TextStyle(color: p.text, fontSize: 15),
              decoration: _deco(p, 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rawCtrl,
              minLines: 6,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              style: TextStyle(color: p.text, fontSize: 14),
              decoration: _deco(p, 'Key / JSON config'),
            ),
          ],
        ),
      ),
    ];
  }

  void _toggleRaw() {
    if (_raw) {
      final text = _rawCtrl.text.trim();
      final f = KeyForm.parse(text.split(RegExp(r'\s+')).first);
      if (f == null) {
        _toast('ဒီ key အမျိုးအစားကို field နဲ့ မပြင်နိုင်ပါ');
        return;
      }
      setState(() {
        _form = f;
        _clearCtrls();
        _raw = false;
      });
    } else {
      setState(() {
        _rawCtrl.text = _form!.build();
        _nameCtrl.text = (_form!.data['remarks'] ?? '').trim().isEmpty
            ? widget.server.name
            : _form!.data['remarks']!.trim();
        _raw = true;
      });
    }
  }

  void _save() {
    String name;
    String link;
    if (_raw) {
      final t = _rawCtrl.text.trim();
      link = t.startsWith('{')
          ? t
          : normalizeKey(t.split(RegExp(r'\s+')).first);
      name = _nameCtrl.text.trim();
    } else {
      link = _form!.build();
      name = (_form!.data['remarks'] ?? '').trim();
    }
    Navigator.pop(context, {'name': name, 'link': link});
  }

  @override
  Widget build(BuildContext context) {
    final p = _P.of(context);
    final pad = MediaQuery.of(context).padding;
    final overlay = (p.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: p.base,
        body: Stack(
          children: [
            Positioned.fill(child: _Backdrop(p: p)),
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(height: pad.top + 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Back',
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Glass(
                              radius: 22,
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: Icon(Icons.arrow_back_rounded,
                                      color: p.blue, size: 24),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Edit server',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.4,
                              color: p.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: _raw ? _rawBody(p) : _formBody(p),
                    ),
                  ),
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(16, 8, 16, 16 + pad.bottom),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: _toggleRaw,
                          child: Text(_raw ? 'Fields' : 'Raw key'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('သိမ်းမည်'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QR scan page
// ---------------------------------------------------------------------------

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        _done = true;
        Navigator.pop(context, v.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: MobileScanner(
                onDetect: _onDetect,
                errorBuilder: (context, error, child) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Camera ဖွင့်မရပါ။ Camera permission ခွင့်ပြုပေးပါ။',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
            Positioned(
              top: pad.top + 12,
              left: 16,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 48,
              child: const Text(
                'QR code ကို ဘောင်ထဲ ထားပါ',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-app proxy page
// ---------------------------------------------------------------------------

class AppEntry {
  AppEntry(this.name, this.pkg, this.icon);
  final String name;
  final String pkg;
  final Uint8List? icon;
}

class AppsPage extends StatefulWidget {
  const AppsPage({
    super.key,
    required this.loader,
    required this.mode,
    required this.selected,
  });

  final Future<List<AppEntry>> Function() loader;
  final String mode;
  final Set<String> selected;

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  late String _mode;
  late Set<String> _sel;
  List<AppEntry>? _apps;
  String? _err;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _sel = Set<String>.from(widget.selected);
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await widget.loader();
      if (mounted) setState(() => _apps = a);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Widget _modeRow(_P p, String id, String title, String sub) {
    final on = _mode == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _mode = id),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _checkDot(p, on),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: p.text)),
                  Text(sub, style: TextStyle(fontSize: 12, color: p.sub)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appRow(_P p, AppEntry a) {
    final on = _sel.contains(a.pkg);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (on) {
          _sel.remove(a.pkg);
        } else {
          _sel.add(a.pkg);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: a.icon != null
                  ? Image.memory(a.icon!,
                      width: 40, height: 40, gaplessPlayback: true)
                  : SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.android_rounded, color: p.sub)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: p.text)),
                  Text(a.pkg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: p.sub)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _checkDot(p, on),
          ],
        ),
      ),
    );
  }

  Widget _list(_P p) {
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('App စာရင်း ယူမရပါ: $_err',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.sub)),
        ),
      );
    }
    if (_apps == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final q = _query.toLowerCase();
    final list = _apps!
        .where((a) =>
            q.isEmpty ||
            a.name.toLowerCase().contains(q) ||
            a.pkg.toLowerCase().contains(q))
        .toList();
    if (list.isEmpty) {
      return Center(
        child: Text('မတွေ့ပါ', style: TextStyle(color: p.sub)),
      );
    }
    return Opacity(
      opacity: _mode == 'off' ? .45 : 1,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: list.length,
        itemBuilder: (_, i) => _appRow(p, list[i]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _P.of(context);
    final pad = MediaQuery.of(context).padding;
    final overlay = (p.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: p.base,
        body: Stack(
          children: [
            Positioned.fill(child: _Backdrop(p: p)),
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(height: pad.top + 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Back',
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Glass(
                              radius: 22,
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: Icon(Icons.arrow_back_rounded,
                                      color: p.blue, size: 24),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Per-app proxy',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.4,
                              color: p.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Glass(
                      radius: 24,
                      child: Column(
                        children: [
                          _modeRow(p, 'off', 'Off',
                              'App အားလုံး VPN ဖြတ်မယ်'),
                          Container(height: 1, color: p.line),
                          _modeRow(p, 'bypass', 'Bypass selected',
                              'ရွေးထားတဲ့ App တွေ ရိုးရိုးလိုင်းနဲ့ သုံးမယ် (ဥပမာ KBZPay)'),
                          Container(height: 1, color: p.line),
                          _modeRow(p, 'only', 'Only selected',
                              'ရွေးထားတဲ့ App တွေပဲ VPN ဖြတ်မယ်'),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(color: p.text, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Search apps',
                        prefixIcon: Icon(Icons.search_rounded, color: p.sub),
                        filled: true,
                        fillColor: p.inner,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: p.panel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: p.border, width: 1.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: _list(p),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(16, 10, 16, 16 + pad.bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_sel.length} app ရွေးထားသည်',
                            style: TextStyle(fontSize: 14, color: p.sub),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(
                            context,
                            <String, dynamic>{
                              'mode': _mode,
                              'apps': _sel.toList(),
                            },
                          ),
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('သိမ်းမည်'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.themeMode, required this.onTheme});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final V2ray _v2ray;
  bool _ready = false;
  bool _busy = false; // connecting / disconnecting
  bool _importing = false;
  bool _testing = false;
  int _tab = 0;
  V2RayStatus _status = V2RayStatus();
  DateTime? _ignoreConnectedUntil;

  final List<Server> _servers = [];
  final List<Sub> _subs = [];
  String _filter = 'all'; // all | sub
  String? _refreshingId;
  String? _selectedId;
  Timer? _busyGuard;

  // per-app proxy
  String _splitMode = 'off'; // off | bypass | only
  Set<String> _splitApps = <String>{};
  Future<List<AppEntry>>? _appsFuture;

  bool get _connected => _status.state == 'CONNECTED';

  Server? get _selected {
    for (final s in _servers) {
      if (s.id == _selectedId) return s;
    }
    return _servers.isNotEmpty ? _servers.first : null;
  }

  String get _splitSummary => _splitMode == 'off' || _splitApps.isEmpty
      ? 'Off'
      : _splitMode == 'bypass'
          ? 'Bypass ${_splitApps.length} apps'
          : 'Only ${_splitApps.length} apps';

  @override
  void initState() {
    super.initState();
    _v2ray = V2ray(onStatusChanged: _onStatus);
    _ctlChannel.setMethodCallHandler((call) async {
      if (call.method == 'toggle') _remoteToggle();
      return null;
    });
    _boot();
  }

  @override
  void dispose() {
    _busyGuard?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await _loadServers();
    await _loadSplit();
    try {
      await _v2ray.initialize(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      _toast('Core စတင်မရပါ: $e');
    }
    // keep the blocked-apps cache fresh (new installs) without slowing connect
    _blockedApps();
    // App was opened by the home-screen widget / Quick Settings tile
    try {
      final pending = await _ctlChannel.invokeMethod<bool>('pending');
      if (pending == true) _remoteToggle();
    } catch (_) {}
    _syncNative();
  }

  /// Tell the native side (widget + Quick Settings tile) the current state.
  void _syncNative() {
    try {
      _ctlChannel.invokeMethod('state', {
        'connected': _connected,
        'name': _selected == null
            ? ''
            : '${_selected!.flag} ${_selected!.displayName}',
      });
    } catch (_) {}
  }

  /// Triggered by the widget / tile: flip the VPN, then go back to where the
  /// user was (the app only flashes open).
  Future<void> _remoteToggle() async {
    for (var i = 0; i < 40 && !_ready && mounted; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    final was = _connected;
    await _toggle();
    for (var i = 0; i < 40 && mounted && !was && !_connected; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    _syncNative();
    final changed = _connected != was;
    if (changed) {
      try {
        await _ctlChannel.invokeMethod('minimize');
      } catch (_) {}
    }
  }

  void _onStatus(V2RayStatus s) {
    if (!mounted) return;
    final until = _ignoreConnectedUntil;
    if (s.state == 'CONNECTED' &&
        until != null &&
        DateTime.now().isBefore(until)) {
      return; // stale status right after the user pressed disconnect
    }
    setState(() {
      _status = s;
      if (s.state == 'CONNECTED' || s.state == 'DISCONNECTED') {
        _busy = false;
        _busyGuard?.cancel();
      }
    });
    _syncNative();
  }

  // ----- storage -----

  Future<void> _loadServers() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('servers');
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => Server.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _servers
          ..clear()
          ..addAll(list);
      }
      final rawSubs = p.getString('subs');
      if (rawSubs != null) {
        _subs
          ..clear()
          ..addAll((jsonDecode(rawSubs) as List)
              .map((e) => Sub.fromJson(Map<String, dynamic>.from(e as Map))));
      }
      _selectedId = p.getString('selected');
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveServers() async {
    _syncNative();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'servers', jsonEncode(_servers.map((e) => e.toJson()).toList()));
      await p.setString(
          'subs', jsonEncode(_subs.map((e) => e.toJson()).toList()));
      if (_selectedId != null) await p.setString('selected', _selectedId!);
    } catch (_) {}
  }

  Future<void> _loadSplit() async {
    try {
      final p = await SharedPreferences.getInstance();
      _splitMode = p.getString('split_mode') ?? 'off';
      _splitApps = (p.getStringList('split_apps') ?? <String>[]).toSet();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveSplit() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('split_mode', _splitMode);
      await p.setStringList('split_apps', _splitApps.toList());
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----- per-app proxy -----

  Future<List<AppEntry>> _loadApps() {
    return _appsFuture ??= _fetchApps();
  }

  Future<List<AppEntry>> _fetchApps() async {
    try {
      final raw = await _appsChannel.invokeMethod<List<dynamic>>('list');
      final out = <AppEntry>[];
      for (final e in raw ?? const []) {
        final m = Map<String, dynamic>.from(e as Map);
        final ic = m['icon'];
        out.add(AppEntry(
          m['name'] as String,
          m['package'] as String,
          ic is Uint8List && ic.isNotEmpty ? ic : null,
        ));
      }
      return out;
    } catch (e) {
      _appsFuture = null;
      rethrow;
    }
  }

  Future<List<String>?> _computeBlocked() async {
    if (_splitMode == 'off' || _splitApps.isEmpty) return null;
    final all = (await _loadApps()).map((a) => a.pkg).toSet();
    if (_splitMode == 'bypass') {
      final l = _splitApps.where(all.contains).toList();
      return l.isEmpty ? null : l;
    }
    final l = all.where((x) => !_splitApps.contains(x)).toList();
    return l.isEmpty ? null : l;
  }

  /// Computes the blocked-apps list and caches it (the widget / tile toggle
  /// and the fast connect path read this cache).
  Future<List<String>?> _blockedApps() async {
    final l = await _computeBlocked();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('blocked_cache', l ?? <String>[]);
    } catch (_) {}
    return l;
  }

  /// Fast path: no need to load every app icon on each connect.
  Future<List<String>?> _cachedBlocked() async {
    if (_splitMode == 'off' || _splitApps.isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final c = p.getStringList('blocked_cache');
      if (c != null && c.isNotEmpty) return c;
    } catch (_) {}
    return _blockedApps();
  }

  Future<void> _openSplit() async {
    final res = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => AppsPage(
          loader: _loadApps,
          mode: _splitMode,
          selected: _splitApps,
        ),
      ),
    );
    if (res == null) return;
    setState(() {
      _splitMode = res['mode'] as String;
      _splitApps = Set<String>.from(res['apps'] as List);
    });
    await _saveSplit();
    _blockedApps(); // refresh cache in the background
    _toast(_connected ? 'နောက်တစ်ခါ ချိတ်ရင် သက်ရောက်မယ်' : 'သိမ်းပြီး');
  }

  // ----- QR -----

  Future<void> _scanQr() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (res != null && res.isNotEmpty) await _import(res);
  }

  Future<void> _showQr(Server s) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: s.link,
                  size: 232,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  errorStateBuilder: (c, e) => const SizedBox(
                    width: 232,
                    height: 232,
                    child: Center(
                      child: Text(
                        'Key အရှည်လွန်းလို့ QR မထုတ်နိုင်ပါ',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('တခြားဖုန်းက Scan QR နဲ့ ဖတ်ပါ',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: s.link));
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('Copy ပြီး');
            },
            child: const Text('Key copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ပိတ်မည်'),
          ),
        ],
      ),
    );
  }

  // ----- import keys -----

  Future<void> _import(String text) async {
    final tokens = extractKeys(text);
    if (tokens.isEmpty) {
      _toast('Key မတွေ့ပါ (vless:// vmess:// trojan:// ss:// ssconf:// စသည်ဖြင့် ထည့်ပါ)');
      return;
    }
    setState(() => _importing = true);
    int added = 0, bad = 0, dup = 0;
    final keys = <String>[];
    final keySub = <String, String>{};
    for (final t in tokens) {
      final l = t.toLowerCase();
      if (l.startsWith(_ssconf)) {
        try {
          keys.addAll(await fetchOutlineDynamic(t));
        } catch (e) {
          bad++;
          _toast('Outline key ဖတ်မရပါ: $e');
        }
      } else if (l.startsWith('http://') || l.startsWith('https://')) {
        try {
          final f = await fetchSubscriptionFull(t);
          final sid = _upsertSub(t, f);
          for (final k in extractKeys(f.body)
              .where((k) => !k.toLowerCase().startsWith('http'))
              .map(normalizeKey)) {
            keys.add(k);
            keySub[k] = sid;
          }
        } catch (e) {
          bad++;
          _toast('Subscription ဖတ်မရပါ: $e');
        }
      } else {
        keys.add(normalizeKey(t));
      }
    }
    for (final k in keys) {
      final same = _servers.where((s) => s.link == k);
      if (same.isNotEmpty) {
        if (same.first.subId == null && keySub[k] != null) {
          same.first.subId = keySub[k];
        }
        dup++;
        continue;
      }
      try {
        final r = resolveKey(k);
        _servers.add(Server(
          id: '${DateTime.now().microsecondsSinceEpoch}_${_servers.length}',
          name: r.remark,
          link: k,
          subId: keySub[k],
        ));
        added++;
      } catch (_) {
        bad++;
      }
    }
    if (added > 0 && _selectedId == null) _selectedId = _servers.first.id;
    await _saveServers();
    if (!mounted) return;
    setState(() => _importing = false);
    _toast('ထည့်ပြီး $added'
        '${dup > 0 ? ' · ထပ်နေ $dup' : ''}'
        '${bad > 0 ? ' · မမှန် $bad' : ''}');
  }

  String _upsertSub(String url, SubFetch f) {
    Sub? sub;
    for (final x in _subs) {
      if (x.url == url) sub = x;
    }
    if (sub == null) {
      sub = Sub(id: 'sub_${DateTime.now().microsecondsSinceEpoch}', url: url);
      _subs.add(sub);
    }
    sub.used = f.used;
    sub.total = f.total;
    sub.expire = f.expire;
    if (f.title != null) sub.name = f.title;
    return sub.id;
  }

  Future<void> _refreshSub(Sub sub) async {
    if (_refreshingId != null) return;
    setState(() => _refreshingId = sub.id);
    try {
      final f = await fetchSubscriptionFull(sub.url);
      final keys = extractKeys(f.body)
          .where((k) => !k.toLowerCase().startsWith('http'))
          .map(normalizeKey)
          .toList();
      if (keys.isEmpty) throw Exception('server မတွေ့ပါ');
      sub.used = f.used;
      sub.total = f.total;
      sub.expire = f.expire;
      if (f.title != null) sub.name = f.title;
      var added = 0;
      for (final k in keys) {
        final ex = _servers.where((x) => x.link == k);
        if (ex.isNotEmpty) {
          ex.first.subId ??= sub.id;
          continue;
        }
        try {
          final r = resolveKey(k);
          _servers.add(Server(
            id: '${DateTime.now().microsecondsSinceEpoch}_${_servers.length}',
            name: r.remark,
            link: k,
            subId: sub.id,
          ));
          added++;
        } catch (_) {}
      }
      final keep = keys.toSet();
      final before = _servers.length;
      _servers.removeWhere((x) => x.subId == sub.id && !keep.contains(x.link));
      final removed = before - _servers.length;
      if (_selectedId != null && !_servers.any((x) => x.id == _selectedId)) {
        _selectedId = null;
      }
      await _saveServers();
      _toast('Update ပြီး · အသစ် $added · ဖယ်ရှား $removed');
    } catch (e) {
      _toast('Subscription ဖတ်မရပါ: $e');
    }
    if (mounted) setState(() => _refreshingId = null);
  }

  Future<void> _pingSub(Sub sub) async {
    final list = _servers.where((x) => x.subId == sub.id).toList();
    if (list.isEmpty || _testing) return;
    setState(() {
      _testing = true;
      for (final s in list) {
        s.ping = null;
      }
    });
    for (var i = 0; i < list.length; i += 4) {
      await Future.wait(list.skip(i).take(4).map((s) async {
        final d = await _measure(s);
        if (mounted) setState(() => s.ping = d);
      }));
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _deleteSub(Sub sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subscription ကို ဖျက်မလား?'),
        content: const Text('ဒီ subscription က ရလာတဲ့ server တွေပါ ပါသွားမယ်။'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('မဖျက်ပါ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ဖျက်မည်')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _servers.removeWhere((x) => x.subId == sub.id);
      _subs.removeWhere((x) => x.id == sub.id);
      if (_selectedId != null && !_servers.any((x) => x.id == _selectedId)) {
        _selectedId = null;
      }
      if (_subs.isEmpty) _filter = 'all';
    });
    await _saveServers();
  }

  Future<void> _serverMenu(Server s) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in const [
              ['ping', 'Ping စစ်', Icons.speed_rounded],
              ['edit', 'Edit', Icons.edit_outlined],
              ['qr', 'QR code', Icons.qr_code_2_rounded],
              ['copy', 'Key copy', Icons.copy_rounded],
              ['del', 'ဖျက်မည်', Icons.delete_outline_rounded],
            ])
              ListTile(
                leading: Icon(e[2] as IconData),
                title: Text(e[1] as String),
                onTap: () => Navigator.pop(ctx, e[0] as String),
              ),
          ],
        ),
      ),
    );
    if (v == null) return;
    if (v == 'ping') _pingOne(s);
    if (v == 'edit') _editServer(s);
    if (v == 'qr') _showQr(s);
    if (v == 'copy') {
      await Clipboard.setData(ClipboardData(text: s.link));
      _toast('Copy ပြီး');
    }
    if (v == 'del') {
      setState(() {
        _servers.remove(s);
        if (_selectedId == s.id) _selectedId = null;
      });
      _saveServers();
    }
  }

  Future<void> _showAddSheet() async {
    final ctrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add key', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'VLESS · VMess · Trojan · Shadowsocks · Outline (ss:// / ssconf://) '
              '· SOCKS · Hysteria2 key, subscription link သို့မဟုတ် JSON config။ '
              'တစ်ကြောင်းကို key တစ်ခုစီ ထည့်နိုင်သည်။',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'vless://...',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null) ctrl.text = d!.text!;
                  },
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Paste'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _scanQr();
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan QR'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final text = ctrl.text;
                      Navigator.pop(ctx);
                      _import(text);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('ထည့်'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----- edit server -----

  Future<void> _editServer(Server s) async {
    if (_connected && s.id == _selected?.id) {
      _toast('ပြင်ရန် အရင်ဖြတ်ပါ');
      return;
    }
    final res = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => EditServerPage(server: s)),
    );
    if (res == null) return;
    await _saveEdit(s, res['name'] ?? '', res['link'] ?? '');
  }

  Future<void> _saveEdit(Server s, String name, String key) async {
    if (key.isEmpty) {
      _toast('Key ဗလာဖြစ်နေပါတယ်');
      return;
    }
    try {
      resolveKey(key);
    } catch (_) {
      _toast('Key မမှန်ပါ၊ တန်ဖိုးတွေ စစ်ပါ');
      return;
    }
    if (_servers.any((o) => o.id != s.id && o.link == key)) {
      _toast('ဒီ key ထပ်နေပါတယ်');
      return;
    }
    setState(() {
      s.link = key;
      if (name.isNotEmpty) s.name = name;
      s.ping = null;
    });
    await _saveServers();
    _toast('သိမ်းပြီး');
  }

  // ----- connect -----

  Future<void> _toggle() async {
    if (_busy) return;
    if (_connected) {
      setState(() => _busy = true);
      try {
        await _v2ray.stopV2Ray();
      } catch (e) {
        _toast('ဖြတ်မရပါ: $e');
      }
      _ignoreConnectedUntil = DateTime.now().add(const Duration(seconds: 3));
      _busyGuard?.cancel();
      if (mounted) {
        setState(() {
          _status = V2RayStatus();
          _busy = false;
        });
        _syncNative();
      }
      return;
    }
    final s = _selected;
    if (s == null) {
      _toast('Key အရင်ထည့်ပါ');
      return;
    }
    if (!_ready) {
      _toast('Core စတင်နေဆဲ၊ ခဏစောင့်ပါ');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = resolveKey(s.link);
      final permF = _v2ray.requestPermission();
      final blockedF = _cachedBlocked();
      final ok = await permF;
      if (!ok) {
        _toast('VPN permission ခွင့်ပြုပေးပါ');
        setState(() => _busy = false);
        return;
      }
      final blocked = await blockedF;
      _ignoreConnectedUntil = null;
      await _v2ray.startV2Ray(
        remark: r.remark,
        config: r.config,
        blockedApps: blocked,
        bypassSubnets: null,
        proxyOnly: false,
      );
      _armBusyGuard();
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast('ချိတ်ဆက်မရပါ: $e');
    }
  }

  /// Safety net so the switch can never stay stuck in "connecting".
  void _armBusyGuard() {
    _busyGuard?.cancel();
    _busyGuard = Timer(const Duration(seconds: 15), () {
      if (mounted && _busy) setState(() => _busy = false);
    });
  }

  // ----- ping -----

  Future<int> _measure(Server s) async {
    try {
      final r = resolveKey(s.link);
      final d = await _v2ray
          .getServerDelay(config: r.config)
          .timeout(const Duration(seconds: 10));
      return d > 0 ? d : -1;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _pingOne(Server s) async {
    setState(() => s.ping = null);
    final d = await _measure(s);
    if (mounted) setState(() => s.ping = d);
  }

  Future<void> _pingAll({bool pickBest = false}) async {
    if (_servers.isEmpty || _testing) return;
    setState(() {
      _testing = true;
      for (final s in _servers) {
        s.ping = null;
      }
    });
    final list = List<Server>.from(_servers);
    for (var i = 0; i < list.length; i += 4) {
      final chunk = list.skip(i).take(4).toList();
      await Future.wait(chunk.map((s) async {
        final d = await _measure(s);
        if (mounted) setState(() => s.ping = d);
      }));
    }
    if (!mounted) return;
    setState(() => _testing = false);
    if (pickBest) {
      final ok = list.where((s) => (s.ping ?? -1) > 0).toList()
        ..sort((a, b) => a.ping!.compareTo(b.ping!));
      if (ok.isEmpty) {
        _toast('အလုပ်လုပ်တဲ့ server မတွေ့ပါ');
      } else {
        setState(() => _selectedId = ok.first.id);
        await _saveServers();
        _toast('အမြန်ဆုံး: ${ok.first.name} (${ok.first.ping}ms)');
      }
    }
  }

  Future<void> _confirmClear() async {
    if (_servers.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Key အားလုံးဖျက်မလား?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('မဖျက်ပါ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ဖျက်မည်')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _servers.clear();
        _subs.clear();
        _filter = 'all';
        _selectedId = null;
      });
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove('servers');
        await p.remove('selected');
      } catch (_) {}
    }
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    final p = _P.of(context);
    final pad = MediaQuery.of(context).padding;
    final overlay = (p.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: p.base,
        body: Stack(
          children: [
            Positioned.fill(child: _Backdrop(p: p)),
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(height: pad.top + 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _header(p),
                  ),
                  Expanded(
                    child: ListView(
                      padding:
                          EdgeInsets.fromLTRB(16, 8, 16, 120 + pad.bottom),
                      children: _tabBody(p),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + pad.bottom,
              child: _tabBar(p),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassBtn(
    _P p,
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool busy = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Glass(
          radius: 22,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, color: p.blue, size: 24),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(_P p) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.asset('assets/icon.png', width: 54, height: 54),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Tulip VPN',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
              color: p.text,
            ),
          ),
        ),
        _glassBtn(p, Icons.qr_code_scanner_rounded, 'Scan QR', _scanQr),
        const SizedBox(width: 8),
        _glassBtn(p, Icons.add_rounded, 'Add key',
            _importing ? null : _showAddSheet,
            busy: _importing),
      ],
    );
  }

  List<Widget> _tabBody(_P p) {
    switch (_tab) {
      case 1:
        return _configTab(p);
      case 2:
        return _dataTab(p);
      case 3:
        return _settingsTab(p);
      default:
        return _homeTab(p);
    }
  }

  // ----- small helpers -----

  Widget _label(_P p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: .7,
            color: p.sub,
          ),
        ),
      );

  Widget _div(_P p) => Container(height: 1, color: p.line);

  Widget _actionRow(
    _P p,
    IconData icon,
    String title, {
    String? sub,
    Color? color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color ?? p.blue, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: color ?? p.text)),
                  if (sub != null)
                    Text(sub,
                        style: TextStyle(fontSize: 12, color: p.sub)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.sub, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _kv(_P p, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(k, style: TextStyle(fontSize: 14, color: p.sub)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                v,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.text),
              ),
            ),
          ],
        ),
      );

  // ----- Home tab -----

  List<Widget> _homeTab(_P p) {
    final shown = _filter == 'sub'
        ? _servers.where((x) => x.subId != null).toList()
        : _servers;
    return [
      const SizedBox(height: 6),
      _connectCard(p),
      if (_subs.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          _chip(p, 'All', 'all'),
          const SizedBox(width: 10),
          _chip(p, 'Subscription', 'sub'),
        ]),
        for (final sub in _subs) ...[
          const SizedBox(height: 12),
          _subCard(p, sub),
        ],
      ],
      _label(p, 'SERVERS'),
      _serverList(p, shown),
      if (_servers.isNotEmpty) ...[
        const SizedBox(height: 6),
        Glass(
          radius: 24,
          child: _actionRow(
            p,
            Icons.bolt_rounded,
            'Ping all · pick fastest',
            onTap: () => _pingAll(pickBest: true),
          ),
        ),
      ],
    ];
  }

  Widget _chip(_P p, String label, String value) {
    final on = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: on ? Colors.transparent : p.panel,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
              color: on ? p.blue : Colors.transparent, width: on ? 1.6 : 0),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: on ? p.blue : p.sub)),
      ),
    );
  }

  Widget _subCard(_P p, Sub sub) {
    final count = _servers.where((x) => x.subId == sub.id).length;
    final total = sub.total ?? 0;
    final used = sub.used ?? 0;
    final frac = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final days = sub.daysLeft;
    final refreshing = _refreshingId == sub.id;
    return Glass(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(18, 16, 6, 16),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _refreshSub(sub),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: refreshing
                      ? const Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Icon(Icons.sync_rounded, color: p.blue, size: 32),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '${sub.name ?? 'Subscription'} ($count)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: p.text),
                ),
              ),
              IconButton(
                onPressed: () => _pingSub(sub),
                icon: Icon(Icons.speed_rounded, color: p.blue, size: 26),
                tooltip: 'Ping',
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: p.text, size: 22),
                onSelected: (v) async {
                  if (v == 'refresh') _refreshSub(sub);
                  if (v == 'ping') _pingSub(sub);
                  if (v == 'copy') {
                    await Clipboard.setData(ClipboardData(text: sub.url));
                    _toast('Link copy ပြီး');
                  }
                  if (v == 'del') _deleteSub(sub);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'refresh', child: Text('Update')),
                  PopupMenuItem(value: 'ping', child: Text('Ping စစ်')),
                  PopupMenuItem(value: 'copy', child: Text('Link copy')),
                  PopupMenuItem(value: 'del', child: Text('ဖျက်မည်')),
                ],
              ),
            ],
          ),
          if (total > 0 || days != null)
            Padding(
              padding: const EdgeInsets.only(left: 48, right: 12, top: 4),
              child: Column(
                children: [
                  if (total > 0)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: frac < .02 ? .02 : frac,
                        minHeight: 10,
                        backgroundColor: p.blue.withOpacity(.18),
                        color: p.blue,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          total > 0
                              ? '${formatBytes(used)} / ${formatBytes(total)}'
                              : '',
                          style: TextStyle(fontSize: 15, color: p.sub)),
                      Text(days == null ? '' : '$days Days Left',
                          style: TextStyle(fontSize: 15, color: p.sub)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _connectCard(_P p) {
    final connected = _connected;
    final title = _busy
        ? (connected ? 'Disconnecting…' : 'Connecting…')
        : connected
            ? 'Connected'
            : 'Not connected';
    final sel = _selected;
    final subtitle = sel == null
        ? 'No server yet'
        : connected
            ? '${sel.flag} ${sel.displayName} · ${_status.duration}'
            : '${sel.flag} ${sel.displayName}';
    return Glass(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONNECTION',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .7,
                            color: p.sub)),
                    const SizedBox(height: 2),
                    Text(title,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: p.text)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.sub)),
                    if (sel?.ping != null) ...[
                      const SizedBox(height: 6),
                      _pingPill(p, sel!.ping!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _switchW(p, connected),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _stat(p, 'Download',
                        '${formatBytes(_status.downloadSpeed)}/s')),
                const SizedBox(width: 10),
                Expanded(
                    child: _stat(p, 'Upload',
                        '${formatBytes(_status.uploadSpeed)}/s')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _switchW(_P p, bool on) {
    return Semantics(
      button: true,
      label: on ? 'Disconnect VPN' : 'Connect VPN',
      child: GestureDetector(
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 68,
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: on ? _accentGrad : null,
            color: on ? null : p.off,
            borderRadius: BorderRadius.circular(20),
            boxShadow: on
                ? const [
                    BoxShadow(
                        color: Color(0x663B82F6),
                        blurRadius: 16,
                        offset: Offset(0, 6))
                  ]
                : null,
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x4D1E2864),
                      blurRadius: 6,
                      offset: Offset(0, 2))
                ],
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(_P p, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.inner,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: p.sub)),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.text)),
          ],
        ),
      );

  Widget _serverList(_P p, [List<Server>? list]) {
    final items = list ?? _servers;
    if (_servers.isEmpty) {
      return Glass(
        radius: 24,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.vpn_key_outlined, size: 44, color: p.sub),
            const SizedBox(height: 10),
            Text('Add a key to get started',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.text)),
            const SizedBox(height: 4),
            Text(
              'Tap + or scan a QR code. Paste a vless:// vmess:// trojan:// ss:// hy2:// key, '
              'an Outline key (ss:// or ssconf://) or a subscription link.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.sub),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Server မရှိသေးပါ',
            style: TextStyle(fontSize: 14, color: p.sub)),
      );
    }
    return Column(children: [for (final s in items) _serverRow(p, s)]);
  }

  Color _typeColor(String t) {
    switch (t) {
      case 'VLESS':
        return const Color(0xFF0891C8);
      case 'VMESS':
        return const Color(0xFF7C3AED);
      case 'TROJAN':
        return const Color(0xFFEA580C);
      case 'SS':
        return const Color(0xFF059669);
      default:
        return const Color(0xFF64748B);
    }
  }

  Widget _serverRow(_P p, Server s) {
    final selected = s.id == _selected?.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _connected || _busy
          ? () => _toast('ပြောင်းရန် အရင်ဖြတ်ပါ')
          : () {
              setState(() => _selectedId = s.id);
              _saveServers();
            },
      onLongPress: () => _serverMenu(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 88,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected ? p.blue.withOpacity(.16) : p.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: selected ? p.blue.withOpacity(.35) : p.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              color: _typeColor(s.type),
              alignment: Alignment.center,
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  s.type,
                  maxLines: 1,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                          color: p.text),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            maskHost(s.host),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, color: p.sub),
                          ),
                        ),
                        _pingText(p, s),
                        GestureDetector(
                          onTap: () => _serverMenu(s),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child:
                                Icon(Icons.more_horiz, color: p.sub, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pingText(_P p, Server s) {
    if (s.ping == null) {
      return _testing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const SizedBox.shrink();
    }
    return _pingPill(p, s.ping!);
  }

  /// Coloured delay badge: green < 300 ms, yellow < 700 ms, red slower/timeout.
  Widget _pingPill(_P p, int v) {
    final c = p.pingColor(v);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(v < 0 ? 'timeout' : '$v ms',
              style: TextStyle(
                  color: c, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ----- Config tab -----

  List<Widget> _configTab(_P p) {
    return [
      _label(p, 'KEYS'),
      Glass(
        radius: 24,
        child: Column(
          children: [
            _actionRow(
              p,
              Icons.add_link_rounded,
              'Add key or subscription',
              sub: 'VLESS · VMess · Trojan · SS · Outline · HY2 · JSON',
              onTap: _showAddSheet,
            ),
            _div(p),
            _actionRow(
              p,
              Icons.qr_code_scanner_rounded,
              'Scan QR code',
              sub: 'ကင်မရာနဲ့ ဖတ်ပြီး key တန်းထည့်မယ်',
              onTap: _scanQr,
            ),
            _div(p),
            _actionRow(
              p,
              Icons.delete_outline_rounded,
              'Delete all servers',
              color: p.bad,
              onTap: _confirmClear,
            ),
          ],
        ),
      ),
      _label(p, 'TESTING'),
      Glass(
        radius: 24,
        child: Column(
          children: [
            _actionRow(
              p,
              Icons.speed_rounded,
              'Ping all servers',
              onTap: () {
                setState(() => _tab = 0);
                _pingAll();
              },
            ),
            _div(p),
            _actionRow(
              p,
              Icons.bolt_rounded,
              'Pick fastest server',
              onTap: () {
                setState(() => _tab = 0);
                _pingAll(pickBest: true);
              },
            ),
          ],
        ),
      ),
    ];
  }

  // ----- Data tab -----

  List<Widget> _dataTab(_P p) {
    final c = _connected;
    String v(String s) => c ? s : '—';
    return [
      _label(p, 'THIS SESSION'),
      Glass(
        radius: 24,
        child: Column(
          children: [
            _kv(p, 'Status',
                _busy ? 'Working…' : c ? 'Connected' : 'Disconnected'),
            _div(p),
            _kv(p, 'Server',
                _selected == null ? '—' : '${_selected!.flag} ${_selected!.displayName}'),
            _div(p),
            _kv(p, 'Duration', v(_status.duration)),
            _div(p),
            _kv(p, 'Downloaded', v(formatBytes(_status.download))),
            _div(p),
            _kv(p, 'Uploaded', v(formatBytes(_status.upload))),
            _div(p),
            _kv(p, 'Download speed',
                v('${formatBytes(_status.downloadSpeed)}/s')),
            _div(p),
            _kv(p, 'Upload speed',
                v('${formatBytes(_status.uploadSpeed)}/s')),
          ],
        ),
      ),
    ];
  }

  // ----- Settings tab -----

  Widget _themeRow(_P p, String t, ThemeMode m) {
    final on = widget.themeMode == m;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTheme(m),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(t,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: p.text)),
            ),
            if (on) Icon(Icons.check_rounded, color: p.blue),
          ],
        ),
      ),
    );
  }

  List<Widget> _settingsTab(_P p) {
    return [
      _label(p, 'NETWORK'),
      Glass(
        radius: 24,
        child: _actionRow(
          p,
          Icons.apps_rounded,
          'Per-app proxy',
          sub: _splitSummary,
          onTap: _openSplit,
        ),
      ),
      _label(p, 'APPEARANCE'),
      Glass(
        radius: 24,
        child: Column(
          children: [
            _themeRow(p, 'System', ThemeMode.system),
            _div(p),
            _themeRow(p, 'Light', ThemeMode.light),
            _div(p),
            _themeRow(p, 'Dark', ThemeMode.dark),
          ],
        ),
      ),
      _label(p, 'ABOUT'),
      Glass(
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Text(
          'Tulip VPN 1.0\nV2Ray / Xray client for Android.',
          style: TextStyle(fontSize: 14, color: p.sub, height: 1.4),
        ),
      ),
    ];
  }

  // ----- bottom tab bar -----

  Widget _tabBar(_P p) {
    const icons = [
      Icons.home_rounded,
      Icons.tune_rounded,
      Icons.bar_chart_rounded,
      Icons.settings_rounded,
    ];
    const labels = ['Home', 'Config', 'Data', 'Settings'];
    return Glass(
      radius: 34,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (var i = 0; i < icons.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 52,
                  decoration: BoxDecoration(
                    color: _tab == i
                        ? p.blue.withOpacity(.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icons[i],
                          size: 22, color: _tab == i ? p.blue : p.sub),
                      const SizedBox(height: 3),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              _tab == i ? FontWeight.w600 : FontWeight.w500,
                          color: _tab == i ? p.blue : p.sub,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background toggle (home-screen widget / Quick Settings tile).
// Runs in a headless Flutter engine started by the native side, so the app
// UI never opens. Needs the VPN permission to be granted already.
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
Future<void> oakBackgroundToggle() async {
  WidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('oak/ctl');
  try {
    final connected = await ch.invokeMethod<bool>('connected') ?? false;
    final prefs = await SharedPreferences.getInstance();
    final up = Completer<void>();
    final v2 = V2ray(onStatusChanged: (st) {
      if (st.state == 'CONNECTED' && !up.isCompleted) up.complete();
    });
    await v2.initialize(
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
    );
    if (connected) {
      await v2.stopV2Ray();
      await ch.invokeMethod('state', {'connected': false, 'name': ''});
    } else {
      final raw = prefs.getString('servers');
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => Server.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (list.isEmpty) return;
      final sel = prefs.getString('selected');
      final s = list.firstWhere((e) => e.id == sel, orElse: () => list.first);
      final r = resolveKey(s.link);
      final blocked = prefs.getStringList('blocked_cache');
      await v2.startV2Ray(
        remark: r.remark,
        config: r.config,
        blockedApps: (blocked == null || blocked.isEmpty) ? null : blocked,
        bypassSubnets: null,
        proxyOnly: false,
      );
      await up.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      final active = up.isCompleted ||
          (await ch.invokeMethod<bool>('vpnActive') ?? false);
      if (active) {
        await ch.invokeMethod('state',
            {'connected': true, 'name': '${s.flag} ${s.displayName}'});
      }
    }
  } catch (_) {
  } finally {
    try {
      await ch.invokeMethod('done');
    } catch (_) {}
  }
}
