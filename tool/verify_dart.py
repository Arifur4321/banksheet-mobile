#!/usr/bin/env python3
"""Static verifier for the BankSheet Flutter app.

`flutter analyze` cannot run here (pub.dev and the Flutter SDK mirrors are
blocked in this sandbox), so this reproduces the checks that actually catch
build-breaking bugs in generated code: unresolved imports, undefined symbols,
missing string keys, missing route names, missing member constants, duplicate
declarations, and dependency coverage.

It is deliberately conservative: it only reports a symbol as undefined when it
is confident, so every finding is worth acting on.
"""
import os, re, sys, json
from collections import defaultdict

# Derived from this file's location rather than hardcoded, so the verifier
# runs from any checkout — it was pinned to the original build sandbox and
# therefore only ever worked on the machine it was written on.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, 'lib')
TEST = os.path.join(ROOT, 'test')
PKG = 'banksheet_mobile'

problems = []
warnings = []


def add(kind, msg):
    (problems if kind == 'E' else warnings).append(msg)


def dart_files(*roots):
    out = []
    for r in roots:
        for dirpath, _, names in os.walk(r):
            for n in names:
                if n.endswith('.dart'):
                    out.append(os.path.join(dirpath, n))
    return sorted(out)


FILES = dart_files(LIB, TEST)
SRC = {f: open(f, encoding='utf-8').read() for f in FILES}


def strip_code(text):
    """Remove comments and string literals so scanning sees only code."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            i = n if j < 0 else j
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            i = n if j < 0 else j + 2
        elif c in '\'"':
            # triple quoted?
            triple = text[i:i + 3]
            if triple in ("'''", '"""'):
                j = text.find(triple, i + 3)
                i = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n:
                    if text[j] == '\\':
                        j += 2
                        continue
                    if text[j] == c:
                        break
                    if text[j] == '\n':
                        break
                    j += 1
                i = j + 1
            out.append(' ')
        else:
            out.append(c)
            i += 1
    return ''.join(out)


CODE = {f: strip_code(t) for f, t in SRC.items()}

# ---------------------------------------------------------------- 1. balance
for f, code in CODE.items():
    depth = {'(': 0, '[': 0, '{': 0}
    pairs = {')': '(', ']': '[', '}': '{'}
    for ch in code:
        if ch in depth:
            depth[ch] += 1
        elif ch in pairs:
            depth[pairs[ch]] -= 1
    for op, d in depth.items():
        if d != 0:
            add('E', f'UNBALANCED {op!r} ({d:+d}) in {os.path.relpath(f, ROOT)}')

# ------------------------------------------------------------- 2. declarations
DECL = re.compile(
    r'^\s*(?:@\w+\s+)*(?:abstract\s+|final\s+|base\s+|interface\s+|sealed\s+)*'
    r'(class|mixin|enum|extension|typedef)\s+(\w+)', re.M)
declared = defaultdict(list)      # name -> [file]
for f, code in CODE.items():
    for kind, name in DECL.findall(code):
        declared[name].append(f)

for name, where in declared.items():
    if len(where) > 1 and not name.startswith('_'):
        rels = ', '.join(os.path.relpath(w, ROOT) for w in where)
        add('W', f'DUPLICATE public declaration {name} in {rels}')

# top-level functions and variables (providers live here)
TOPLEVEL = re.compile(
    r'^(?:final|const)\s+[\w<>,\s\?\.]+?\s+(\w+)\s*=', re.M)
for f, code in CODE.items():
    for name in TOPLEVEL.findall(code):
        declared[name].append(f)

# ---------------------------------------------------------------- 3. imports
def resolve(imp, from_file):
    if imp.startswith('package:%s/' % PKG):
        return os.path.join(LIB, imp[len('package:%s/' % PKG):])
    if imp.startswith(('package:', 'dart:')):
        return None  # external
    return os.path.normpath(os.path.join(os.path.dirname(from_file), imp))


IMPORT = re.compile(r"^\s*(?:import|export)\s+'([^']+)'", re.M)
imports_of = {}
for f, code in SRC.items():
    imps = IMPORT.findall(code)
    imports_of[f] = imps
    for imp in imps:
        target = resolve(imp, f)
        if target is None:
            continue
        if not os.path.isfile(target):
            add('E', f'UNRESOLVED IMPORT {imp!r} in {os.path.relpath(f, ROOT)}')

