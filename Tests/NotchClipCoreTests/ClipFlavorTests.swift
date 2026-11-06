import Testing
@testable import NotchClipCore

struct ClipFlavorTests {
    @Test func detectsLinks() {
        #expect(ClipFlavor.detect("https://www.motion.minutechbuilds.com/x?y=1") == .link(host: "motion.minutechbuilds.com"))
        #expect(ClipFlavor.detect("see https://a.com today") == .plain)
    }

    @Test func detectsColours() {
        #expect(ClipFlavor.detect("#FF6200") == .color(red: 1, green: 98.0 / 255, blue: 0))
        #expect(ClipFlavor.detect("#fff") == .color(red: 1, green: 1, blue: 1))
        #expect(ClipFlavor.detect("123456") == .plain)
    }

    @Test(arguments: ["ryanatcdr@gmail.com", "a.b+c@example.co.uk"])
    func detectsEmails(_ text: String) {
        #expect(ClipFlavor.detect(text) == .email)
    }

    @Test func detectsPhones() {
        #expect(ClipFlavor.detect("+965 5555 1234") == .phone)
    }

    @Test(arguments: ["npm run build && npm test", "func a() {\n  return 1\n}", "const x = {a: 1};"])
    func detectsCode(_ text: String) {
        #expect(ClipFlavor.detect(text) == .code)
    }

    @Test(arguments: ["Hey! Thanks for reaching out.", "Sri Lanka vs India — 3rd ODI, Colombo"])
    func plainTextStaysPlain(_ text: String) {
        #expect(ClipFlavor.detect(text) == .plain)
    }
}
