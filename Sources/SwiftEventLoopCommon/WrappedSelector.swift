import VProxyCommon

public class WrappedSelector: FDSelector {
    private let selector: FDSelector

    private struct REntry: CustomStringConvertible {
        var watchedEvents: EventSet
        var attachment: UnsafeMutableRawPointer?

        init(watchedEvents: EventSet, attachment: UnsafeMutableRawPointer?) {
            self.watchedEvents = watchedEvents
            self.attachment = attachment
        }

        var description: String {
            return "REntry{watchedEvents=\(watchedEvents), attachment=\(String(describing: attachment))}"
        }
    }

    private var VIRTUAL_LOCK = Lock() // only lock when calculating and registering, which would be enough for current code base
    private var virtualSocketFDs = [VirtualFDHandle: REntry]()
    private var readableFired = Set<FDHandle>()
    private var writableFired = Set<FDHandle>()

    public init(selector: FDSelector) {
        self.selector = selector
    }

    public func isOpen() -> Bool {
        return selector.isOpen()
    }

    private func calcVirtual(_ count: inout Int, _ entries: inout [SelectedEntry]) {
        VIRTUAL_LOCK.lock()
        defer { VIRTUAL_LOCK.unlock() }

        for (fdHandle, entry) in virtualSocketFDs {
            if entries.capacity <= count {
                break
            }

            let fd = fdHandle.fd

            var readable = false
            var writable = false
            if entry.watchedEvents.have(.READABLE) {
                if readableFired.contains(fd.handle()) {
                    assert(Logger.lowLevelDebug("fire readable for \(fd)"))
                    readable = true
                }
            }
            if entry.watchedEvents.have(.WRITABLE) {
                if writableFired.contains(fd.handle()) {
                    assert(Logger.lowLevelDebug("fire writable for \(fd)"))
                    writable = true
                }
            }
            let eventSet: EventSet
            if readable && writable {
                eventSet = EventSet.readwrite()
            } else if readable {
                eventSet = EventSet.read()
            } else if writable {
                eventSet = EventSet.write()
            } else {
                eventSet = EventSet.none()
            }
            entries[count] = SelectedEntry(fd: fd, ready: eventSet, attachment: entry.attachment)
            count += 1
        }
    }

    public func select(_ entries: inout [SelectedEntry]) throws(IOException) -> Int {
        var count = try selector.select(&entries)
        calcVirtual(&count, &entries)
        return count
    }

    public func selectNow(_ entries: inout [SelectedEntry]) throws(IOException) -> Int {
        var count = try selector.selectNow(&entries)
        calcVirtual(&count, &entries)
        return count
    }

    public func select(_ entries: inout [SelectedEntry], millis: Int) throws(IOException) -> Int {
        var count = try selector.select(&entries, millis: millis)
        calcVirtual(&count, &entries)
        return count
    }

    public func wakeup() {
        selector.wakeup()
    }

    public func isRegistered(_ fd: any FD) -> Bool {
        if let virtualFD = fd as? any VirtualFD {
            let handle = virtualFD.handle()
            return virtualSocketFDs.keys.contains(handle)
        } else {
            return selector.isRegistered(fd)
        }
    }

    public func register(_ fd: any FD, ops: EventSet, attachment: UnsafeMutableRawPointer?) throws(IOException) {
        assert(Logger.lowLevelDebug("register fd to selector \(fd)"))

        if let virtualFd = fd as? any VirtualFD {
            assert(Logger.lowLevelDebug("register virtual fd to selector"))
            VIRTUAL_LOCK.lock()
            defer { VIRTUAL_LOCK.unlock() }
            virtualSocketFDs[virtualFd.handle()] = REntry(watchedEvents: ops, attachment: attachment)
            virtualFd.onRegister()
        } else {
            assert(Logger.lowLevelDebug("register real fd to selector"))
            try selector.register(fd, ops: ops, attachment: attachment)
        }
    }

    public func remove(_ fd: any FD) -> UnsafeMutableRawPointer? {
        assert(Logger.lowLevelDebug("remove fd from selector \(fd)"))
        if let virtualFD = fd as? any VirtualFD {
            let removed = virtualSocketFDs.removeValue(forKey: virtualFD.handle())
            readableFired.remove(fd.handle())
            writableFired.remove(fd.handle())
            virtualFD.onRemove()
            return removed?.attachment
        } else {
            return selector.remove(fd)
        }
    }

