import libae
import SwiftEventLoopCommon
import SwiftEventLoopPosixCHelper
import VProxyCommon

let globalClose = close

class AESelector: FDSelector {
    private var isOpen_ = true
    private let ae: UnsafeMutablePointer<aeEventLoop>
    private var fds: [PosixFD?]
    private var pipeFDs = [Int32](repeating: 0, count: 2) // 0 read, 1 write

    public init(setsize: Int = 128 * 1024, opts: SelectorOptions = SelectorOptions.defaultOpts) throws(IOException) {
        var selectorFlags: Int32 = 0
        if opts.preferPoll {
            selectorFlags |= AE_FLAG_PREFER_POLL
        }
        var epfd = opts.epfd
        if epfd < 0 {
            epfd = 0
        }
        let ae = aeCreateEventLoop3(Int32(setsize), Int32(epfd), selectorFlags)

        guard let ae else {
            throw IOException("failed to open ae event loop")
        }
        self.ae = ae
        fds = Arrays.newArray(capacity: setsize)
        var err = pipe(&pipeFDs)
        if err != 0 {
            aeDeleteEventLoop(ae)
            throw IOException("failed to create pipe fds or configure nonblocking")
        }
        err = swvs_configureBlocking(pipeFDs[0], 0)
        if err == 0 {
            err = swvs_configureBlocking(pipeFDs[1], 0)
        }
        if err == 0 {
            err = aeCreateFileEvent(ae, pipeFDs[0], AE_READABLE, nil, nil)
        }
        if err != 0 {
            aeDeleteEventLoop(ae)
            closePipeFDs(pipeFDs)
            throw IOException("failed to set nonblocking on pipe fds or watch pipe fd read side")
        }
    }

    private func closePipeFDs(_ pipeFDs: [Int32]) {
        _ = globalClose(pipeFDs[0])
        if pipeFDs[0] != pipeFDs[1] {
            _ = globalClose(pipeFDs[1])
        }
    }

    func isOpen() -> Bool {
        return isOpen_
    }

    func select(_ entries: inout [SelectedEntry]) throws(IOException) -> Int {
        let nevents = aePoll(ae, nil)
        return handleFired(nevents, &entries)
    }

    func selectNow(_ entries: inout [SelectedEntry]) throws(IOException) -> Int {
        var tv = timeval(tv_sec: 0, tv_usec: 0)
        let nevents = aePoll(ae, &tv)
        return handleFired(nevents, &entries)
    }

    func select(_ entries: inout [SelectedEntry], millis: Int) throws(IOException) -> Int {
        var tv = timeval(tv_sec: 0, tv_usec: 0)
        if millis / 1000 != 0 {
            tv.tv_sec = Int(millis / 1000)
        }
#if os(Linux)
        tv.tv_usec = Int((millis % 1000) * 1000)
#else
        tv.tv_usec = Int32((millis % 1000) * 1000)
#endif
        let nevents = aePoll(ae, &tv)
        return handleFired(nevents, &entries)
    }

    private func handleFired(_ nevents: Int32, _ entries: inout [SelectedEntry]) -> Int {
        var index = 0
        var added = 0
        while index < nevents && index < entries.capacity {
            let fired = ae.pointee.fired.advanced(by: index).pointee
            index += 1
            if fired.fd == pipeFDs[0] {
                clearPipeFD()
                continue
            }
            let fd = fds[Int(fired.fd)]!
            var ops = EventSet.none()
            if fired.mask & AE_READABLE != 0 {
                ops = ops.combine(EventSet.read())
            }
            if fired.mask & AE_WRITABLE != 0 {
                ops = ops.combine(EventSet.write())
            }
            let event = ae.pointee.events[Int(fired.fd)]
            entries[added] = SelectedEntry(fd: fd, ready: ops, attachment: event.clientData)
            added += 1
        }
        return added
    }

    private func clearPipeFD() {
        var buf: UInt64 = 0
        while true {
            let n = read(pipeFDs[0], &buf, 8)
            if n == -1 {
                break
            }
        }
    }

