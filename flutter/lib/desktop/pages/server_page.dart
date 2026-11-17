// original cm window in Sciter version.

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';

/// Set only by this window's own close control, and only once the user has confirmed. Any other
/// way the window can go - a session logout closing every window, the window manager, a native
/// title-bar button this app does not draw - leaves it false, which is the honest answer:
/// nothing in that close says who asked for it. It lives at file scope because the control that
/// sets it (`ConnectionManagerState`) and the handler that reads it (`_DesktopServerPageState`)
/// are different widgets.
bool _cmClosedByOperator = false;

/// AniDesk: baslaticinin Tema.cs degerleri (koyu = Tema m=0, aydinlik = Tema m=1).
/// Secim: ANIDESK_TEMA=acik|koyu (baslatici Seceneklerinden gelir), yoksa Windows AppsUseLightTheme.
bool _aniAcikMi() {
  final e = (Platform.environment['ANIDESK_TEMA'] ?? '').trim().toLowerCase();
  if (e == 'acik') return true;
  if (e == 'koyu') return false;
  return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.light;
}

/// Sistem temasi degisince (platformBrightness) yeniden cizilmek icin build icinde cagrilir.
bool _aniDinle(BuildContext context) {
  MediaQuery.platformBrightnessOf(context);
  return _aniAcikMi();
}

Color get _aniZemin => _aniAcikMi() ? Color(0xFFF7F4EC) : Color(0xFF0B0A10);
Color get _aniZemin2 => _aniAcikMi() ? Color(0xFFFCFAF5) : Color(0xFF17131F);
Color get _aniYuzey => _aniAcikMi() ? Color(0xFFFFFFFF) : Color(0xFF12101A);
Color get _aniYuzeyUst => _aniAcikMi() ? Color(0xFFFFFFFF) : Color(0xFF1B1726);
Color get _aniAltin => _aniAcikMi() ? Color(0xFFA07216) : Color(0xFFD4A853);
Color get _aniAltinAcik => _aniAcikMi() ? Color(0xFF7A5408) : Color(0xFFE6C37A);
Color get _aniSinyal => _aniAcikMi() ? Color(0xFF087680) : Color(0xFF4FD0DC);
Color get _aniOk => _aniAcikMi() ? Color(0xFF1C7644) : Color(0xFF6FCF97);
Color get _aniInk100 => _aniAcikMi() ? Color(0xFF2B2832) : Color(0xFFE8E2D9);
Color get _aniInk300 => _aniAcikMi() ? Color(0xFF5E5964) : Color(0xFFB5A089);
Color get _aniCizgi => _aniAcikMi() ? Color(0x6EA87A1E) : Color(0x46D4A853);
Color get _aniPrimUst => _aniAcikMi() ? Color(0xFF9C6C12) : Color(0xFFE6C37A);
Color get _aniPrimAlt => _aniAcikMi() ? Color(0xFF7E540A) : Color(0xFFD4A853);
Color get _aniPrimYazi => _aniAcikMi() ? Color(0xFFFFFFFF) : Color(0xFF0B0A10);
const List<String> _aniFontYedek = ['Segoe UI', 'Tahoma'];

/// Pencere basligi = baslaticiya giden durum (baslatici --cm penceresinin basligini okur).
/// Protokol: istek bekliyor -> 'AniDesk · destek isteği'; yetki verildi -> 'AniDesk · bağlı';
/// hepsi bitti -> 'AniDesk · bağlantı sona erdi'.
const String kAniBaslikIstek = 'AniDesk · destek isteği';
const String kAniBaslikBagli = 'AniDesk · bağlı';
const String kAniBaslikBitti = 'AniDesk · bağlantı sona erdi';

void _aniBaslikUygula() {
  final cl = gFFI.serverModel.clients;
  if (cl.isEmpty) return;
  String t;
  if (cl.any((c) => !c.authorized && !c.disconnected)) {
    t = kAniBaslikIstek;
  } else if (cl.any((c) => c.authorized && !c.disconnected)) {
    t = kAniBaslikBagli;
  } else {
    t = kAniBaslikBitti;
  }
  windowManager.setTitle(t);
}

TextStyle _aniYazi(double size, Color color, {FontWeight? weight}) => TextStyle(
    fontFamily: 'Segoe UI Variable Text',
    fontFamilyFallback: _aniFontYedek,
    fontSize: size,
    color: color,
    fontWeight: weight);

