import Foundation
import ThermalPrinterCommand
import PrinterSimulator
import Communication
#if canImport(CNIOLinux)
@preconcurrency import CNIOLinux
#endif

setbuf(stdout, nil)

if CommandLine.arguments.contains("--license") {
    printLicenses()
    exit(0)
}

var port = 9100
let arguments = CommandLine.arguments
if arguments.count >= 2,
   let parsed = Int(arguments[1]),
   (1...65535).contains(parsed) {
    port = parsed
}

let sixelSupported = detectSixelSupport()

let server = TCPServer(port: port)

do {
    let (boundPort, connections) = try await server.start()

    print("Thermal Printer Simulator listening on port \(boundPort)...")
    if sixelSupported {
        print("Sixel graphics: enabled")
    } else {
        print("Sixel graphics: disabled (terminal does not support Sixel)")
    }
    print("Send ESC/POS data via TCP (e.g., nc localhost \(boundPort)")
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
            var renderer = TextReceiptRenderer(
                ansiStyleEnabled: (isatty(STDOUT_FILENO) != 0),
                sixelEnabled: sixelSupported
            )
            let cellSize = detectCellSize()
            if let cellSize {
                renderer.cellPixelWidth = cellSize.cellPixelWidth
                renderer.displayScale = cellSize.displayScale
            }
            var simulator = ESCPOSPrinterSimulator(renderer: renderer)

            for try await data in receive {
                let commands = decoder.decode(data)
                for response in simulator.process(commands) {
                    try await send(response)
                }
            }
        }
    } catch {
        // 接続が閉じられた場合のエラーは正常終了として扱う
    }

    print("Connection from \(remoteAddress) closed")
}
