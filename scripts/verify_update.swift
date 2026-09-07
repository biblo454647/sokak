import Foundation
import CryptoKit

// Read-only verification uses the public key. It never accesses Keychain.
final class Enclosures: NSObject, XMLParserDelegate {
    var items: [[String: String]] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "enclosure" { items.append(attributes) }
    }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "Sokak.Release", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
do {
    let args = CommandLine.arguments
    try require(args.count == 3, "Usage: swift scripts/verify_update.swift appcast.xml archive.zip")
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: "Resources/Info.plist")), format: nil) as! [String: Any]
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: plist["SUPublicEDKey"] as! String)!)
    let feed = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let boundary = feed.range(of: marker, options: .backwards), let trailer = String(data: feed[boundary.lowerBound...], encoding: .utf8) else {
        throw NSError(domain: "Sokak.Release", code: 2, userInfo: [NSLocalizedDescriptionKey: "Feed signature is missing."])
    }
    let pattern = try NSRegularExpression(pattern: "^<!-- sparkle-signatures:\\nedSignature: ([A-Za-z0-9+/=]+)\\nlength: ([0-9]+)\\n-->\\n?$")
    guard let match = pattern.firstMatch(in: trailer, range: NSRange(trailer.startIndex..., in: trailer)),
          let signatureRange = Range(match.range(at: 1), in: trailer), let lengthRange = Range(match.range(at: 2), in: trailer),
          let signature = Data(base64Encoded: String(trailer[signatureRange])) else {
        throw NSError(domain: "Sokak.Release", code: 3, userInfo: [NSLocalizedDescriptionKey: "Feed signature trailer is malformed."])
    }
    let content = feed.prefix(boundary.lowerBound)
    try require(Int(trailer[lengthRange]) == content.count && key.isValidSignature(signature, for: content), "Feed signature verification failed.")
    let enclosures = Enclosures(), parser = XMLParser(data: content)
    parser.shouldResolveExternalEntities = false
    parser.delegate = enclosures
    try require(parser.parse(), "The signed feed is not valid XML.")
    let archiveURL = URL(fileURLWithPath: args[2])
    guard let item = enclosures.items.first(where: { URL(string: $0["url"] ?? "")?.lastPathComponent == archiveURL.lastPathComponent }),
          let archiveSignature = Data(base64Encoded: item["sparkle:edSignature"] ?? "") else {
        throw NSError(domain: "Sokak.Release", code: 4, userInfo: [NSLocalizedDescriptionKey: "No signed enclosure matches the archive."])
    }
    let archive = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
    try require(Int(item["length"] ?? "") == archive.count && key.isValidSignature(archiveSignature, for: archive), "Archive signature verification failed.")
    print("Passed: feed and archive Ed25519 signatures, exact lengths, and matching enclosure. Public-key verification only.")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
