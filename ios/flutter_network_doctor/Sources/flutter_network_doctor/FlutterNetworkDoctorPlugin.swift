import Flutter
import Network
import UIKit

public class FlutterNetworkDoctorPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_network_doctor/native",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(FlutterNetworkDoctorPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "getNetworkSnapshot" else {
      result(FlutterMethodNotImplemented)
      return
    }
    collectSnapshot(result: result)
  }

  private func collectSnapshot(result: @escaping FlutterResult) {
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "flutter_network_doctor.path")
    var completed = false

    monitor.pathUpdateHandler = { path in
      guard !completed else { return }
      completed = true
      monitor.cancel()
      let snapshot = self.snapshot(from: path)
      DispatchQueue.main.async { result(snapshot) }
    }
    monitor.start(queue: queue)

    queue.asyncAfter(deadline: .now() + 3) {
      guard !completed else { return }
      completed = true
      monitor.cancel()
      DispatchQueue.main.async {
        result(FlutterError(
          code: "path_timeout",
          message: "Timed out while reading the active network path.",
          details: nil
        ))
      }
    }
  }

  private func snapshot(from path: NWPath) -> [String: Any] {
    var value: [String: Any] = [
      "dnsServers": [],
      "routes": [],
      "isExpensive": path.isExpensive,
      "isConstrained": path.isConstrained,
      "pathStatus": pathStatusName(path.status),
      "localNetworkPermission": "unsupported"
    ]
    if path.status == .satisfied {
      value["supportsIpv4"] = path.supportsIPv4
      value["supportsIpv6"] = path.supportsIPv6
      value["supportsDns"] = path.supportsDNS
    }
    if let interface = path.availableInterfaces.first(where: {
      path.usesInterfaceType($0.type)
    }) {
      value["interfaceName"] = interface.name
    }
    return value
  }

  private func pathStatusName(_ status: NWPath.Status) -> String {
    switch status {
    case .satisfied:
      return "satisfied"
    case .unsatisfied:
      return "unsatisfied"
    case .requiresConnection:
      return "requiresConnection"
    @unknown default:
      return "unknown"
    }
  }
}