class DesktopServerPage extends StatefulWidget {
  const DesktopServerPage({Key? key}) : super(key: key);

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage>
    with WindowListener, AutomaticKeepAliveClientMixin {
  final tabController = gFFI.serverModel.tabController;

  _DesktopServerPageState() {
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, "");
    Get.put<DesktopTabController>(tabController);
    tabController.onRemoved = (_, id) {
      onRemoveId(id);
    };
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    // Other platforms keep the old behaviour exactly: the ambiguity this guards against is a
    // Linux session logout, which closes every window in the session.
    final byOperator = _cmClosedByOperator || !isLinux;
    Future.wait([gFFI.serverModel.closeAll(byOperator: byOperator), gFFI.close()]).then((_) {
      if (isMacOS) {
        RdPlatformChannel.instance.terminate();
      } else {
        windowManager.setPreventClose(false);
        windowManager.close();
      }
    });
    super.onWindowClose();
  }

  void onRemoveId(String id) {
    if (tabController.state.value.tabs.isEmpty) {
      windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.serverModel),
        ChangeNotifierProvider.value(value: gFFI.chatModel),
      ],
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) {
          final acik = _aniDinle(context);
          final body = Scaffold(
            backgroundColor: Colors.transparent,
            body: DefaultTextStyle.merge(
              style: TextStyle(
                  fontFamily: 'Segoe UI Variable Text',
                  fontFamilyFallback: _aniFontYedek),
              child: Theme(
                  data: acik ? MyTheme.lightTheme : MyTheme.darkTheme,
                  child: ConnectionManager()),
            ),
          );
          return isLinux
              ? buildVirtualWindowFrame(context, body)
              : workaroundWindowBorder(
                  context,
                  Container(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [_aniZemin2, _aniZemin]),
                        border: Border.all(color: _aniCizgi)),
                    child: body,
                  ));
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ConnectionManager extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => ConnectionManagerState();
}

