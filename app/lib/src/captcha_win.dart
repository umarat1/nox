import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// Root navigator (main.dart) so the engine-driven captcha can open a dialog anywhere.
final noxNav = GlobalKey<NavigatorState>();

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

// Same interceptor as Android CaptchaActivity: success_token from captchaNotRobot.check replies.
const _intercept = r'''
(function() {
  if (window.__nox_cap) return; window.__nox_cap = true;
  function send(o) { try { window.chrome.webview.postMessage(JSON.stringify(o)); } catch (e) {} }
  function pick(d) {
    try {
      if (d && d.response && d.response.success_token) send({ok: d.response.success_token});
      else if (d && d.error) send({err: JSON.stringify(d.error)});
    } catch (e) {}
  }
  var of = window.fetch;
  if (of) window.fetch = function() {
    var u = arguments[0]; u = (u && u.url) ? u.url : String(u || '');
    var p = of.apply(this, arguments);
    if (u.indexOf('captchaNotRobot.check') >= 0) p.then(function(r) { r.clone().json().then(pick, function(){}); }, function(){});
    return p;
  };
  var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m, u) { this.__nox_u = String(u || ''); return oo.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function() {
    var x = this;
    if (x.__nox_u && x.__nox_u.indexOf('captchaNotRobot.check') >= 0)
      x.addEventListener('load', function() { try { pick(JSON.parse(x.responseText)); } catch (e) {} });
    return os.apply(this, arguments);
  };
})();
''';

/// Windows: VK «я не робот» page in WebView2; returns success_token or "error:…".
Future<String> solveCaptchaWindows(String url) async {
  final ctx = noxNav.currentContext;
  if (ctx == null) return 'error:no-window';
  if (await WebviewController.getWebViewVersion() == null)
    return 'error:webview2-missing';
  final wc = WebviewController();
  try {
    await wc.initialize();
    await wc.setUserAgent(_ua);
    await wc.addScriptToExecuteOnDocumentCreated(_intercept);
  } catch (_) {
    return 'error:webview';
  }
  String? result;
  StreamSubscription? sub;
  final done = Completer<void>();
  sub = wc.webMessage.listen((m) {
    try {
      final o = (m is String ? jsonDecode(m) : m) as Map;
      result = o['ok'] != null ? '${o['ok']}' : 'error:${o['err']}';
    } catch (_) {
      return;
    }
    if (!done.isCompleted) done.complete();
  });
  await wc.loadUrl(url);
  if (!ctx.mounted) return 'error:no-window';
  final dlg = showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (d) {
      done.future.then((_) {
        if (Navigator.of(d).canPop()) Navigator.of(d).pop();
      });
      return Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: 460,
          height: 640,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Проверка VK «я не робот»',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(d).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(child: Webview(wc)),
            ],
          ),
        ),
      );
    },
  );
  await dlg;
  await sub.cancel();
  await wc.dispose();
  return result ?? 'error:cancelled';
}
