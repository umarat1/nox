package com.lumen.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import com.lumen.core.noxcore.Noxcore
import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet4Address
import java.net.NetworkInterface

/** Default (physical) network for sing-box's interface monitor, and the system DNS server. */
object NetMonitor {
    @Volatile private var started = false
    private var last = ""

    fun start(ctx: Context) = synchronized(this) {
        if (started) return
        started = true
        val cm = ctx.getSystemService(ConnectivityManager::class.java)
        cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = push(cm, network)
            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) = push(cm, network)
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = push(cm, network)
            override fun onLost(network: Network) {
                if (cm.activeNetwork == null) {
                    last = ""
                    Noxcore.defaultInterfaceChanged("", -1, false)
                }
            }
        })
    }

    private fun push(cm: ConnectivityManager, n: Network) {
        val caps = cm.getNetworkCapabilities(n)
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) return
        val lp = cm.getLinkProperties(n) ?: return
        val name = lp.interfaceName ?: return
        val idx = try { NetworkInterface.getByName(name)?.index } catch (_: Exception) { null } ?: return
        lp.dnsServers.firstOrNull { it is Inet4Address }?.hostAddress?.let { Noxcore.setDNS(it) }
        val metered = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
        val key = "$name/$idx/$metered"
        if (key == last) return
        last = key
        Noxcore.defaultInterfaceChanged(name, idx, metered)
    }

    fun interfaces(ctx: Context): String {
        val out = JSONArray()
        val list = NetworkInterface.getNetworkInterfaces() ?: return "[]"
        for (ni in list) {
            val addrs = JSONArray()
            for (ia in ni.interfaceAddresses) {
                val h = ia.address.hostAddress?.substringBefore('%') ?: continue
                addrs.put("$h/${ia.networkPrefixLength}")
            }
            var flags = 0
            try {
                if (ni.isUp) flags = flags or 0x1 or 0x40
                if (ni.isLoopback) flags = flags or 0x8
                if (ni.isPointToPoint) flags = flags or 0x10
                if (ni.supportsMulticast()) flags = flags or 0x1000
            } catch (_: Exception) {}
            val n = ni.name
            val type = when {
                n.startsWith("wlan") -> 0
                n.startsWith("rmnet") || n.startsWith("ccmni") -> 1
                n.startsWith("eth") -> 2
                else -> 3
            }
            out.put(JSONObject().put("name", n).put("index", ni.index).put("mtu", try { ni.mtu } catch (_: Exception) { 1500 })
                .put("flags", flags).put("type", type).put("addrs", addrs).put("dns", JSONArray()).put("metered", type == 1))
        }
        return out.toString()
    }
}
