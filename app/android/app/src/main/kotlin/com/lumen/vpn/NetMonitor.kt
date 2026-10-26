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
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

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
                val under = underlying(cm)
                bindProcess(cm, under)
                if (under == null) {
                    last = ""
                    Noxcore.defaultInterfaceChanged("", -1, false)
                    Noxcore.underlyingNetworkChanged("")
                } else {
                    push(cm, under)
                }
            }
        })
    }

    /** Non-VPN network that has internet, or null. */
    fun underlying(cm: ConnectivityManager): Network? =
        cm.allNetworks.firstOrNull { n ->
            val caps = cm.getNetworkCapabilities(n) ?: return@firstOrNull false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }

    private fun bindProcess(cm: ConnectivityManager, n: Network?) {
        try { cm.bindProcessToNetwork(n) } catch (_: Exception) {}
    }

    /** Pin one socket to the current physical network. Reflection: FileDescriptor has no public ctor for an existing int. */
    fun bindSocket(ctx: Context, fd: Int) {
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return
        val n = underlying(cm) ?: return
        try {
            val f = java.io.FileDescriptor()
            val field = java.io.FileDescriptor::class.java.getDeclaredField("descriptor")
            field.isAccessible = true
            field.setInt(f, fd)
            n.bindSocket(f)
        } catch (_: Exception) {}
    }

    private fun push(cm: ConnectivityManager, n: Network) {
        bindProcess(cm, underlying(cm))
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
        Noxcore.underlyingNetworkChanged(name)
    }

    /** System resolver on a physical network. Empty when it does not answer in time. */
    fun resolve(ctx: Context, host: String): String {
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return ""
        val nets = cm.allNetworks.toList().sortedBy { n ->
            val caps = cm.getNetworkCapabilities(n)
            if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) 1 else 0
        }
        val got = AtomicReference("")
        val done = CountDownLatch(1)
        Thread {
            try {
                for (n in nets) {
                    val caps = cm.getNetworkCapabilities(n) ?: continue
                    if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
                    try {
                        val ips = n.getAllByName(host).mapNotNull { a: InetAddress ->
                            a.hostAddress?.substringBefore('%')
                        }
                        if (ips.isNotEmpty()) {
                            got.set(ips.joinToString(","))
                            break
                        }
                    } catch (_: Exception) {
                    }
                }
            } finally {
                done.countDown()
            }
        }.start()
        done.await(2, TimeUnit.SECONDS)
        return got.get()
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
