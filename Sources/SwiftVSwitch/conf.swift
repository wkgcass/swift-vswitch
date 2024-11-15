import VProxyCommon

public struct IfaceConf {
    var name: String
    var toBridge: UInt32
    var toNetstack: UInt32
    var mac: MacAddress
    var meta: IfaceMetadata
}

public struct BridgeConf {
    var id: UInt32
}

public struct NetstackConf {
    var id: UInt32
}
