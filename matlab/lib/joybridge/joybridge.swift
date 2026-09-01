// joybridge.swift — minimal macOS HID joystick -> UDP bridge for MATLAB
//
// Reads a generic HID joystick/gamepad through IOKit HID (native arm64, no
// toolboxes) and streams its axes and buttons as line-oriented UDP datagrams to
// localhost. Written for the AE4-311 Citation model on Apple Silicon, where
// Simulink 3D Animation (the model's Joystick Input block) is unavailable.
//
// Build:   ./build.sh          (or: swiftc -O joybridge.swift -framework IOKit
//                                    -framework CoreFoundation -o joybridge)
//
// Usage:   joybridge --list
//              print every HID joystick/gamepad (name, VID, PID) and exit
//          joybridge [--vid 0x044F] [--pid 0x0406] [--port 25147] [--rate 100]
//              open the first matching device and stream until killed
//
// Wire format (ASCII, one datagram per line, '\n' terminated):
//   M,<name>,<vid>,<pid>,<nAxes>,<usage0>,..,<usageN-1>,<nButtons>
//       metadata, resent ~1 Hz. <usageK> is the HID Generic-Desktop usage code
//       of axis K (48=X 49=Y 50=Z 51=Rx 52=Ry 53=Rz 54=Slider 55=Dial 56=Wheel
//       57=Hat). Axis order is ascending usage code, stable for a given device.
//   D,<seq>,<nAxes>,<a0>,..,<aN-1>,<nButtons>,<b0>,..,<bM-1>
//       data, sent at --rate Hz. aK is normalised to [0,1] from the element
//       logical range; bK is 0 or 1. seq is a wrapping uint32 counter.
//
// Calibration (centre, sign, dead-zone, span, channel->axis mapping) is done on
// the MATLAB side by joystick_calibrate.m — this bridge stays policy-free.

import Foundation
import IOKit
import IOKit.hid

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

func parseIntArg(_ s: String) -> Int? {
    let t = s.lowercased()
    if t.hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
    return Int(t)
}

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

// Generic-Desktop (page 0x01) usage codes we treat as analogue axes.
let axisUsages: Set<Int> = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]
let kGenericDesktopPage = 0x01
let kButtonPage = 0x09

// ---------------------------------------------------------------------------
// UDP sender (BSD sockets, no Network.framework dependency)
// ---------------------------------------------------------------------------

final class UDPOut {
    private let fd: Int32
    private var addr: sockaddr_in

    init(host: String, port: UInt16) {
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 { die("socket() failed") }
        addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
    }

