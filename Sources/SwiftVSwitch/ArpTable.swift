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
    private var ip4Map = [IPv4: ArpEntry]()
    private var ip6Map = [IPv6: ArpEntry]()
    private var macMap = [MacAddress: Set<ArpEntry>]()

    public func record(mac: MacAddress, ip: any IP) {
        record(mac: mac, ip: ip, persist: false)
    }

    public func record(mac: MacAddress, ip: any IP, persist: Bool) {
        let entry: ArpEntry?
        if let v4 = ip as? IPv4 {
            entry = ip4Map[v4]
        } else if let v6 = ip as? IPv6 {
            entry = ip6Map[v6]
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
        let entryNew = ArpEntry(parent: self, mac: mac, ip: ip, persist: persist)
        entryNew.record()
    }

    public func lookup(ip: any IP) -> MacAddress? {
        if let v4 = ip as? IPv4 {
            return ip4Map[v4]?.mac
        } else if let v6 = ip as? IPv6 {
            return ip6Map[v6]?.mac
        } else {
            return nil
        }
    }

    public func lookupByMac(mac: MacAddress) -> Set<ArpEntry>? {
        return macMap[mac]
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

    public func remove(mac: MacAddress) {
        if let entries = macMap[mac] {
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
        let mac: MacAddress
        let ip: any IP

        init(parent: ArpTable, mac: MacAddress, ip: any IP, persist: Bool) {
            self.parent = parent
            self.mac = mac
            self.ip = ip
            super.init(loop: parent.loop, timeoutMillis: persist ? -1 : parent.params.arpTableTimeoutMillis)
        }

        func record() {
            if let v4 = ip as? IPv4 {
                let entry = parent.ip4Map[v4]
                if let entry {
                    entry.cancel()
                }
                parent.ip4Map[v4] = self
            } else {
                let v6 = ip as! IPv6
                let entry = parent.ip6Map[v6]
                if let entry {
                    entry.cancel()
                }
                parent.ip6Map[v6] = self
            }
            parent.entries.insert(self)
            if !parent.macMap.keys.contains(mac) {
                parent.macMap[mac] = Set()
            }
            parent.macMap[mac]!.insert(self)
            resetTimer()

            Logger.trace(LogType.ALERT, "arp entry \(mac) -> \(ip) recorded")
        }

        override public func cancel() {
            super.cancel()

            Logger.trace(LogType.ALERT, "arp entry \(mac) -> \(ip) removed")

            parent.entries.remove(self)
            if let v4 = ip as? IPv4 {
                parent.ip4Map.removeValue(forKey: v4)
            } else {
                let v6 = ip as! IPv6
                parent.ip6Map.removeValue(forKey: v6)
            }
            if parent.macMap[mac] != nil {
                parent.macMap[mac]!.remove(self)
                if parent.macMap[mac]!.isEmpty {
                    parent.macMap.removeValue(forKey: mac)
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
