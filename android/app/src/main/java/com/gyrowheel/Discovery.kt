package com.gyrowheel

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.mutableStateOf

/**
 * Browses for `_gyrowheel._udp` services advertised by the Mac receivers (Android twin
 * of the iOS Discovery / NWBrowser). Holds a Wi-Fi multicast lock while active so mDNS
 * actually reaches us on most networks.
 */
class Discovery(context: Context) {
    companion object {
        const val SERVICE_TYPE = "_gyrowheel._udp."
    }

    private val appContext = context.applicationContext
    private val nsd = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val main = Handler(Looper.getMainLooper())

    val macs = mutableStateOf<List<DiscoveredMac>>(emptyList())

    private var multicastLock: WifiManager.MulticastLock? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private val found = LinkedHashMap<String, DiscoveredMac>()

    fun start() {
        if (discoveryListener != null) return
        multicastLock = wifi.createMulticastLock("gyrowheel.nsd").apply {
            setReferenceCounted(true)
            runCatching { acquire() }
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onServiceFound(service: NsdServiceInfo) {
                resolve(service)
            }

            override fun onServiceLost(service: NsdServiceInfo) {
                synchronized(found) { found.remove(service.serviceName) }
                publish()
            }
        }
        discoveryListener = listener
        runCatching {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        }
    }

    private fun resolve(service: NsdServiceInfo) {
        nsd.resolveService(service, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                val host = serviceInfo.host?.hostAddress ?: return
                val mac = DiscoveredMac(serviceInfo.serviceName, host, serviceInfo.port)
                synchronized(found) { found[serviceInfo.serviceName] = mac }
                publish()
            }
        })
    }

    private fun publish() {
        val list = synchronized(found) { found.values.sortedBy { it.name } }
        main.post { macs.value = list }
    }

    fun stop() {
        discoveryListener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        discoveryListener = null
        multicastLock?.let { if (it.isHeld) runCatching { it.release() } }
        multicastLock = null
        synchronized(found) { found.clear() }
        main.post { macs.value = emptyList() }
    }
}
