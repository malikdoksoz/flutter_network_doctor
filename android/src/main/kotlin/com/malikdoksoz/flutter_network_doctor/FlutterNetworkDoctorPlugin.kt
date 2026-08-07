package com.malikdoksoz.flutter_network_doctor

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.Inet6Address

/** Provides native Android network characteristics without requesting permissions. */
class FlutterNetworkDoctorPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "flutter_network_doctor/native")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getNetworkSnapshot" -> result.success(networkSnapshot())
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun networkSnapshot(): Map<String, Any?> {
        val manager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)
            as ConnectivityManager
        val network = if (Build.VERSION.SDK_INT >= 23) manager.activeNetwork else null
        val capabilities = network?.let(manager::getNetworkCapabilities)
        val link = network?.let(manager::getLinkProperties)
        val metered = manager.isActiveNetworkMetered

        return mapOf(
            "dnsServers" to (link?.dnsServers?.map { it.hostAddress ?: it.toString() }
                ?: emptyList<String>()),
            "routes" to (link?.routes?.map { it.toString() } ?: emptyList<String>()),
            "interfaceName" to link?.interfaceName,
            "mtu" to link?.mtu,
            "proxy" to link?.httpProxy?.toString(),
            "privateDnsServerName" to if (Build.VERSION.SDK_INT >= 28) {
                link?.privateDnsServerName
            } else {
                null
            },
            "isMetered" to metered,
            "isExpensive" to metered,
            "isConstrained" to if (Build.VERSION.SDK_INT >= 24) {
                manager.restrictBackgroundStatus ==
                    ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
            } else {
                null
            },
            "isValidated" to capabilities?.hasCapability(
                NetworkCapabilities.NET_CAPABILITY_VALIDATED,
            ),
            "captivePortalDetected" to capabilities?.hasCapability(
                NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL,
            ),
            "supportsIpv4" to link?.linkAddresses?.any { it.address is Inet4Address },
            "supportsIpv6" to link?.linkAddresses?.any { it.address is Inet6Address },
            "supportsDns" to link?.dnsServers?.isNotEmpty(),
            "localNetworkPermission" to localNetworkPermissionStatus(),
        )
    }

    private fun localNetworkPermissionStatus(): String {
        val targetSdk = applicationContext.applicationInfo.targetSdkVersion
        if (Build.VERSION.SDK_INT < 37 || targetSdk < 37) {
            return "notRequired"
        }

        val permission = "android.permission.ACCESS_LOCAL_NETWORK"
        return if (applicationContext.checkSelfPermission(permission) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            "granted"
        } else {
            "denied"
        }
    }
}