class ConnectionManagerState extends State<ConnectionManager>
    with WidgetsBindingObserver {
  final RxBool _controlPageBlock = false.obs;
  final RxBool _sidePageBlock = false.obs;

  ConnectionManagerState() {
    gFFI.serverModel.tabController.onSelected = (client_id_str) {
      final client_id = int.tryParse(client_id_str);
      if (client_id != null) {
        final client =
            gFFI.serverModel.clients.firstWhereOrNull((e) => e.id == client_id);
        if (client != null) {
          gFFI.chatModel.changeCurrentKey(MessageKey(client.peerId, client.id));
          if (client.unreadChatMessageCount.value > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              client.unreadChatMessageCount.value = 0;
              gFFI.chatModel.showChatPage(MessageKey(client.peerId, client.id));
            });
          }
          _aniBaslikUygula();
          gFFI.cmFileModel.updateCurrentClientId(client.id);
        }
      }
    };
    gFFI.chatModel.isConnManager = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (!allowRemoteCMModification()) {
        shouldBeBlocked(_controlPageBlock, null);
        shouldBeBlocked(_sidePageBlock, null);
      }
    }
  }

  @override
  void initState() {
    gFFI.serverModel.updateClientState();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    _aniDinle(context);
    pointerHandler(PointerEvent e) {
      if (serverModel.cmHiddenTimer != null) {
        serverModel.cmHiddenTimer!.cancel();
        serverModel.cmHiddenTimer = null;
        debugPrint("CM hidden timer has been canceled");
      }
    }

    return serverModel.clients.isEmpty
        ? Column(
            children: [
              buildTitleBar(),
              Expanded(
                child: Center(
                  child: Text('Bekleniyor...',
                      style: _aniYazi(14, _aniInk300)),
                ),
              ),
            ],
          )
        : Listener(
            onPointerDown: pointerHandler,
            onPointerMove: pointerHandler,
            child: DesktopTab(
              showTitle: false,
              showLogo: false,
              showMaximize: false,
              showMinimize: true,
              showClose: true,
              onWindowCloseButton: handleWindowCloseButton,
              controller: serverModel.tabController,
              selectedBorderColor: MyTheme.accent,
              maxLabelWidth: 100,
              tabStripOverride:
                  serverModel.clients.length <= 1 ? const _AppIcon() : null,
              tail: null, //buildScrollJumper(),
              tabBuilder: (key, icon, label, themeConf) {
                final client = serverModel.clients
                    .firstWhereOrNull((client) => client.id.toString() == key);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                        message: key,
                        waitDuration: Duration(seconds: 1),
                        child: label),
                    unreadMessageCountBuilder(client?.unreadChatMessageCount)
                        .marginOnly(left: 4),
                  ],
                );
              },
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constrains) {
                  var borderWidth = 0.0;
                  if (constrains.maxWidth >
                      kConnectionManagerWindowSizeClosedChat.width) {
                    borderWidth = kConnectionManagerWindowSizeOpenChat.width -
                        constrains.maxWidth;
                  } else {
                    borderWidth = kConnectionManagerWindowSizeClosedChat.width -
                        constrains.maxWidth;
                  }
                  if (borderWidth < 0 || borderWidth > 50) {
                    borderWidth = 0;
                  }
                  final realClosedWidth =
                      kConnectionManagerWindowSizeClosedChat.width -
                          borderWidth;
                  final realChatPageWidth =
                      constrains.maxWidth - realClosedWidth;
                  final row = Row(children: [
                    if (constrains.maxWidth >
                        kConnectionManagerWindowSizeClosedChat.width)
                      Consumer<ChatModel>(
                          builder: (_, model, child) => SizedBox(
                                width: realChatPageWidth,
                                child: allowRemoteCMModification()
                                    ? buildSidePage()
                                    : buildRemoteBlock(
                                        child: buildSidePage(),
                                        block: _sidePageBlock,
                                        mask: true),
                              )),
                    SizedBox(
                        width: realClosedWidth,
                        child: SizedBox(
                            width: realClosedWidth,
                            child: allowRemoteCMModification()
                                ? pageView
                                : buildRemoteBlock(
                                    child: _buildKeyEventBlock(pageView),
                                    block: _controlPageBlock,
                                    mask: false,
                                  ))),
                  ]);
                  return Container(
                    color: Colors.transparent,
                    child: row,
                  );
                },
              ),
            ),
          );
  }

  Widget buildSidePage() {
    final selected = gFFI.serverModel.tabController.state.value.selected;
    if (selected < 0 || selected >= gFFI.serverModel.clients.length) {
      return Offstage();
    }
    final clientType = gFFI.serverModel.clients[selected].type_();
    if (clientType == ClientType.file) {
      return _FileTransferLogPage();
    } else {
      return ChatPage(type: ChatPageType.desktopCM);
    }
  }

  Widget _buildKeyEventBlock(Widget child) {
    return ExcludeFocus(child: child, excluding: true);
  }

  Widget buildTitleBar() {
    return SizedBox(
      height: kDesktopRemoteTabBarHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _AppIcon(),
          Expanded(
            child: GestureDetector(
              onPanStart: (d) {
                windowManager.startDragging();
              },
              child: Container(
                color: Theme.of(context).colorScheme.background,
              ),
            ),
          ),
          const SizedBox(
            width: 4.0,
          ),
          const _CloseButton()
        ],
      ),
    );
  }

  Widget buildScrollJumper() {
    final offstage = gFFI.serverModel.clients.length < 2;
    final sc = gFFI.serverModel.tabController.state.value.scrollController;
    return Offstage(
        offstage: offstage,
        child: Row(
          children: [
            ActionIcon(
                icon: Icons.arrow_left, iconSize: 22, onTap: sc.backward),
            ActionIcon(
                icon: Icons.arrow_right, iconSize: 22, onTap: sc.forward),
          ],
        ));
  }

  Future<bool> handleWindowCloseButton() async {
    var tabController = gFFI.serverModel.tabController;
    final connLength = tabController.length;
    if (connLength <= 1) {
      _cmClosedByOperator = true;
      windowManager.close();
      return true;
    } else {
      final bool res;
      if (!option2bool(kOptionEnableConfirmClosingTabs,
          bind.mainGetLocalOption(key: kOptionEnableConfirmClosingTabs))) {
        res = true;
      } else {
        res = await closeConfirmDialog();
      }
      if (res) {
        // After the dialog, never before it: an external close while it is open must not
        // inherit an intent the user had not expressed yet.
        _cmClosedByOperator = true;
        windowManager.close();
      }
      return res;
    }
  }
}

Widget buildConnectionCard(Client client) {
  return Consumer<ServerModel>(
    builder: (context, value, child) {
      _aniDinle(context);
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        key: ValueKey(client.id),
        children: [
          // Ust bolum kaydirilabilir: pencere/DPI ne olursa olsun hicbir oge kesilmez, dugmeler altta sabit.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CmHeader(client: client),
                  client.type_() == ClientType.file ||
                          client.type_() == ClientType.portForward ||
                          client.type_() == ClientType.terminal ||
                          client.disconnected
                      ? Offstage()
                      : _IzinOzeti(client: client),
                ],
              ),
            ),
          ),
          _CmControlPanel(client: client),
        ],
      ).paddingSymmetric(vertical: 4.0, horizontal: 8.0);
    },
  );
}

