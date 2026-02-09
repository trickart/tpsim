import Foundation
import NIOCore

public struct TCPConnection: Sendable {
    private let channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
    public let remoteAddress: String

    internal init(channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, remoteAddress: String) {
        self.channel = channel
        self.remoteAddress = remoteAddress
    }

    public func withConnection(
        _ handler: @Sendable (
            _ receive: AsyncThrowingStream<Data, any Error>,
            _ send: @Sendable (Data) async throws -> Void
        ) async throws -> Void
    ) async throws {
        try await channel.executeThenClose { inbound, outbound in
            let receiveStream = AsyncThrowingStream<Data, any Error> { continuation in
                let task = Task {
                    do {
                        for try await var buffer in inbound {
                            let data = Data(buffer.readBytes(length: buffer.readableBytes)!)
                            continuation.yield(data)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }

            let sendFunc: @Sendable (Data) async throws -> Void = { data in
                let buffer = ByteBuffer(bytes: data)
                try await outbound.write(buffer)
            }

            try await handler(receiveStream, sendFunc)
        }
    }
}
