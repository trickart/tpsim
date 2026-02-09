import Foundation

/// rawモードでターミナルにリクエストを送り、レスポンスを読む共通ヘルパー
private func queryTerminal(request: [UInt8], isComplete: ([UInt8]) -> Bool) -> [UInt8]? {
    guard isatty(STDIN_FILENO) != 0 else { return nil }

    // 元のターミナル属性を保存
    var originalTermios = termios()
    tcgetattr(STDIN_FILENO, &originalTermios)

    // rawモードに設定（エコーなし・カノニカル無効）
    var raw = originalTermios
    raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
    raw.c_cc.16 = 0  // VMIN
    raw.c_cc.17 = 1  // VTIME = 100ms
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)

    defer {
        tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios)
    }

    _ = request.withUnsafeBufferPointer { buffer in
        write(STDOUT_FILENO, buffer.baseAddress!, buffer.count)
    }

    var response = [UInt8]()
    var buf = [UInt8](repeating: 0, count: 256)
    let deadline = DispatchTime.now() + .seconds(1)

    while DispatchTime.now() < deadline {
        let n = read(STDIN_FILENO, &buf, buf.count)
        if n > 0 {
            response.append(contentsOf: buf[0..<n])
            if isComplete(response) { break }
        } else {
            break
        }
    }

    return response.isEmpty ? nil : response
}

/// ターミナルがSixelグラフィックスに対応しているか検出する。
/// DA1 (Primary Device Attributes) リクエスト `ESC [ c` を送信し、
/// レスポンスに `4`（Sixel対応）が含まれるかで判定する。
/// 標準入力がターミナルでない場合や、タイムアウト時は false を返す。
func detectSixelSupport() -> Bool {
    // DA1リクエスト: ESC [ c
    guard let response = queryTerminal(
        request: [0x1B, 0x5B, 0x63],
        isComplete: { $0.contains(0x63) }
    ) else {
        return false
    }

    guard let responseStr = String(bytes: response, encoding: .ascii) else {
        return false
    }

    // レスポンス例: ESC [ ? 4 ; 6 c  — セミコロン区切りの属性に "4" があればSixel対応
    guard let qIndex = responseStr.firstIndex(of: "?"),
          let cIndex = responseStr.firstIndex(of: "c"),
          qIndex < cIndex else {
        return false
    }

    let body = responseStr[responseStr.index(after: qIndex)..<cIndex]
    let attributes = body.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    return attributes.contains("4")
}

/// iTerm2の Report Cell Size で取得したセル情報
struct CellSizeInfo {
    /// セル幅（デバイスピクセル単位、width × scale）
    var cellPixelWidth: Int
    /// ディスプレイのスケールファクター（Retina=2, 通常=1）
    var displayScale: Int
}

/// iTerm2の Report Cell Size エスケープコードでセル情報を取得する。
/// リクエスト: OSC 1337 ; ReportCellSize ST
/// レスポンス: OSC 1337 ; ReportCellSize=height;width[;scale] ST
/// 非対応ターミナルやタイムアウト時は nil を返す。
func detectCellSize() -> CellSizeInfo? {
    // OSC 1337 ; ReportCellSize ST = ESC ] 1337 ; ReportCellSize ESC backslash
    let request: [UInt8] = Array("\u{1B}]1337;ReportCellSize\u{1B}\\".utf8)

    guard let response = queryTerminal(
        request: request,
        isComplete: { bytes in
            // ST = ESC \ (0x1B 0x5C) または BEL (0x07)
            if bytes.contains(0x07) { return true }
            if bytes.count >= 2 {
                for i in 1..<bytes.count {
                    if bytes[i - 1] == 0x1B && bytes[i] == 0x5C {
                        return true
                    }
                }
            }
            return false
        }
    ) else {
        return nil
    }

    guard let responseStr = String(bytes: response, encoding: .ascii) else {
        return nil
    }

    // "ReportCellSize=height;width[;scale]" をパース
    guard let eqIndex = responseStr.firstIndex(of: "=") else {
        return nil
    }

    // 終端（BEL or ESC）の手前まで取得
    let endIndex: String.Index
    if let belIndex = responseStr.firstIndex(of: "\u{07}") {
        endIndex = belIndex
    } else if let escIndex = responseStr.lastIndex(of: "\u{1B}") {
        endIndex = escIndex
    } else {
        endIndex = responseStr.endIndex
    }

    let body = responseStr[responseStr.index(after: eqIndex)..<endIndex]
    let parts = body.split(separator: ";")
    guard parts.count >= 2, let width = Double(parts[1]) else {
        return nil
    }

    let scale = parts.count >= 3 ? (Double(parts[2]) ?? 1.0) : 1.0
    let displayScale = max(1, Int(scale.rounded()))
    let cellPixelWidth = Int(width * scale)

    guard cellPixelWidth > 0 else { return nil }

    return CellSizeInfo(cellPixelWidth: cellPixelWidth, displayScale: displayScale)
}
