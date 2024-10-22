#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

func main() -> Int32 {
    // TODO:
    return 0
}

let exitCode = main()
exit(exitCode)
