import Collections
import SwiftEventLoopCommon
import VProxyCommon

public class MacTable: CustomStringConvertible {
    private let loop: SelectorEventLoop
    private var params: VSwitchParams

    public init(loop: SelectorEventLoop, params: VSwitchParams) {
        self.loop = loop
        self.params = params
    }

    private var entries = Set<MacEntry>()
    private var macMap = [MacAddress: MacEntry]()
    private var ifaceMap = [IfaceHandle: Set<MacEntry>]()

    public func record(mac: MacAddress, iface: IfaceEx) {
        record(mac: mac, iface: iface, persist: false)
    }

    public func record(mac: MacAddress, iface: IfaceEx, persist: Bool) {
        let entry = macMap[mac]
        if let entry, entry.iface.handle() == iface.handle() {
            if persist {
                if entry.timeoutMillis == -1 {
                    return
                } else {
                    entry.cancel(isTimeout: false)
                }
            } else {
                entry.resetTimer()
                return
            }
        }
        // otherwise need to overwrite the entry
        let e = MacEntry(parent: self, mac: mac, iface: iface, persist: persist)
        e.record()
    }

    public func disconnect(iface: IfaceEx) {
        guard var set = ifaceMap[iface.handle()] else {
            return
        }
        set = Set(set)
        for entry in set {
            entry.cancel(isTimeout: false)
        }
    }

    public func lookup(mac: MacAddress) -> (IfaceEx)? {
        return macMap[mac]?.iface
    }

    public func clearCache() {
        let entriesCopy = Set(entries)
        for entry in entriesCopy {
            entry.cancel(isTimeout: false)
        }
    }

    public func listEntries() -> Set<MacEntry> {
        return entries
    }

    public func setTimeout(timeoutMillis: Int) {
        params.macTableTimeoutMillis = timeoutMillis
        loop.runOnLoop {
            for entry in self.entries {
                entry.setTimeout(millis: timeoutMillis)
            }
        }
    }

    public func remove(mac: MacAddress) {
        guard let entry = macMap[mac] else {
            return
        }
        entry.cancel(isTimeout: false)
    }

    public func remove(iface: IfaceEx) {
        guard let set = ifaceMap[iface.handle()] else {
            return
        }
        for s in set {
            s.cancel(isTimeout: false)
        }
    }

    public func release() {
        clearCache()
    }

    public var description: String {
        return "MacTable{\(entries)}"
    }

    public class MacEntry: Timer, Equatable, Hashable, CustomStringConvertible {
        let parent: MacTable
        let mac: MacAddress
        let iface: IfaceEx
        private var offloaded = false
        private var offloadedCount = 0

        init(parent: MacTable, mac: MacAddress, iface: IfaceEx, persist: Bool) {
            self.parent = parent
            self.mac = mac
            self.iface = iface
            super.init(loop: parent.loop, timeoutMillis: persist ? -1 : parent.params.macTableTimeoutMillis)
        }

        func record() {
            if let entry = parent.macMap[mac] {
                // the mac is already registered on another iface
                // remove that iface
                entry.cancel(isTimeout: false)
            }
            parent.entries.insert(self)
            parent.macMap[mac] = self
            if parent.ifaceMap.keys.contains(iface.handle()) {
                parent.ifaceMap[iface.handle()]!.insert(self)
            } else {
                parent.ifaceMap[iface.handle()] = Set<MacEntry>()
            }
            resetTimer()
            tryOffload()
            Logger.trace(.ALERT, "mac entry \(iface.name) -> \(mac) recorded")
        }

        private func tryOffload() {
            // TODO: implement xdp offload
        }

        override public func cancel() {
            cancel(isTimeout: true)
        }

        func cancel(isTimeout: Bool) {
            super.cancel()

            if isTimeout && offloaded {
                if hasOffloadedPacketPassed() {
                    start()
                    return
                }
            }

            Logger.trace(.ALERT, "mac entry \(iface.name) -> \(mac) removed")

            parent.entries.remove(self)
            parent.macMap.removeValue(forKey: mac)
            if parent.ifaceMap.keys.contains(iface.handle()) {
                parent.ifaceMap[iface.handle()]!.remove(self)
                if parent.ifaceMap[iface.handle()]!.isEmpty {
                    parent.ifaceMap.removeValue(forKey: iface.handle())
                }
            }

            clearOffload()
        }

        private func hasOffloadedPacketPassed() -> Bool {
            // TODO: implement xdp offload
            return false
        }

        private func clearOffload() {
            // TODO: implement xdp offload
        }

        override public func resetTimer() {
            if timeoutMillis == -1 {
                return
            }
            _ = hasOffloadedPacketPassed() // will update offloadedCount field
            super.resetTimer()
        }

        func isOffloaded() -> Bool {
            return offloaded
        }

        func getOffloadedCount() -> Int {
            return offloadedCount
        }

        public var description: String {
            if offloaded {
                return "MacEntry{mac=\(mac), iface=\(iface.name), offloaded=\(offloaded)(\(offloadedCount))}"
            } else {
                return "MacEntry{mac=\(mac), iface=\(iface.name)}"
            }
        }

        public func hash(into hasher: inout Hasher) {
            mac.hash(into: &hasher)
        }

        public static func == (lhs: MacTable.MacEntry, rhs: MacTable.MacEntry) -> Bool {
            return lhs === rhs
        }
    }
}