/// AniDesk isareti: baslaticidaki altin kalkan + A (Ortak.cs MonogramCiz ile ayni geometri).
class _KalkanBoyaci extends CustomPainter {
  final Color ust, alt, yazi;
  _KalkanBoyaci(this.ust, this.alt, this.yazi);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 16, sy = size.height / 20;
    Offset o(double x, double y) => Offset(x * sx, y * sy);
    final yol = Path()
      ..moveTo(0, 2 * sy)
      ..lineTo(8 * sx, 0)
      ..lineTo(16 * sx, 2 * sy)
      ..lineTo(16 * sx, 10 * sy)
      ..cubicTo(16 * sx, 15 * sy, 11 * sx, 18 * sy, 8 * sx, 20 * sy)
      ..cubicTo(5 * sx, 18 * sy, 0, 15 * sy, 0, 10 * sy)
      ..close();
    canvas.drawPath(
        yol,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ust, alt])
              .createShader(Offset.zero & size));
    canvas.drawPath(
        yol,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = yazi.withOpacity(0.25));
    final kalem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * sx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = yazi;
    canvas.drawPath(
        Path()
          ..moveTo(4.6 * sx, 13.5 * sy)
          ..lineTo(8 * sx, 5.2 * sy)
          ..lineTo(11.4 * sx, 13.5 * sy),
        kalem);
    canvas.drawLine(o(5.9, 10.6), o(10.1, 10.6), kalem);
  }

  @override
  bool shouldRepaint(covariant _KalkanBoyaci old) =>
      old.ust != ust || old.alt != alt || old.yazi != yazi;
}

Widget _aniKalkan(double yukseklik) {
  return SizedBox(
    width: yukseklik * 0.8,
    height: yukseklik,
    child: CustomPaint(
        painter: _KalkanBoyaci(
            _aniAcikMi() ? Color(0xFFAC7A1A) : Color(0xFFF6D690),
            _aniAcikMi() ? Color(0xFF7E540A) : Color(0xFFC88C3E),
            _aniAcikMi() ? Color(0xFFFFFFFF) : Color(0xFF1A1208))),
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    _aniDinle(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8.0),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _aniKalkan(18),
            SizedBox(width: 8),
            Text('AniDesk',
                style: _aniYazi(13, _aniAltin, weight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        windowManager.close();
      },
      icon: const Icon(
        IconFont.close,
        size: 18,
      ),
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );
  }
}

class _CmHeader extends StatefulWidget {
  final Client client;

  const _CmHeader({Key? key, required this.client}) : super(key: key);

  @override
  State<_CmHeader> createState() => _CmHeaderState();
}

