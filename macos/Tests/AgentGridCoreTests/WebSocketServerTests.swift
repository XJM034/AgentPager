import Foundation
import Testing
@testable import AgentGridCore

@Test("连续帧移除前缀后仍可安全解码")
func decodesFrameAfterRemovingConsumedPrefix() {
    var buffer = maskedFrame(opcode: 0x1, text: "first")
    buffer.append(maskedFrame(opcode: 0x8, text: ""))

    let first = WebSocketServer.decodeClientFrame(buffer)
    #expect(first?.payload == Data("first".utf8))
    buffer.removeFirst(first?.consumed ?? 0)

    let close = WebSocketServer.decodeClientFrame(buffer)

    #expect(close?.opcode == 0x8)
    #expect(close?.payload.isEmpty == true)
}

private func maskedFrame(opcode: UInt8, text: String) -> Data {
    let payload = Array(text.utf8)
    let mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
    var frame = Data([0x80 | opcode, 0x80 | UInt8(payload.count)])
    frame.append(contentsOf: mask)
    for (index, byte) in payload.enumerated() {
        frame.append(byte ^ mask[index % mask.count])
    }
    return frame
}