    public func modify(_ fd: any FD, ops: EventSet) {
        if let virtualFD = fd as? any VirtualFD {
            let handle = virtualFD.handle()
            if virtualSocketFDs.keys.contains(handle) {
                virtualSocketFDs[virtualFD.handle()]?.watchedEvents = ops
            } else {
                Logger.error(LogType.SOCKET_ERROR, "\(virtualFD) is not registered")
            }
        } else {
            selector.modify(fd, ops: ops)
        }
    }

    func firingEvents(_ fd: any VirtualFD) -> EventSet {
        var ret = EventSet.none()

        if writableFired.contains(fd.handle()) {
            ret = ret.combine(EventSet.write())
        }
        if readableFired.contains(fd.handle()) {
            ret = ret.combine(EventSet.read())
        }

        return ret
    }

    public func events(_ fd: any FD) -> EventSet {
        if let virtualFD = fd as? any VirtualFD {
            let handle = virtualFD.handle()
            if virtualSocketFDs.keys.contains(handle) {
                return virtualSocketFDs[handle]!.watchedEvents
            } else {
                return EventSet.none()
            }
        } else {
            return selector.events(fd)
        }
    }

    public func attachment(_ fd: any FD) -> UnsafeMutableRawPointer? {
        if let virtualFD = fd as? any VirtualFD {
            let handle = virtualFD.handle()
            if virtualSocketFDs.keys.contains(handle) {
                return virtualSocketFDs[handle]!.attachment
            } else {
                return nil
            }
        } else {
            return selector.attachment(fd)
        }
    }

    public func entries() -> [RegisterEntry] {
        var ret = selector.entries()
        if virtualSocketFDs.isEmpty {
            return ret
        }

        for (fd, entry) in virtualSocketFDs {
            ret.append(RegisterEntry(fd: fd.fd, eventSet: entry.watchedEvents, attachment: entry.attachment))
        }

        return ret
    }

    public func close() {
        virtualSocketFDs.removeAll()
        readableFired.removeAll()
        writableFired.removeAll()
        selector.close()
    }

    public func registerVirtualReadable(_ vfd: any VirtualFD) {
        if !selector.isOpen() {
            assert(Logger.lowLevelDebug("selector \(selector) is closed but trying to register virtual readable \(vfd)"))
            return
        }
        if !vfd.isOpen() {
            Logger.error(.IMPROPER_USE, "fd \(vfd) is not open, but still trying to register readable")
            return
        }
        if !virtualSocketFDs.keys.contains(vfd.handle()) {
            assert(Logger.lowLevelDebug("cannot register readable for \(vfd) when the fd not handled by this selector." +
                    " Maybe it comes from a pre-registration process. You may ignore this warning if it does not keep printing."))
            return
        }
        assert(Logger.lowLevelDebug("add virtual readable: \(vfd)"))
        readableFired.insert(vfd.handle())

        // check fired
        if let rentry = virtualSocketFDs[vfd.handle()] {
            if rentry.watchedEvents.have(.READABLE) {
                wakeup()
            }
        }
    }

    public func removeVirtualReadable(_ vfd: any VirtualFD) {
        assert(Logger.lowLevelDebug("remove virtual readable: \(vfd)"))
        readableFired.remove(vfd.handle())
    }

    public func registerVirtualWritable(_ vfd: any VirtualFD) {
        if !selector.isOpen() {
            assert(Logger.lowLevelDebug("selector \(selector) is closed but trying to register virtual writable \(vfd)"))
            return
        }
        if !vfd.isOpen() {
            Logger.error(LogType.IMPROPER_USE, "fd \(vfd) is not open, but still trying to register writable")
            return
        }
        if !virtualSocketFDs.keys.contains(vfd.handle()) {
            assert(Logger.lowLevelDebug("cannot register writable for \(vfd) when the fd not handled by this selector." +
                    " Maybe it comes from a pre-registration process. You may ignore this warning if it does not keep printing."))
            return
        }
        assert(Logger.lowLevelDebug("add virtual writable: \(vfd)"))
        writableFired.insert(vfd.handle())

        // check fired
        if let rentry = virtualSocketFDs[vfd.handle()] {
            if rentry.watchedEvents.have(.WRITABLE) {
                wakeup()
            }
        }
    }

    public func removeVirtualWritable(_ vfd: any VirtualFD) {
        assert(Logger.lowLevelDebug("remove virtual writable: \(vfd)"))
        writableFired.remove(vfd.handle())
    }

    public func getSelector() -> FDSelector {
        return selector
    }

    public func getFiredExtra() -> (Int, UnsafePointer<FiredExtra>) {
        return selector.getFiredExtra()
    }
}