class _CmHeaderState extends State<_CmHeader>
    with AutomaticKeepAliveClientMixin {
  Client get client => widget.client;

  final _time = 0.obs;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (client.authorized && !client.disconnected) {
        _time.value = _time.value + 1;
      }
    });
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.serverModel.tabController.onSelected?.call(client.id.toString());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _aniDinle(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _aniBaslikUygula());
    final String baslik = 'Teknisyeniniz bağlanmak istiyor';
    final String durum = client.authorized
        ? (client.disconnected
            ? 'Bağlantı sona erdi'
            : 'Bağlı · teknisyeniniz ekranınızı görüyor')
        : 'İzninizi bekliyor';
    final Color durumRenk = client.authorized && !client.disconnected
        ? _aniSinyal
        : (client.disconnected ? _aniInk300 : _aniSinyal);
    String? tur;
    if (client.type_() == ClientType.terminal) tur = 'Terminal';
    if (client.type_() == ClientType.file) tur = 'Dosya aktarımı';
    if (client.type_() == ClientType.camera) tur = 'Kamera görüntüsü';
    if (client.portForward.isNotEmpty) {
      tur = 'Port Forward: ${client.portForward}';
    }
    final String ad = client.name.trim();
    final String kimlikSatiri =
        'Bağlanan: ${ad.isNotEmpty ? ad + ' · ' : ''}${client.peerId}';
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
      padding: EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik,
                    style:
                        _aniYazi(22, _aniAltinAcik, weight: FontWeight.bold)),
                SizedBox(height: 14.0),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14.0),
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_aniYuzeyUst, _aniYuzey]),
                    border: Border.all(color: _aniSinyal.withOpacity(0.45)),
                    boxShadow: [
                      BoxShadow(
                          color: _aniSinyal.withOpacity(0.10),
                          blurRadius: 14,
                          offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Bilgisayarınızda yardımcı olmak için uzaktan bağlanmak istiyor. İzin verirseniz ekranınızı görebilir.',
                          style: _aniYazi(14, _aniInk100)),
                      SizedBox(height: 8),
                      Text(kimlikSatiri,
                          softWrap: true, style: _aniYazi(12, _aniInk300)),
                      if (tur != null)
                        Text(tur, style: _aniYazi(12, _aniInk300)),
                    ],
                  ),
                ),
                SizedBox(height: 12.0),
                Row(
                  children: [
                    Text('●  ', style: _aniYazi(12, durumRenk)),
                    Flexible(
                      child: Text(durum,
                          style: _aniYazi(14, durumRenk,
                              weight: FontWeight.bold)),
                    ),
                    if (client.authorized && !client.disconnected)
                      Obx(
                        () => Text(
                          '   ' +
                              formatDurationToTime(
                                  Duration(seconds: _time.value)),
                          style: _aniYazi(13, _aniInk300),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Offstage(
            offstage: !client.authorized ||
                (client.type_() != ClientType.remote &&
                    client.type_() != ClientType.file &&
                    client.type_() != ClientType.camera),
            child: IconButton(
              onPressed: () => checkClickTime(client.id, () {
                if (client.type_() == ClientType.file) {
                  gFFI.chatModel.toggleCMFilePage();
                } else {
                  gFFI.chatModel
                      .toggleCMChatPage(MessageKey(client.peerId, client.id));
                }
              }),
              icon: SvgPicture.asset(
                  client.type_() == ClientType.file
                      ? 'assets/file_transfer.svg'
                      : 'assets/chat2.svg',
                  color: _aniAltin),
              splashRadius: kDesktopIconButtonSplashRadius,
            ),
          )
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  Widget _buildClientAvatar() {
    return buildAvatarWidget(
          avatar: client.avatar,
          size: 70,
          borderRadius: 15,
          fallback: _buildInitialAvatar(),
        ) ??
        _buildInitialAvatar();
  }

  Widget _buildInitialAvatar() {
    return Container(
      width: 70,
      height: 70,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(client.name),
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: Text(
        client.name.isNotEmpty ? client.name[0] : '?',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontSize: 55,
        ),
      ),
    );
  }
}

/// Salt-okunur izin ozeti: degerler gercek baglanti izinlerinden (client.*) okunur; baslaticidaki
/// Seceneklerle (motor ayari enable-*) birebir ayni. Duzenlenemez.
class _IzinOzeti extends StatelessWidget {
  final Client client;

  const _IzinOzeti({Key? key, required this.client}) : super(key: key);

  Widget _satir(IconData ikon, String ad, bool acik) {
    final Color renk = acik ? _aniOk : _aniInk300;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(ikon, size: 18, color: renk),
          SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$ad: ', style: _aniYazi(13, _aniInk100)),
                TextSpan(
                    text: acik ? 'açık' : 'kapalı',
                    style: _aniYazi(13, renk, weight: FontWeight.bold)),
              ]),
            ),
          ),
          Icon(acik ? Icons.check_circle_rounded : Icons.remove_circle_outline,
              size: 16, color: renk),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _aniDinle(context);
    final satirlar = client.type_() == ClientType.camera
        ? [
            _satir(Icons.volume_up_rounded, 'Ses', client.audio),
            _satir(Icons.videocam_rounded, 'Kayıt', client.recording),
          ]
        : [
            _satir(Icons.keyboard, 'Fare ve klavye', client.keyboard),
            _satir(Icons.upload_file_rounded, 'Dosya aktarımı', client.file),
            _satir(Icons.volume_up_rounded, 'Ses', client.audio),
            _satir(Icons.assignment_rounded, 'Pano', client.clipboard),
          ];
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(5.0, 2.0, 5.0, 8.0),
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        color: _aniYuzey,
        border: Border.all(color: _aniCizgi),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('İzinler',
              style: _aniYazi(14, _aniInk100, weight: FontWeight.bold)),
          SizedBox(height: 4),
          ...satirlar,
          SizedBox(height: 6),
          Text('İzinleri AniDesk penceresindeki Seçenekler\'den belirlediniz.',
              style: _aniYazi(11, _aniInk300)),
        ],
      ),
    );
  }
}