    func wakeup() {
        if !isOpen() {
            return
        }
        var buf = Int64(-1)
        _ = write(pipeFDs[1], &buf, 8)
    }

    func isRegistered(_ fd: any FD) -> Bool {
        if let pfd = fd as? PosixFD {
            return fds[Int(pfd.fd)] != nil
        }
        return false
    }

    private func ops2mask(_ ops: EventSet) -> Int32 {
        var mask: Int32 = 0
        if ops.have(.READABLE) {
            mask |= AE_READABLE
        }
        if ops.have(.WRITABLE) {
            mask |= AE_WRITABLE
        }
        return mask
    }

    private func mask2ops(_ mask: Int32) -> EventSet {
        var ops = EventSet.none()
        if mask & AE_READABLE != 0 {
            ops = ops.combine(EventSet.read())
        }
        if mask & AE_WRITABLE != 0 {
            ops = ops.combine(EventSet.write())
        }
        return ops
    }

    func register(_ fd: any FD, ops: EventSet, attachment: UnsafeMutableRawPointer?) throws(IOException) {
        if let pfd = fd as? PosixFD {
            let mask = ops2mask(ops)
            if aeCreateFileEvent(ae, pfd.fd, mask, nil, attachment) == 0 {
                fds[Int(pfd.fd)] = pfd
            } else {
                throw IOException("failed to register \(fd) into event loop")
            }
        } else {
            Logger.error(.IMPROPER_USE, "\(fd) is not a PosixFD")
        }
    }

    func remove(_ fd: any FD) -> UnsafeMutableRawPointer? {
        if let pfd = fd as? PosixFD {
            let ret = ae.pointee.events[Int(pfd.fd)].clientData
            aeDeleteFileEvent(ae, pfd.fd, AE_READABLE | AE_WRITABLE)
            fds[Int(pfd.fd)] = nil
            return ret
        } else {
            Logger.error(.IMPROPER_USE, "\(fd) is not a PosixFD")
        }
        return nil
    }

    func modify(_ fd: any FD, ops: EventSet) {
        if let pfd = fd as? PosixFD {
            let event = ae.pointee.events[Int(pfd.fd)]
            let oldMask = event.mask
            let mask = ops2mask(ops)

            let toAdd = mask & ~oldMask
            let toDelete = oldMask & ~mask

            if toAdd != 0 {
                aeCreateFileEvent(ae, pfd.fd, mask, nil, event.clientData)
            }
            if toDelete != 0 {
                aeDeleteFileEvent(ae, pfd.fd, toDelete)
            }
        } else {
            Logger.error(.IMPROPER_USE, "\(fd) is not a PosixFD")
        }
    }

    func events(_ fd: any FD) -> EventSet {
        if let pfd = fd as? PosixFD {
            let mask = ae.pointee.events[Int(pfd.fd)].mask
            let ops = mask2ops(mask)
            return ops
        } else {
            Logger.error(.IMPROPER_USE, "\(fd) is not a PosixFD")
            return EventSet.none()
        }
    }

    func attachment(_ fd: any FD) -> UnsafeMutableRawPointer? {
        if let pfd = fd as? PosixFD {
            return ae.pointee.events[Int(pfd.fd)].clientData
        } else {
            Logger.error(.IMPROPER_USE, "\(fd) is not a PosixFD")
            return nil
        }
    }

    func entries() -> [RegisterEntry] {
        var ret = [RegisterEntry]()
        for i in 0 ..< fds.count {
            guard let fd = fds[i] else {
                continue
            }
            let event = ae.pointee.events[i]
            let mask = event.mask
            ret.append(RegisterEntry(fd: fd, eventSet: mask2ops(mask),
                                     attachment: event.clientData))
        }
        return ret
    }

    func close() {
        isOpen_ = false
        aeDeleteEventLoop(ae)
        closePipeFDs(pipeFDs)
    }

    func getFiredExtra() -> (Int, UnsafePointer<FiredExtra>) {
        return (Int(ae.pointee.firedExtraNum), Convert.ptr2ptrUnsafe(ae.pointee.firedExtra))
    }
}
