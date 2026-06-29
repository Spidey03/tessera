import Foundation
import TesseraKit

setbuf(stdout, nil)
setbuf(stderr, nil)

print("""
╔══════════════════════════════════════════╗
║         Tessera — Tiling Daemon          ║
╚══════════════════════════════════════════╝
""")

ConfigLoader.ensureConfigDir()
let loaded = ConfigLoader.load()
let tiler = Tiler(config: loaded.tesseraConfig)
let daemon = Daemon(tiler: tiler, bindings: loaded.bindings)
daemon.run()
