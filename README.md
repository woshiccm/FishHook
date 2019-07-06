

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
![badge-pms](https://img.shields.io/badge/languages-Swift-orange.svg)
[![Swift Version](https://img.shields.io/badge/Swift-4.0--5.0.x-F16D39.svg?style=flat)](https://developer.apple.com/swift)


FishHook is a lightweight, pure-Swift library that enables dynamically rebinding symbols in Mach-O binaries running on iOS in the simulator and on device. This project is heavily inspired by the popular [fishhook](https://github.com/facebook/fishhook).

## Usage

```
typealias NewPrintf = @convention(thin) (String, Any...) -> Void

func newPrinf(str: String, arg: Any...) -> Void {
    print("test success")
}

public func fishhookPrint(newMethod: UnsafeMutableRawPointer) {
    var oldMethod: UnsafeMutableRawPointer?
    rebindSymbol("printf", replacement: newMethod, replaced: &oldMethod)
}

fishhookPrint(newMethod: unsafeBitCast(newPrinf as NewPrintf, to: UnsafeMutableRawPointer.self))
```


## Requirements

- iOS 8.0+
- Swift 4.0-5.x


## Installation

#### Carthage
Add the following line to your [Cartfile](https://github.com/carthage/carthage)

```
git "https://github.com/woshiccm/FishHook.git" "master"
```

## Thanks
[fishhook](https://github.com/facebook/fishhook)   
[anti-fishhook](https://github.com/TannerJin/anti-fishhook).   

## License

Aspect is released under the MIT license. See LICENSE for details.


