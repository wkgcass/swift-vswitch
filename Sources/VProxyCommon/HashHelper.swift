public class HashHelper {
    private init() {}

    public static func hash(from a: AnyObject, into hasher: inout Hasher) {
        ObjectIdentifier(a).hash(into: &hasher)
    }
}
