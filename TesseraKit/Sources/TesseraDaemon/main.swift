import Foundation
import TesseraKit

setbuf(stdout, nil)
setbuf(stderr, nil)

print("""
╔══════════════════════════════════════════╗
║         Tessera — Tiling Daemon          ║
╚══════════════════════════════════════════╝
""")

let config = TesseraConfig()
let tiler = Tiler(config: config)

let bindings: [KeyBinding] = [.tile, .focusLeft, .focusRight, .focusUp, .focusDown, .remove, .quit]
let daemon = Daemon(tiler: tiler, bindings: bindings)
daemon.run()
