import Foundation
import NIOCore
import NIOPosix

public struct TCPServer: Sendable {
    private let host: String
    private let port: Int

    public init(host: String = "localhost", port: Int) {
        self.host = host
        self.port = port
    }

    public func start() async throws -> (boundPort: Int, connections: AsyncThrowingStream<TCPConnection, any Error>) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(host: host, port: port) { childChannel in
                childChannel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<ByteBuffer, ByteBuffer>(
                        wrappingChannelSynchronously: childChannel
                    )
                }
            }

        let boundPort = channel.channel.localAddress?.port ?? port

        let connections = AsyncThrowingStream<TCPConnection, any Error> { continuation in
            let task = Task {
                do {
                    try await channel.executeThenClose { inbound in
                        for try await childChannel in inbound {
                            let remoteAddress = childChannel.channel.remoteAddress?.description ?? "unknown"
                            let connection = TCPConnection(channel: childChannel, remoteAddress: remoteAddress)
                            continuation.yield(connection)
                        }
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

        return (boundPort, connections)
    }
}
