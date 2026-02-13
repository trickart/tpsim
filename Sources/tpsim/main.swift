import Foundation
import ThermalPrinterCommand
import ReceiptRenderer
import Communication
#if canImport(CNIOLinux)
@preconcurrency import CNIOLinux
#endif

setbuf(stdout, nil)

if CommandLine.arguments.contains("--license") {
    printLicenses()
    exit(0)
}

let sixelSupported = detectSixelSupport()

let server = TCPServer(port: 9100)

do {
    let (boundPort, connections) = try await server.start()

    print("Thermal Printer Simulator listening on port \(boundPort)...")
    if sixelSupported {
        print("Sixel graphics: enabled")
    } else {
        print("Sixel graphics: disabled (terminal does not support Sixel)")
    }
    print("Send ESC/POS data via TCP (e.g., nc localhost 9100)")
    print("Press Ctrl+C to stop.\n")

    for try await connection in connections {
        Task {
            await handleConnection(connection)
        }
    }
} catch {
    print("Error: \(error)")
    exit(1)
}

func handleConnection(_ connection: TCPConnection) async {
    let remoteAddress = connection.remoteAddress
    print("Connection from \(remoteAddress)")

    do {
        try await connection.withConnection { receive, send in
            var decoder = ESCPOSDecoder()
            var renderer = TextReceiptRenderer(ansiStyleEnabled: (isatty(STDOUT_FILENO) != 0), sixelEnabled: sixelSupported)
            let cellSize = detectCellSize()
            if let cellSize {
                renderer.cellPixelWidth = cellSize.cellPixelWidth
                renderer.displayScale = cellSize.displayScale
            }

            for try await data in receive {
                let commands = decoder.decode(data)
                renderer.render(commands)

                for command in commands {
                    if case .requestProcessIdResponse(let d1, let d2, let d3, let d4) = command {
                        // プロセスIDレスポンス送信: Header(37H 25H) + fn(30H) + status(00H) + d1-d4 + NUL(00H)
                        let response = Data([0x37, 0x25, 0x30, 0x00, d1, d2, d3, d4, 0x00])
                        try await send(response)
                        print("process: \(d1), \(d2), \(d3), \(d4)")
                    }
                }
            }
        }
    } catch {
        // 接続が閉じられた場合のエラーは正常終了として扱う
    }

    print("Connection from \(remoteAddress) closed")
}
