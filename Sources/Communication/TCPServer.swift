import Foundation
import NIOCore
import NIOPosix

public struct TCPServer: Sendable {
    private let hosts: [String]
    private let port: Int

    public init(host: String, port: Int) {
        self.hosts = [host]
        self.port = port
    }

    public init(hosts: [String] = ["127.0.0.1", "::1"], port: Int) {
        self.hosts = hosts
        self.port = port
    }

    public func start() async throws -> (boundPort: Int, connections: AsyncThrowingStream<TCPConnection, any Error>) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        var boundPort = port
        var channels: [NIOAsyncChannel<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never>] = []

        for host in hosts {
            do {
                let channel = try await ServerBootstrap(group: group)
                    .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                    .bind(host: host, port: port) { childChannel in
                        childChannel.eventLoop.makeCompletedFuture {
                            try NIOAsyncChannel<ByteBuffer, ByteBuffer>(
                                wrappingChannelSynchronously: childChannel
                            )
                        }
                    }

                if let p = channel.channel.localAddress?.port {
                    boundPort = p
                }
                channels.append(channel)
            } catch {
                // バインドに失敗したホストはスキップ（例: IPv6非対応環境）
            }
        }

        guard !channels.isEmpty else {
            throw TCPServerError.noBindableAddress
        }

        let sendableChannels = channels
        let connections = AsyncThrowingStream<TCPConnection, any Error> { continuation in
            let task = Task {
                do {
                    let channels = sendableChannels
                    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                        for channel in channels {
                            taskGroup.addTask {
                                try await channel.executeThenClose { inbound in
                                    for try await childChannel in inbound {
                                        let remoteAddress = childChannel.channel.remoteAddress?.description ?? "unknown"
                                        let connection = TCPConnection(channel: childChannel, remoteAddress: remoteAddress)
                                        continuation.yield(connection)
                                    }
                                }
                            }
                        }
                        try await taskGroup.waitForAll()
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

enum TCPServerError: Error, CustomStringConvertible {
    case noBindableAddress

    var description: String {
        switch self {
        case .noBindableAddress:
            return "No address could be bound. Check that the port is not already in use."
        }
    }
}