const double buttonBottomMargin = 8;

class _CmControlPanel extends StatelessWidget {
  final Client client;

  const _CmControlPanel({Key? key, required this.client}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return client.authorized
        ? client.disconnected
            ? buildDisconnected(context)
            : buildAuthorized(context)
        : buildUnAuthorized(context);
  }

  buildAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = !kAniDeskHideElevate &&
        canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Offstage(
          offstage: !client.inVoiceCall,
          child: Row(
            children: [
              Expanded(
                child: buildButton(context,
                    color: MyTheme.accent,
                    onClick: null, onTapDown: (details) async {
                  final devicesInfo =
                      await AudioInput.getDevicesInfo(true, true);
                  List<String> devices = devicesInfo['devices'] as List<String>;
                  if (devices.isEmpty) {
                    msgBox(
                      gFFI.sessionId,
                      'custom-nocancel-info',
                      'Prompt',
                      'no_audio_input_device_tip',
                      '',
                      gFFI.dialogManager,
                    );
                    return;
                  }

                  String currentDevice = devicesInfo['current'] as String;
                  final x = details.globalPosition.dx;
                  final y = details.globalPosition.dy;
                  final position = RelativeRect.fromLTRB(x, y, x, y);
                  showMenu(
                    context: context,
                    position: position,
                    items: devices
                        .map((d) => PopupMenuItem<String>(
                              value: d,
                              height: 18,
                              padding: EdgeInsets.zero,
                              onTap: () => AudioInput.setDevice(d, true, true),
                              child: IgnorePointer(
                                  child: RadioMenuButton(
                                value: d,
                                groupValue: currentDevice,
                                onChanged: (v) {
                                  if (v != null)
                                    AudioInput.setDevice(v, true, true);
                                },
                                child: Container(
                                  child: Text(
                                    d,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          kConnectionManagerWindowSizeClosedChat
                                                  .width -
                                              80),
                                ),
                              )),
                            ))
                        .toList(),
                  );
                },
                    icon: Icon(
                      Icons.call_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    text: "Ses girişi",
                    textColor: Colors.white),
              ),
              Expanded(
                child: buildButton(
                  context,
                  color: Colors.red,
                  onClick: () => closeVoiceCall(),
                  icon: Icon(
                    Icons.call_end_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  text: "Sesli aramayı bitir",
                  textColor: Colors.white,
                ),
              )
            ],
          ),
        ),
        Offstage(
          offstage: !client.incomingVoiceCall,
          child: Row(
            children: [
              Expanded(
                child: buildButton(context,
                    color: MyTheme.accent,
                    onClick: () => handleVoiceCall(true),
                    icon: Icon(
                      Icons.call_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    text: "Kabul et",
                    textColor: Colors.white),
              ),
              Expanded(
                child: buildButton(
                  context,
                  color: Colors.red,
                  onClick: () => handleVoiceCall(false),
                  icon: Icon(
                    Icons.phone_disabled_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  text: "Yoksay",
                  textColor: Colors.white,
                ),
              )
            ],
          ),
        ),
        Offstage(
          offstage: !client.fromSwitch,
          child: buildButton(context,
              color: Colors.purple,
              onClick: () => handleSwitchBack(context),
              icon: Icon(Icons.reply, color: Colors.white),
              text: "Tarafları değiştir",
              textColor: Colors.white),
        ),
        Offstage(
          offstage: !showElevation,
          child: buildButton(
            context,
            color: MyTheme.accent,
            onClick: () {
              handleElevate(context);
              windowManager.minimize();
            },
            icon: Icon(
              Icons.security_rounded,
              color: Colors.white,
              size: 14,
            ),
            text: 'Yetki yükselt',
            textColor: Colors.white,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: buildButton(context,
                  color: Colors.transparent,
                  border: Border.all(color: _aniAltin, width: 1.5),
                  onClick: handleDisconnect,
                  text: 'Bağlantıyı kes',
                  textColor: _aniAltin),
            ),
          ],
        )
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  buildDisconnected(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
            child: buildButton(context,
                color: MyTheme.accent,
                onClick: handleClose,
                text: 'Kapat',
                textColor: _aniPrimYazi)),
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  buildUnAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = !kAniDeskHideElevate &&
        canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote &&
        bind.mainGetBuildinOption(
                key: kOptionHideElevateButtonInAcceptWindow) !=
            'Y';
    final showAccept = model.approveMode != 'password';
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Offstage(
          offstage: !showElevation || !showAccept,
          child: buildButton(context, color: Colors.green[700], onClick: () {
            handleAccept(context);
            handleElevate(context);
            windowManager.minimize();
          },
              text: 'Kabul et ve yetki yükselt',
              icon: Icon(
                Icons.security_rounded,
                color: Colors.white,
                size: 14,
              ),
              textColor: Colors.white,
              tooltip: 'accept_and_elevate_btn_tooltip'),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showAccept)
              Expanded(
                child: Column(
                  children: [
                    buildButton(
                      context,
                      color: MyTheme.accent,
                      onClick: () {
                        handleAccept(context);
                        windowManager.minimize();
                      },
                      text: 'Bağlantıya izin ver',
                      textColor: _aniPrimYazi,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: buildButton(
                context,
                color: Colors.transparent,
                border: Border.all(color: _aniAltin, width: 1.5),
                onClick: handleDisconnect,
                text: 'Reddet',
                textColor: _aniAltin,
              ),
            ),
          ],
        ),
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  Widget buildButton(BuildContext context,
      {required Color? color,
      GestureTapCallback? onClick,
      Widget? icon,
      BoxBorder? border,
      required String text,
      required Color? textColor,
      String? tooltip,
      GestureTapDownCallback? onTapDown}) {
    assert(!(onClick == null && onTapDown == null));
    final bool dolgu = color == MyTheme.accent;
    final txtStyle =
        _aniYazi(15, textColor ?? _aniAltin, weight: FontWeight.bold);
    Widget textWidget;
    if (icon != null) {
      textWidget = Text(
        translate(text),
        style: txtStyle,
        textAlign: TextAlign.center,
      );
    } else {
      textWidget = Expanded(
        child: Text(
          translate(text),
          style: txtStyle,
          textAlign: TextAlign.center,
        ),
      );
    }
    final borderRadius = BorderRadius.circular(14.0);
    final btn = Container(
      height: 46,
      decoration: BoxDecoration(
          color: dolgu ? null : color,
          gradient: dolgu
              ? LinearGradient(colors: [_aniPrimUst, _aniPrimAlt])
              : null,
          borderRadius: borderRadius,
          border:
              dolgu ? Border.all(color: _aniPrimUst, width: 1.5) : border,
          boxShadow: dolgu
              ? [
                  BoxShadow(
                      color: _aniAltin.withOpacity(0.35),
                      blurRadius: 16,
                      offset: Offset(0, 4))
                ]
              : null),
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () {
          if (onClick == null) return;
          checkClickTime(client.id, onClick);
        },
        onTapDown: (details) {
          if (onTapDown == null) return;
          checkClickTime(client.id, () {
            onTapDown.call(details);
          });
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Offstage(offstage: icon == null, child: icon).marginOnly(right: 5),
            textWidget,
          ],
        ),
      ),
    );
    return (tooltip != null
            ? Tooltip(
                message: translate(tooltip),
                child: btn,
              )
            : btn)
        .marginAll(4);
  }

  void handleDisconnect() {
    bind.cmCloseConnection(connId: client.id);
  }

  void handleAccept(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.sendLoginResponse(client, true);
  }

  void handleElevate(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.setShowElevation(false);
    bind.cmElevatePortable(connId: client.id);
  }

  void handleClose() async {
    await bind.cmRemoveDisconnectedConnection(connId: client.id);
    if (await bind.cmGetClientsLength() == 0) {
      windowManager.close();
    }
  }

  void handleSwitchBack(BuildContext context) {
    bind.cmSwitchBack(connId: client.id);
  }

  void handleVoiceCall(bool accept) {
    bind.cmHandleIncomingVoiceCall(id: client.id, accept: accept);
  }

  void closeVoiceCall() {
    bind.cmCloseVoiceCall(id: client.id);
  }
}

void checkClickTime(int id, Function() callback) async {
  if (allowRemoteCMModification()) {
    callback();
    return;
  }
  var clickCallbackTime = DateTime.now().millisecondsSinceEpoch;
  await bind.cmCheckClickTime(connId: id);
  Timer(const Duration(milliseconds: 120), () async {
    var d = clickCallbackTime - await bind.cmGetClickTime();
    if (d > 120) callback();
  });
}

bool allowRemoteCMModification() {
  return option2bool(kOptionAllowRemoteCmModification,
      bind.mainGetLocalOption(key: kOptionAllowRemoteCmModification));
}

class _FileTransferLogPage extends StatefulWidget {
  _FileTransferLogPage({Key? key}) : super(key: key);

  @override
  State<_FileTransferLogPage> createState() => __FileTransferLogPageState();
}

class __FileTransferLogPageState extends State<_FileTransferLogPage> {
  @override
  Widget build(BuildContext context) {
    return statusList();
  }

  Widget generateCard(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.all(
          Radius.circular(15.0),
        ),
      ),
      child: child,
    );
  }

