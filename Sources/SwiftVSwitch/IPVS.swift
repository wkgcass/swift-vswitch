import VProxyCommon

public class IPVS {
    public private(set) var services = [PktTuple: Service]()

    public init() {}

    public func addService(_ svc: Service) -> Bool {
        let tup = GetServiceTuple(proto: svc.proto, vip: svc.vip, port: svc.port)
        if services.keys.contains(tup) {
            return false
        }
        services[tup] = svc
        return true
    }

    public func removeService(_ proto: UInt8, vip: any IP, port: UInt16) -> Bool {
        let tup = GetServiceTuple(proto: proto, vip: vip, port: port)
        return services.removeValue(forKey: tup) != nil
    }
}

public func GetServiceTuple(proto: UInt8, vip: any IP, port: UInt16) -> PktTuple {
    return PktTuple(proto: proto,
                    srcPort: 0,
                    dstPort: port,
                    srcIp: GetAnyIpWithSameAFAs(ip: vip), dstIp: vip)
}
