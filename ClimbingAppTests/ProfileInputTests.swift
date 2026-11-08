import XCTest
@testable import ClimbingApp

final class ProfileInputTests: XCTestCase {
    private func hidden(_ text: String, lineBreaks: Bool = false) -> Bool { ProfileInput.hasHiddenCharacters(text, allowLineBreaks: lineBreaks) }

    func testJoinersInEmojiAndWordsAreAllowed() {
        for text in ["Ana 🧗‍♀️", "👨‍👩‍👧", "🏳️‍🌈", "می‌خواهم", "क्‍ष"] {
            XCTAssertFalse(hidden(text), text);XCTAssertFalse(hidden(text, lineBreaks: true), text)
        }
        XCTAssertNil(ProfileInput.problem(username: "ana", name: "Ana 🧗‍♀️", bio: "می‌خواهم 👨‍👩‍👧"))
    }

    func testOtherHiddenAndControlCharactersAreRejected() {
        for value: UInt32 in [0x200B, 0x200E, 0x200F, 0x202A, 0x202E, 0x2060, 0x2066, 0x2069, 0xFEFF, 0x00, 0x07, 0x0B, 0x1B, 0x7F, 0x85, 0x9F] {
            let text = "a\(Character(UnicodeScalar(value)!))b"
            XCTAssertTrue(hidden(text), String(value, radix: 16));XCTAssertTrue(hidden(text, lineBreaks: true), String(value, radix: 16))
        }
        XCTAssertEqual(ProfileInput.problem(username: "ana", name: "Ana", bio: "a\u{2066}b"), "Your bio has hidden or formatting characters. Retype it without them.")
    }

    func testLineBreaksOnlyWhereAllowed() {
        for text in ["a\nb", "a\tb", "a\r\nb"] { XCTAssertTrue(hidden(text));XCTAssertFalse(hidden(text, lineBreaks: true)) }
        XCTAssertEqual(ProfileInput.problem(username: "ana", name: "Ana\nB", bio: ""), "Your display name has hidden or formatting characters. Retype it without them.")
        XCTAssertNil(ProfileInput.problem(username: "ana", name: "Ana", bio: "One\nTwo\tthree"))
    }

    /// Capture 1 of `pattern` in the newest migration that matches it, so the test follows later redefinitions.
    private func newest(_ pattern: String) throws -> String {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "supabase/migrations")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { throw XCTSkip("supabase/migrations isn't readable from the test host") }
        let regex = try Regex(pattern)
        var found: Substring?
        for file in files.filter({ $0.hasSuffix(".sql") }).sorted() {
            if let match = try String(contentsOf: folder.appending(path: file), encoding: .utf8).matches(of: regex).last { found = match.output[1].substring }
        }
        return String(try XCTUnwrap(found, pattern))
    }

    /// Scalars a check's character class rejects. Knows only the forms these checks use; anything else fails the test.
    private func rejected(by charClass: String) throws -> Set<UInt32> {
        let token = try Regex(#"\[:cntrl:\]|\\[xu]([0-9a-f]+)(?:-\\[xu]([0-9a-f]+))?"#)
        XCTAssertEqual(charClass.replacing(token, with: ""), "", "unrecognised syntax in [\(charClass)]")
        var set = Set<UInt32>()
        for match in charClass.matches(of: token) {
            guard let low = match.output[1].substring.flatMap({ UInt32($0, radix: 16) }) else { set.formUnion(Array(0x00...0x1F) + Array(0x7F...0x9F)); continue }
            set.formUnion(low...(match.output[2].substring.flatMap { UInt32($0, radix: 16) } ?? low))
        }
        return set
    }

    func testServerTextChecksRejectExactlyWhatTheAppRejects() throws {
        for (check, lineBreaks) in [("display_name_plain", false), ("bio_plain", true), ("caption_plain", true), ("body_plain", true)] {
            let server = try rejected(by: newest(#"constraint \#(check) check \(\w+ !~ '\[(.*?)\]'\)"#))
            XCTAssertFalse(server.contains(0x200C) || server.contains(0x200D), check)
            // From U+0001: Postgres text can't hold U+0000, so the server classes leave it out.
            for value in UInt32(1)...0xFFFF where !(0xD800...0xDFFF).contains(value) {
                let app = hidden(String(Character(UnicodeScalar(value)!)), lineBreaks: lineBreaks)
                if app != server.contains(value) { XCTFail("\(check) and the app disagree on U+\(String(value, radix: 16, uppercase: true))");break }
            }
        }
    }

    func testReservedUsernamesMatchTheServer() throws {
        let list = try newest(#"constraint username_not_reserved check \(username !~ 'chalkbook' and username not in\s*\(([^)]*)\)"#)
        XCTAssertEqual(Set(list.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "' \n")) }), ProfileInput.reserved)
    }
}