  iconLabel(CmFileLog item) {
    switch (item.action) {
      case CmFileAction.none:
        return Container();
      case CmFileAction.localToRemote:
      case CmFileAction.remoteToLocal:
        return Column(
          children: [
            Transform.rotate(
              angle: item.action == CmFileAction.remoteToLocal ? 0 : pi,
              child: SvgPicture.asset(
                "assets/arrow.svg",
                colorFilter: svgColor(Theme.of(context).tabBarTheme.labelColor),
              ),
            ),
            Text(item.action == CmFileAction.remoteToLocal
                ? translate('Send')
                : translate('Receive'))
          ],
        );
      case CmFileAction.remove:
        return Column(
          children: [
            Icon(
              Icons.delete,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Delete'))
          ],
        );
      case CmFileAction.createDir:
        return Column(
          children: [
            Icon(
              Icons.create_new_folder,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Create Folder'))
          ],
        );
      case CmFileAction.rename:
        return Column(
          children: [
            Icon(
              Icons.drive_file_move_outlined,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Rename'))
          ],
        );
    }
  }

  Widget statusList() {
    return PreferredSize(
      preferredSize: const Size(200, double.infinity),
      child: Container(
          padding: const EdgeInsets.all(12.0),
          child: Obx(
            () {
              final jobTable = gFFI.cmFileModel.currentJobTable;
              statusListView(List<CmFileLog> jobs) => ListView.builder(
                    controller: ScrollController(),
                    itemBuilder: (BuildContext context, int index) {
                      final item = jobs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: generateCard(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: iconLabel(item),
                                  ).paddingOnly(left: 15),
                                  const SizedBox(
                                    width: 16.0,
                                  ),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.fileName,
                                        ).paddingSymmetric(vertical: 10),
                                        if (item.totalSize > 0)
                                          Text(
                                            '${translate("Total")} ${readableFileSize(item.totalSize.toDouble())}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: MyTheme.darkGray,
                                            ),
                                          ),
                                        if (item.totalSize > 0)
                                          Offstage(
                                            offstage: item.state !=
                                                JobState.inProgress,
                                            child: Text(
                                              '${translate("Speed")} ${readableFileSize(item.speed)}/s',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: MyTheme.darkGray,
                                              ),
                                            ),
                                          ),
                                        Offstage(
                                          offstage: !(item.isTransfer() &&
                                              item.state !=
                                                  JobState.inProgress),
                                          child: Text(
                                            translate(
                                              item.display(),
                                            ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: MyTheme.darkGray,
                                            ),
                                          ),
                                        ),
                                        if (item.totalSize > 0)
                                          Offstage(
                                            offstage: item.state !=
                                                JobState.inProgress,
                                            child: LinearPercentIndicator(
                                              padding:
                                                  EdgeInsets.only(right: 15),
                                              animateFromLastPercent: true,
                                              center: Text(
                                                '${(item.finishedSize / item.totalSize * 100).toStringAsFixed(0)}%',
                                              ),
                                              barRadius: Radius.circular(15),
                                              percent: item.finishedSize /
                                                  item.totalSize,
                                              progressColor: MyTheme.accent,
                                              backgroundColor:
                                                  Theme.of(context).hoverColor,
                                              lineHeight:
                                                  kDesktopFileTransferRowHeight,
                                            ).paddingSymmetric(vertical: 15),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [],
                                  ),
                                ],
                              ),
                            ],
                          ).paddingSymmetric(vertical: 10),
                        ),
                      );
                    },
                    itemCount: jobTable.length,
                  );

              return jobTable.isEmpty
                  ? generateCard(
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              "assets/transfer.svg",
                              colorFilter: svgColor(
                                  Theme.of(context).tabBarTheme.labelColor),
                              height: 40,
                            ).paddingOnly(bottom: 10),
                            Text(
                              translate("No transfers in progress"),
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.linear(1.20),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).tabBarTheme.labelColor),
                            ),
                          ],
                        ),
                      ),
                    )
                  : statusListView(jobTable);
            },
          )),
    );
  }
}
