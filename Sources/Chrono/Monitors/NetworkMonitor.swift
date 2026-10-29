import Darwin
import Foundation
import SystemConfiguration

struct NetworkSample {
    var upRate: Double = 0      // bytes/sec
    var downRate: Double = 0    // bytes/sec
    var totalSent: UInt64 = 0
    var totalReceived: UInt64 = 0
    var interface: String?
    var address: String?
}

final class NetworkMonitor {
    private var previous: (sent: UInt64, received: UInt64, time: Double)?
    private let store = SCDynamicStoreCreate(nil, "Chrono" as CFString, nil, nil)
    private var route: (interface: String?, address: String?, at: Double) = (nil, nil, -.infinity)

    func sample() -> NetworkSample {
        let (sent, received) = counters()
        let now = ProcessInfo.processInfo.systemUptime
        var sample = NetworkSample(totalSent: sent, totalReceived: received)
        if let previous, now > previous.time {
            let dt = now - previous.time
            // Counters can reset (e.g. an interface goes away), so never report negative rates.
            sample.upRate = sent >= previous.sent ? Double(sent - previous.sent) / dt : 0
            sample.downRate = received >= previous.received ? Double(received - previous.received) / dt : 0
        }
        previous = (sent, received, now)

        // The primary route rarely changes; re-resolve it every 5s rather than every tick.
        if now - route.at > 5 {
            isPhysical.removeAll()  // interface indexes are reused when interfaces come and go
            let interface = primaryInterface()
            route = (interface, interface.flatMap(Self.ipv4Address), now)
        }
        sample.interface = route.interface
        sample.address = route.address
        return sample
    }

    private var isPhysical: [UInt16: Bool] = [:]

    /// Sums 64-bit byte counters across physical (en*) interfaces.
    private func counters() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var sent: UInt64 = 0, received: UInt64 = 0
        var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.load(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if physical(msg.ifm_index, &nameBuf) {
                        sent += msg.ifm_data.ifi_obytes
                        received += msg.ifm_data.ifi_ibytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (sent, received)
    }

    private func physical(_ index: UInt16, _ nameBuf: inout [CChar]) -> Bool {
        if let known = isPhysical[index] { return known }
        let result = if_indextoname(UInt32(index), &nameBuf) != nil && String(cString: nameBuf).hasPrefix("en")
        isPhysical[index] = result
        return result
    }

    private func primaryInterface() -> String? {
        guard let store,
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return dict["PrimaryInterface"] as? String
    }

    private static func ipv4Address(for interface: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var cursor = head
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.pointee.ifa_name) == interface else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
