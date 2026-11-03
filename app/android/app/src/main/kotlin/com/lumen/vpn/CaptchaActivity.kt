package com.lumen.vpn

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * VK "I'm not a robot" check for qWDTT servers. Loads VK's captcha page and watches its
 * captchaNotRobot.check reply for success_token, which goes back to the engine (and on to
 * qWDTT's stdin). The page talks to VK directly: Nox is outside its own VPN.
 */
class CaptchaActivity : Activity() {
    private var done = false
    private lateinit var web: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra("url")
        if (url == null || !url.startsWith("https://")) { finishWith("error:bad-url"); return }
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.parseColor("#0E1116")) }
        val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(32, 16, 16, 16) }
        bar.addView(TextView(this).apply {
            text = "Проверка VK для qWDTT"; setTextColor(Color.WHITE); textSize = 16f
        }, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        bar.addView(Button(this).apply { text = "Отмена"; setOnClickListener { finishWith("error:cancelled") } })
        root.addView(bar, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        web = WebView(this)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
            userAgentString = DESKTOP_UA
        }
        web.addJavascriptInterface(object {
            @JavascriptInterface fun onSuccess(token: String) = runOnUiThread { finishWith(token) }
            @JavascriptInterface fun onError(err: String) = runOnUiThread { finishWith("error:vk") }
        }, "WdttCaptcha")
        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, u: String?, favicon: android.graphics.Bitmap?) {
                view?.evaluateJavascript(INTERCEPT, null)
            }
            override fun onPageFinished(view: WebView?, u: String?) {
                view?.evaluateJavascript(INTERCEPT, null)
            }
        }
        web.webChromeClient = WebChromeClient()
        root.addView(web, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        setContentView(root)
        web.loadUrl(url)
        web.requestFocus()
    }

    private fun finishWith(r: String) {
        if (done) return
        done = true
        setResult(RESULT_OK, Intent().putExtra("r", r))
        finish()
    }

    @Deprecated("plain Activity")
    override fun onBackPressed() {
        if (::web.isInitialized && web.canGoBack()) web.goBack() else finishWith("error:cancelled")
    }

    override fun onDestroy() {
        if (::web.isInitialized) web.destroy()
        super.onDestroy()
    }

    companion object {
        const val DESKTOP_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
        // Same interceptor as qWDTT's own Android client: fetch + XHR replies of captchaNotRobot.check.
        val INTERCEPT = """
            (function() {
              if (window.__nox_cap) return; window.__nox_cap = true;
              function pick(d) {
                try {
                  if (d && d.response && d.response.success_token) window.WdttCaptcha.onSuccess(d.response.success_token);
                  else if (d && d.error) window.WdttCaptcha.onError(JSON.stringify(d.error));
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
        """.trimIndent()
    }
}
