import VProxyCommon

public class IPVS {
    public private(set) var services = [PktTuple: Service]()

    public init() {}

    public func addService(_ svc: Service) -> Bool {
        let tup = PktTuple(proto: svc.proto,
                           srcPort: 0,
                           dstPort: svc.port,
                           srcIp: GetAnyIpWithSameAFAs(ip: svc.vip), dstIp: svc.vip)
        if services.keys.contains(tup) {
            return false
        }
        services[tup] = svc
        return true
    }

    public func removeService(_ proto: UInt8, vip: any IP, port: UInt16) -> Bool {
        let tup = PktTuple(proto: proto,
                           srcPort: 0,
                           dstPort: port,
                           srcIp: GetAnyIpWithSameAFAs(ip: vip), dstIp: vip)
        return services.removeValue(forKey: tup) != nil
    }
}
