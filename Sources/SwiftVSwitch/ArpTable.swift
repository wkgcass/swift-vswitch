import Collections
import SwiftEventLoopCommon
import VProxyCommon

public class ArpTable: CustomStringConvertible {
    private let loop: SelectorEventLoop
    private var params: VSwitchParams

    public init(loop: SelectorEventLoop, params: VSwitchParams) {
        self.loop = loop
        self.params = params
    }

    public private(set) var entries = Set<ArpEntry>()
    private var ip4Map = [IPv4Dev: ArpEntry]()
    private var ip6Map = [IPv6Dev: ArpEntry]()
    private var macMap = [MacDev: Set<ArpEntry>]()

    private struct IPv4Dev: Hashable {
        let ip: IPv4
        let dev: IfaceHandle
    }

    private struct IPv6Dev: Hashable {
        let ip: IPv6
        let dev: IfaceHandle
    }

    private struct MacDev: Hashable {
        let mac: MacAddress
        let dev: IfaceHandle
    }

    public func record(mac: MacAddress, ip: any IP, dev: IfaceEx) {
        record(mac: mac, ip: ip, dev: dev, persist: false)
    }

    public func record(mac: MacAddress, ip: any IP, dev: IfaceEx, persist: Bool) {
        let entry: ArpEntry?
        if let v4 = ip as? IPv4 {
            entry = ip4Map[IPv4Dev(ip: v4, dev: dev.handle())]
        } else if let v6 = ip as? IPv6 {
            entry = ip6Map[IPv6Dev(ip: v6, dev: dev.handle())]
        } else {
            entry = nil
        }

        if let entry, entry.mac == mac {
            if persist {
                if entry.timeoutMillis == -1 {
                    return
                } else {
                    entry.cancel()
                }
            } else {
                entry.resetTimer()
                return
            }
        }

        // otherwise need to overwrite the entry
        let entryNew = ArpEntry(parent: self, mac: mac, ip: ip, dev: dev, persist: persist)
        entryNew.record()
    }

    public func lookup(ip: any IP, dev: IfaceEx) -> MacAddress? {
        if let v4 = ip as? IPv4 {
            return ip4Map[IPv4Dev(ip: v4, dev: dev.handle())]?.mac
        } else if let v6 = ip as? IPv6 {
            return ip6Map[IPv6Dev(ip: v6, dev: dev.handle())]?.mac
        } else {
            return nil
        }
    }

    public func lookupByMac(mac: MacAddress, dev: IfaceEx) -> Set<ArpEntry>? {
        return macMap[MacDev(mac: mac, dev: dev.handle())]
    }

    public func setTimeout(_ timeout: Int) {
        params.arpTableTimeoutMillis = timeout
        loop.runOnLoop {
            for entry in self.entries {
                entry.setTimeout(millis: timeout)
            }
        }
    }

    public func clearCache() {
        let entriesToClear = Set(entries)
        for entry in entriesToClear {
            entry.cancel()
        }
    }

    public func remove(mac: MacAddress, dev: IfaceEx) {
        if let entries = macMap[MacDev(mac: mac, dev: dev.handle())] {
            for entry in entries {
                entry.cancel()
            }
        }
    }

    public func release() {
        clearCache()
    }

    public var description: String {
        return "ArpTable{\(entries)}"
    }

    public class ArpEntry: Timer, Hashable, CustomStringConvertible {
        let parent: ArpTable
        public let mac: MacAddress
        public let ip: any IP
        public let dev: IfaceEx

        init(parent: ArpTable, mac: MacAddress, ip: any IP, dev: IfaceEx, persist: Bool) {
            self.parent = parent
            self.mac = mac
            self.ip = ip
            self.dev = dev
            super.init(loop: parent.loop, timeoutMillis: persist ? -1 : parent.params.arpTableTimeoutMillis)
        }

        func record() {
            if let v4 = ip as? IPv4 {
                let entry = parent.ip4Map[IPv4Dev(ip: v4, dev: dev.handle())]
                if let entry {
                    entry.cancel()
                }
                parent.ip4Map[IPv4Dev(ip: v4, dev: dev.handle())] = self
            } else {
                let v6 = ip as! IPv6
                let key = IPv6Dev(ip: v6, dev: dev.handle())
                let entry = parent.ip6Map[key]
                if let entry {
                    entry.cancel()
                }
                parent.ip6Map[key] = self
            }
            parent.entries.insert(self)
            let key = MacDev(mac: mac, dev: dev.handle())
            if !parent.macMap.keys.contains(key) {
                parent.macMap[key] = Set()
            }
            parent.macMap[MacDev(mac: mac, dev: dev.handle())]!.insert(self)
            resetTimer()

            Logger.trace(LogType.ALERT, "arp entry \(mac) -> \(ip) recorded")
        }

        override public func cancel() {
            super.cancel()

            Logger.trace(LogType.ALERT, "arp entry \(mac) -> \(ip) removed")

            parent.entries.remove(self)
            if let v4 = ip as? IPv4 {
                parent.ip4Map.removeValue(forKey: IPv4Dev(ip: v4, dev: dev.handle()))
            } else {
                let v6 = ip as! IPv6
                parent.ip6Map.removeValue(forKey: IPv6Dev(ip: v6, dev: dev.handle()))
            }
            let key = MacDev(mac: mac, dev: dev.handle())
            if parent.macMap[key] != nil {
                parent.macMap[key]!.remove(self)
                if parent.macMap[key]!.isEmpty {
                    parent.macMap.removeValue(forKey: key)
                }
            }
        }

        override public func resetTimer() {
            if timeoutMillis == -1 {
                return
            }
            super.resetTimer()
        }

        public var description: String {
            return "ArpEntry{mac=\(mac), ip=\(ip)}"
        }

        public func hash(into hasher: inout Hasher) {
            ObjectIdentifier(self).hash(into: &hasher)
        }

        public static func == (lhs: ArpEntry, lhr: ArpEntry) -> Bool {
            return lhs === lhr
        }
    }
}
