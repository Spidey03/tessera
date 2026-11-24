// Sign or create keys for the in-app updater (Ed25519, CryptoKit).
//
//   swift scripts/sign_update.swift keygen <private-key-file>   (never overwrites)
//   swift scripts/sign_update.swift sign <file> <expected-public-key-base64>
//
// `sign` reads the base64 private key from TESSERA_UPDATE_PRIVATE_KEY and writes
// <file>.sig. It refuses a key that does not match the one embedded in the app.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "keygen" where args.count == 3:
    let key = Curve25519.Signing.PrivateKey()
    let fd = open(args[2], O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard fd >= 0 else { fail("cannot create \(args[2]) (already exists?)") }
    do {
        try FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            .write(contentsOf: Data(key.rawRepresentation.base64EncodedString().utf8))
    } catch { fail("cannot write key: \(error)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign" where args.count == 4:
    let encoded = (ProcessInfo.processInfo.environment["TESSERA_UPDATE_PRIVATE_KEY"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw = Data(base64Encoded: encoded),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("TESSERA_UPDATE_PRIVATE_KEY is not a base64 Ed25519 key") }
    guard key.publicKey.rawRepresentation.base64EncodedString() == args[3]
    else { fail("private key does not match the public key embedded in the app") }
    do {
        let signature = try key.signature(for: Data(contentsOf: URL(fileURLWithPath: args[2])))
        try Data(signature.base64EncodedString().utf8)
            .write(to: URL(fileURLWithPath: args[2] + ".sig"))
    } catch { fail("signing failed: \(error)") }
default:
    fail("usage: sign_update.swift keygen <file> | sign <file> <public-key>")
}