    func send(_ line: String) {
        var a = addr
        let bytes = Array(line.utf8)
        _ = withUnsafePointer(to: &a) { ap in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
                sendto(fd, bytes, bytes.count, 0, sap, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}

// ---------------------------------------------------------------------------
// device model
// ---------------------------------------------------------------------------

struct Axis {
    let elem: IOHIDElement
    let usage: Int
    let lmin: Double
    let lmax: Double
}

final class Bridge {
    let manager: IOHIDManager
    var device: IOHIDDevice?
    var axes: [Axis] = []
    var buttonElems: [IOHIDElement] = []

    var name = "unknown"
    var vid = 0
    var pid = 0

    let out: UDPOut
    let rateHz: Double
    var seq: UInt32 = 0

    init(out: UDPOut, rateHz: Double) {
        self.out = out
        self.rateHz = rateHz
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // -- discovery ---------------------------------------------------------

    static func matchingDicts() -> CFArray {
        // Generic Desktop / Joystick (4) and Generic Desktop / Gamepad (5)
        let mk: (Int, Int) -> CFDictionary = { page, usage in
            [kIOHIDDeviceUsagePageKey: page, kIOHIDDeviceUsageKey: usage] as CFDictionary
        }
        return [mk(kGenericDesktopPage, 4), mk(kGenericDesktopPage, 5)] as CFArray
    }

    static func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? Int) ?? 0
    }
    static func strProp(_ dev: IOHIDDevice, _ key: String) -> String {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? String) ?? ""
    }

    func listDevices() {
        IOHIDManagerSetDeviceMatchingMultiple(manager, Bridge.matchingDicts())
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        if set.isEmpty { print("(no HID joystick or gamepad found)"); return }
        for d in set {
            let n = Bridge.strProp(d, kIOHIDProductKey)
            let v = Bridge.intProp(d, kIOHIDVendorIDKey)
            let p = Bridge.intProp(d, kIOHIDProductIDKey)
            print(String(format: "name=%@  vid=0x%04X  pid=0x%04X", n, v, p))
        }
    }

    func open(vid wantVid: Int?, pid wantPid: Int?) {
        IOHIDManagerSetDeviceMatchingMultiple(manager, Bridge.matchingDicts())
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var chosen: IOHIDDevice?
        for d in set {
            let v = Bridge.intProp(d, kIOHIDVendorIDKey)
            let p = Bridge.intProp(d, kIOHIDProductIDKey)
            if let wv = wantVid, wv != v { continue }
            if let wp = wantPid, wp != p { continue }
            chosen = d; break
        }
        guard let dev = chosen ?? set.first else { die("no matching HID joystick found") }
        device = dev
        name = Bridge.strProp(dev, kIOHIDProductKey)
        vid = Bridge.intProp(dev, kIOHIDVendorIDKey)
        pid = Bridge.intProp(dev, kIOHIDProductIDKey)

        let elems = IOHIDDeviceCopyMatchingElements(dev, nil, IOOptionBits(kIOHIDOptionsTypeNone))
            as? [IOHIDElement] ?? []
        var found: [Axis] = []
        for e in elems {
            let page = Int(IOHIDElementGetUsagePage(e))
            let usage = Int(IOHIDElementGetUsage(e))
            if page == kGenericDesktopPage && axisUsages.contains(usage) {
                let lmin = Double(IOHIDElementGetLogicalMin(e))
                let lmax = Double(IOHIDElementGetLogicalMax(e))
                if found.contains(where: { $0.usage == usage }) { continue }
                found.append(Axis(elem: e, usage: usage, lmin: lmin, lmax: max(lmax, lmin + 1)))
            } else if page == kButtonPage {
                buttonElems.append(e)
            }
        }
        axes = found.sorted { $0.usage < $1.usage }

        FileHandle.standardError.write(
            (String(format: "joybridge: %@ (vid=0x%04X pid=0x%04X) axes=%d buttons=%d\n",
                    name, vid, pid, axes.count, buttonElems.count)).data(using: .utf8)!)
    }

    // -- streaming -------------------------------------------------------

    // Poll the current value of one element; returns 0 if unreadable.
    func readInt(_ elem: IOHIDElement) -> Int {
        guard let dev = device else { return 0 }
        var vref: Unmanaged<IOHIDValue>?
        let rc = withUnsafeMutablePointer(to: &vref) { ptr -> IOReturn in
            ptr.withMemoryRebound(to: Unmanaged<IOHIDValue>.self, capacity: 1) {
                IOHIDDeviceGetValue(dev, elem, $0)
            }
        }
        if rc == kIOReturnSuccess, let v = vref?.takeUnretainedValue() {
            return IOHIDValueGetIntegerValue(v)
        }
        return 0
    }

    func sendMeta() {
        var f = "M,\(name.replacingOccurrences(of: ",", with: " ")),"
        f += String(format: "0x%04X,0x%04X,", vid, pid)
        f += "\(axes.count),"
        f += axes.map { String($0.usage) }.joined(separator: ",")
        f += ",\(buttonElems.count)\n"
        out.send(f)
    }

    func sendData() {
        seq = seq &+ 1
        var f = "D,\(seq),\(axes.count),"
        f += axes.map { a -> String in
            let raw = Double(readInt(a.elem))
            let u = (raw - a.lmin) / (a.lmax - a.lmin)
            return String(format: "%.5f", min(1.0, max(0.0, u)))
        }.joined(separator: ",")
        f += ",\(buttonElems.count),"
        f += buttonElems.map { String(readInt($0) != 0 ? 1 : 0) }.joined(separator: ",")
        f += "\n"
        out.send(f)
    }

    func run() {
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        sendMeta()
        var ticks = 0
        let metaEvery = max(1, Int(self.rateHz.rounded()))   // ~1 Hz
        let period = 1.0 / rateHz
        let timer = Timer(timeInterval: period, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.sendData()
            ticks += 1
            // burst metadata over the first ~0.5 s so a late-binding receiver
            // still learns the axis layout, then settle to ~1 Hz.
            if ticks <= 25 || ticks % metaEvery == 0 { self.sendMeta() }
        }
        RunLoop.current.add(timer, forMode: .default)
        CFRunLoopRun()
    }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

var args = Array(CommandLine.arguments.dropFirst())
var wantVid: Int?
var wantPid: Int?
var port: UInt16 = 25147
var rate = 100.0
var listOnly = false

var i = 0
while i < args.count {
    switch args[i] {
    case "--list": listOnly = true
    case "--vid": i += 1; wantVid = i < args.count ? parseIntArg(args[i]) : nil
    case "--pid": i += 1; wantPid = i < args.count ? parseIntArg(args[i]) : nil
    case "--port": i += 1; if i < args.count, let p = parseIntArg(args[i]) { port = UInt16(p) }
    case "--rate": i += 1; if i < args.count, let r = Double(args[i]) { rate = r }
    case "-h", "--help":
        print("usage: joybridge [--list] [--vid 0xVVVV] [--pid 0xPPPP] [--port 25147] [--rate 100]")
        exit(0)
    default: die("unknown argument: \(args[i])")
    }
    i += 1
}

let bridge = Bridge(out: UDPOut(host: "127.0.0.1", port: port), rateHz: rate)

if listOnly {
    bridge.listDevices()
    exit(0)
}

bridge.open(vid: wantVid, pid: wantPid)
bridge.run()