# ------------------------------------------------- 4. pubspec covers packages
pubspec = open(os.path.join(ROOT, 'pubspec.yaml'), encoding='utf-8').read()
declared_pkgs = set(re.findall(r'^\s{2}([a-z_0-9]+):', pubspec, re.M))
declared_pkgs |= {'flutter', 'flutter_test', PKG}
used_pkgs = set()
for f, imps in imports_of.items():
    for imp in imps:
        m = re.match(r'package:([a-z_0-9]+)/', imp)
        if m:
            used_pkgs.add(m.group(1))
for p in sorted(used_pkgs - declared_pkgs):
    add('E', f'PACKAGE {p!r} imported but not in pubspec.yaml dependencies')

# ------------------------------------------------- 5. member constant checks
def members_of(path, class_name):
    code = CODE[path]
    m = re.search(r'(?:abstract\s+final\s+|final\s+)?class\s+%s\b' % class_name, code)
    if not m:
        return set()
    start = code.index('{', m.end())
    depth, i = 0, start
    while i < len(code):
        if code[i] == '{':
            depth += 1
        elif code[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = code[start:i]
    names = set(re.findall(r'\b(?:static\s+)?(?:const|final)\s+[\w<>,\s\?\.]+?\s+(\w+)\s*[=;]', body))
    names |= set(re.findall(r'\bstatic\s+[\w<>,\s\?\.]+?\s+(\w+)\s*\(', body))
    names |= set(re.findall(r'\bstatic\s+[\w<>,\s\?\.]*?\bget\s+(\w+)', body))
    names |= set(re.findall(r'\b(\w+)\s*\(', body))  # constructors/methods
    return names


CONSTANT_HOLDERS = {
    'S':          os.path.join(LIB, 'core/i18n/strings.dart'),
    'AppRoute':   os.path.join(LIB, 'app/routes.dart'),
    'AppColors':  os.path.join(LIB, 'core/theme/tokens.dart'),
    'AppRadius':  os.path.join(LIB, 'core/theme/tokens.dart'),
    'AppSpacing': os.path.join(LIB, 'core/theme/tokens.dart'),
    'AppShadows': os.path.join(LIB, 'core/theme/tokens.dart'),
    'AppMotion':  os.path.join(LIB, 'core/theme/tokens.dart'),
    'AppText':    os.path.join(LIB, 'core/theme/typography.dart'),
    'Fmt':        os.path.join(LIB, 'core/utils/formatters.dart'),
    'J':          os.path.join(LIB, 'core/utils/json.dart'),
    'Endpoints':  os.path.join(LIB, 'core/network/endpoints.dart'),
    'AppConfig':  os.path.join(LIB, 'core/config/app_config.dart'),
    'Log':        os.path.join(LIB, 'core/utils/logger.dart'),
}

holder_members = {}
for holder, path in CONSTANT_HOLDERS.items():
    if os.path.isfile(path):
        holder_members[holder] = members_of(path, holder)
    else:
        add('E', f'MISSING holder file for {holder}: {path}')

for f, code in CODE.items():
    for holder, known in holder_members.items():
        for m in re.finditer(r'\b%s\.(\w+)' % holder, code):
            name = m.group(1)
            if name not in known:
                line = code[:m.start()].count('\n') + 1
                add('E', f'{holder}.{name} does not exist — {os.path.relpath(f, ROOT)}:{line}')

# ------------------------------------------------- 6. cross-file type usage
# Build the visible symbol set per file: own declarations + everything the
# files it imports (transitively through exports) declare.
declared_in = defaultdict(set)
for f, code in CODE.items():
    for kind, name in DECL.findall(code):
        declared_in[f].add(name)
    for name in TOPLEVEL.findall(code):
        declared_in[f].add(name)
    # enum values and static consts are reached via the type name, skip

SDK = set('''
Widget StatelessWidget StatefulWidget State BuildContext Key GlobalKey ValueKey
Text Column Row Container Padding Center Align Expanded Flexible SizedBox Spacer
Stack Positioned ListView GridView SingleChildScrollView CustomScrollView
SliverList SliverGrid SliverToBoxAdapter SliverFillRemaining SliverPadding
SliverAppBar SliverList Scaffold AppBar Drawer BottomNavigationBar NavigationBar
NavigationDestination FloatingActionButton Icon IconData Icons Image ImageProvider
Colors Color Theme ThemeData ColorScheme TextStyle TextTheme TextAlign TextOverflow
TextDirection FontWeight FontStyle FontFeature EdgeInsets EdgeInsetsGeometry
BorderRadius Radius Border BorderSide BoxDecoration BoxShadow BoxFit BoxConstraints
Decoration ShapeBorder RoundedRectangleBorder StadiumBorder CircleBorder
Material MaterialApp InkWell GestureDetector Listener MouseRegion
TextButton ElevatedButton OutlinedButton FilledButton IconButton
TextField TextFormField TextEditingController FocusNode Form FormState
InputDecoration InputDecorationTheme OutlineInputBorder UnderlineInputBorder
Checkbox Switch Radio Slider DropdownButton DropdownMenuItem DropdownButtonFormField
CircularProgressIndicator LinearProgressIndicator RefreshIndicator
Divider ListTile Card Chip ActionChip FilterChip InputChip
SnackBar SnackBarAction ScaffoldMessenger ScaffoldMessengerState
showDialog showModalBottomSheet showDatePicker AlertDialog Dialog BottomSheet
Navigator NavigatorState Route MaterialPageRoute PageRoute
AnimationController Animation Tween CurvedAnimation Curves Curve Cubic
AnimatedBuilder AnimatedContainer AnimatedOpacity AnimatedSwitcher
TweenAnimationBuilder FadeTransition SlideTransition ScaleTransition
Transform Matrix4 Offset Size Rect Alignment AlignmentGeometry FractionalOffset
CustomPaint CustomPainter Canvas Paint Path PaintingStyle StrokeCap StrokeJoin
Gradient LinearGradient RadialGradient SweepGradient
MediaQuery MediaQueryData Orientation Brightness
Duration DateTime String int double num bool List Map Set Iterable Future Stream
Object Function Comparable Exception Error StateError ArgumentError
RangeError UnsupportedError FormatException TimeoutException
StreamSubscription StreamController Completer Timer
File Directory FileSystemException Platform Process SocketException HttpClient
Uint8List ByteData Random
Uri Encoding utf8 base64 base64Url json jsonEncode jsonDecode
ChangeNotifier ValueNotifier Listenable ValueListenable
ConsumerWidget ConsumerStatefulWidget ConsumerState WidgetRef Ref
Provider StateProvider FutureProvider StreamProvider StateNotifier
StateNotifierProvider AsyncValue AsyncData AsyncError AsyncLoading
ProviderScope Override AutoDisposeProvider ProviderListenable
GoRouter GoRoute ShellRoute GoRouterState RouteBase NoTransitionPage
Dio Response BaseOptions Options RequestOptions FormData MultipartFile
CancelToken DioException DioExceptionType Interceptor QueuedInterceptor
InterceptorsWrapper RequestInterceptorHandler ErrorInterceptorHandler
ResponseInterceptorHandler
SharedPreferences FlutterSecureStorage AndroidOptions IOSOptions
KeychainAccessibility
PackageInfo DeviceInfoPlugin AndroidDeviceInfo IosDeviceInfo
Connectivity ConnectivityResult
InAppPurchase ProductDetails PurchaseDetails PurchaseParam PurchaseStatus
ProductDetailsResponse IAPError InAppPurchaseStoreKitPlatformAddition
AppStorePurchaseParam GooglePlayPurchaseParam
FilePicker FilePickerResult PlatformFile FileType
ImagePicker XFile ImageSource
OpenFilex OpenResult ResultType
Share ShareResult XFile SharePlus ShareParams
Clipboard ClipboardData SystemChrome SystemUiOverlayStyle DeviceOrientation
HapticFeedback SystemSound PlatformException MethodChannel
launchUrl launchUrlString canLaunchUrl LaunchMode
getApplicationDocumentsDirectory getTemporaryDirectory
compute WidgetsBinding WidgetsFlutterBinding SchedulerBinding TickerMode
Ticker TickerProvider SingleTickerProviderStateMixin TickerProviderStateMixin
WidgetsBindingObserver AppLifecycleState
kDebugMode kReleaseMode kProfileMode defaultTargetPlatform TargetPlatform
immutable protected visibleForTesting required override
DecoratedBox ClipRRect ClipOval ClipPath Opacity IgnorePointer AbsorbPointer
Semantics ExcludeSemantics MergeSemantics Tooltip Hero Visibility Wrap
IntrinsicHeight IntrinsicWidth LayoutBuilder OrientationBuilder SafeArea
ReorderableListView Dismissible DismissDirection Draggable DragTarget
ScrollController ScrollPhysics NeverScrollableScrollPhysics
AlwaysScrollableScrollPhysics BouncingScrollPhysics ClampingScrollPhysics
NotificationListener ScrollNotification ScrollEndNotification
WidgetStateProperty WidgetState WidgetStatePropertyAll MaterialStateProperty
TextScaler TextInputType TextInputAction TextCapitalization
FilteringTextInputFormatter LengthLimitingTextInputFormatter TextInputFormatter
AutofillHints Localizations DefaultMaterialLocalizations
CardThemeData DialogThemeData BottomSheetThemeData SnackBarThemeData
NavigationBarThemeData ListTileThemeData ChipThemeData DividerThemeData
ProgressIndicatorThemeData SwitchThemeData TooltipThemeData IconThemeData
AppBarTheme InputDecorationTheme FilledButtonThemeData OutlinedButtonThemeData
TextButtonThemeData IconButtonThemeData PageTransitionsTheme
CupertinoPageTransitionsBuilder PageTransitionsBuilder InkSparkle VisualDensity
NavigationDestinationLabelBehavior SnackBarBehavior
FlutterError FlutterErrorDetails ErrorWidget
Queue LinkedHashMap HashMap HashSet SplayTreeMap UnmodifiableListView

MainAxisSize MainAxisAlignment CrossAxisAlignment MapEntry RegExp Match RegExpMatch
BoxShape VoidCallback ValueChanged ValueGetter ValueSetter AsyncCallback
AlwaysStoppedAnimation Clip HitTestBehavior DragStartDetails DragUpdateDetails
DragEndDetails TapDownDetails TapUpDetails LongPressStartDetails ScaleUpdateDetails
FocusScope FocusManager AutofillGroup TextInput TextSelection TextEditingValue
StackTrace Type Symbol Record Enum Iterator Comparator Pattern Sink StringBuffer
StringSink Stopwatch Expando WeakReference Finalizer Zone
Positioned Directionality Baseline ConstrainedBox UnconstrainedBox FittedBox
AspectRatio FractionallySizedBox LimitedBox OverflowBox SizedOverflowBox
Table TableRow TableCell TableBorder TableColumnWidth FlexColumnWidth
FixedColumnWidth IntrinsicColumnWidth Flex Axis WrapAlignment WrapCrossAlignment
VerticalDirection TextBaseline StackFit OverflowBarAlignment
ScrollView ScrollbarThemeData Scrollbar PageView PageController TabBar TabBarView
TabController DefaultTabController Tab NestedScrollView
ExpansionTile ExpansionPanel ExpansionPanelList Stepper Step
PopupMenuButton PopupMenuItem PopupMenuEntry MenuAnchor MenuItemButton
SearchBar SearchAnchor SegmentedButton ButtonSegment ToggleButtons
BadgeThemeData Badge CircleAvatar
BackdropFilter ImageFilter ColorFilter BlendMode FilterQuality
FontFeature FontVariation StrutStyle TextSpan InlineSpan WidgetSpan RichText
TextPainter TextHeightBehavior TextWidthBasis Locale
NumberFormat DateFormat
GlobalObjectKey UniqueKey ObjectKey LabeledGlobalKey PageStorageKey
InheritedWidget StatefulBuilder Builder LayoutId CustomMultiChildLayout
RepaintBoundary KeyedSubtree AutomaticKeepAliveClientMixin
RestorationMixin WidgetsApp Router RouteInformationParser RouterDelegate
BackButtonDispatcher RouteInformation
Diagnosticable DiagnosticableTree DiagnosticPropertiesBuilder
CupertinoIcons CupertinoActivityIndicator
ThemeExtension MaterialLocalizations
Rectangle Point Vector3 Matrix3 Quaternion
BigInt Runes RuneIterator
Endian ByteBuffer Int8List Int16List Int32List Int64List Uint16List Uint32List
Float32List Float64List
IOSink RandomAccessFile FileMode FileStat Link
Isolate SendPort ReceivePort Capability
JsonEncoder JsonDecoder JsonCodec Utf8Codec Utf8Encoder Utf8Decoder
Base64Codec Base64Encoder Base64Decoder AsciiCodec LineSplitter Codec Converter
HttpHeaders HttpStatus ContentType Cookie HttpDate
Directory Process ProcessResult ProcessSignal Stdin Stdout
NetworkImage AssetImage MemoryImage FileImage ResizeImage ImageStream
ImageInfo ImageConfiguration ImageCache ImageErrorListener
Image ImageByteFormat
PurchaseVerificationData ProductDetailsResponse RestoreError
AppStoreProductDetails GooglePlayProductDetails AppStorePurchaseDetails
GooglePlayPurchaseDetails SKPaymentQueueWrapper BillingResultWrapper
InAppPurchaseAndroidPlatformAddition
ShareResultStatus
FileSystemEntity FileSystemEntityType
LinkedHashSet ListQueue DoubleLinkedQueue
Decoder Encoder JpegEncoder PngEncoder JpegDecoder PngDecoder
Command Interpolation

'''.split())

for f, code in CODE.items():
    visible = set(declared_in[f]) | SDK
    for imp in imports_of[f]:
        target = resolve(imp, f)
        if target and target in declared_in:
            visible |= declared_in[target]
            # one level of re-export
            for sub in imports_of.get(target, []):
                st = resolve(sub, target)
                if st and st in declared_in and re.search(
                        r"export\s+'%s'" % re.escape(sub), SRC[target]):
                    visible |= declared_in[st]

    # Types used in a `Type name` position or `Type(` construction
    for m in re.finditer(r'\b([A-Z]\w{2,})\s*(?:\.|\(|<|\s+\w+\s*[=;,\)])', code):
        name = m.group(1)
        if name in visible or name.startswith('_'):
            continue
        # skip enum-ish access on known holders
        if name in CONSTANT_HOLDERS:
            continue
        line = code[:m.start()].count('\n') + 1
        if name in declared:
            add('E', f'{name} used but NOT IMPORTED — {os.path.relpath(f, ROOT)}:{line} '
                     f'(declared in {os.path.relpath(declared[name][0], ROOT)})')
        else:
            add('W', f'unknown symbol {name} — {os.path.relpath(f, ROOT)}:{line}')

# ------------------------------------------------- 7. hygiene
for f, code in CODE.items():
    rel = os.path.relpath(f, ROOT)
    for m in re.finditer(r'(?<![\w.])print\s*\(', code):
        add('E', f'print() call — {rel}:{code[:m.start()].count(chr(10)) + 1}')
    for m in re.finditer(r'\.withOpacity\s*\(', code):
        add('W', f'deprecated withOpacity — {rel}:{code[:m.start()].count(chr(10)) + 1}')
for f, text in SRC.items():
    rel = os.path.relpath(f, ROOT)
    for kw in ('TODO', 'FIXME', 'XXX:'):
        for m in re.finditer(kw, text):
            add('W', f'{kw} marker — {rel}:{text[:m.start()].count(chr(10)) + 1}')

# ------------------------------------------------- 8. assets declared exist
for asset in re.findall(r'^\s+-\s+(assets/[^\s]+)', pubspec, re.M):
    p = os.path.join(ROOT, asset)
    if asset.endswith('/'):
        if not os.path.isdir(p):
            add('W', f'asset directory missing: {asset}')
    elif not os.path.isfile(p):
        add('W', f'asset missing: {asset}')

# ------------------------------------------------- report
print(f'files: {len(FILES)}   declarations: {len(declared)}   '
      f'packages: {len(used_pkgs)}')
print(f'\nERRORS: {len(problems)}')
for p in problems[:400]:
    print('  E', p)
print(f'\nWARNINGS: {len(warnings)}')
seen = set()
for w in warnings[:200]:
    if w not in seen:
        seen.add(w)
        print('  W', w)
sys.exit(1 if problems else 0)
