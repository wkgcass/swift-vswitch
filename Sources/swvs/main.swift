#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

func main() -> Int32 {
    // TODO:
    print("TODO")
    return 1
}

let exitCode = main()
exit(exitCode)
