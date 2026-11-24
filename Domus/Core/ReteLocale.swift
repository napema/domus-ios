import Darwin
import Foundation

struct InfoReteWiFi: Sendable {
    let ipLocale: String
    let prefissoSottorete: String
    let broadcast: String
}

/// Rilevamento sottorete Wi-Fi (`en0`) e scansione TCP non bloccante ad alta velocità sulle porte
/// **5577** (Magic Home) e **6668** (Tuya LAN).
/// Fondamentale su iOS con firma gratuita SideStore: trova tutte le luci in ~0,8 secondi anche senza permesso Multicast Apple.
enum ReteLocale {
    static func infoWiFi() -> InfoReteWiFi? {
        var puntatore: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&puntatore) == 0, let primo = puntatore else { return nil }
        defer { freeifaddrs(primo) }

        var corrente: UnsafeMutablePointer<ifaddrs>? = primo
        var fallback: InfoReteWiFi?

        while let voce = corrente?.pointee {
            defer { corrente = voce.ifa_next }
            guard let addr = voce.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let nome = String(cString: voce.ifa_name)
            guard nome == "en0" || nome.hasPrefix("en") || nome == "bridge100" else { continue }

            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var copiaInd = sin.sin_addr
            inet_ntop(AF_INET, &copiaInd, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: ipBuf)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else { continue }

            let parti = ip.split(separator: ".").map(String.init)
            guard parti.count == 4 else { continue }
            let prefisso = "\(parti[0]).\(parti[1]).\(parti[2])"

            var bcast = "\(prefisso).255"
            if let maskPtr = voce.ifa_netmask {
                let maskSin = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                let bcastAddr = in_addr(s_addr: sin.sin_addr.s_addr | ~maskSin.sin_addr.s_addr)
                var bBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var copiaB = bcastAddr
                inet_ntop(AF_INET, &copiaB, &bBuf, socklen_t(INET_ADDRSTRLEN))
                bcast = String(cString: bBuf)
            }

            let info = InfoReteWiFi(ipLocale: ip, prefissoSottorete: prefisso, broadcast: bcast)
            if nome == "en0" { return info }
            fallback = info
        }
        return fallback
    }

    /// Scansiona tutti i 254 indirizzi della sottorete `/24` cercando host con una porta TCP aperta (5577 o 6668).
    static func scansionaPorta(prefisso: String, porta: UInt16, escludendo ipProprio: String? = nil, timeoutMs: Int32 = 900) async -> [String] {
        let candidati: [String] = (1...254).map { "\(prefisso).\($0)" }.filter { $0 != ipProprio }
        var aperti: [String] = []
        let dimensioneBlocco = 100

        for inizio in stride(from: 0, to: candidati.count, by: dimensioneBlocco) {
            let fine = min(inizio + dimensioneBlocco, candidati.count)
            let fetta = Array(candidati[inizio..<fine])
            let trovati = await verificaBloccoTCP(indirizzi: fetta, porta: porta, timeoutMs: timeoutMs)
            aperti.append(contentsOf: trovati)
        }
        return aperti
    }

    private static func verificaBloccoTCP(indirizzi: [String], porta: UInt16, timeoutMs: Int32) async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var fds: [(fd: Int32, ip: String)] = []
                fds.reserveCapacity(indirizzi.count)

                for ip in indirizzi {
                    let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
                    guard fd >= 0 else { continue }
                    let flags = fcntl(fd, F_GETFL, 0)
                    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                    var noSigPipe: Int32 = 1
                    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

                    var sin = sockaddr_in()
                    sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    sin.sin_family = sa_family_t(AF_INET)
                    sin.sin_port = porta.bigEndian
                    _ = ip.withCString { inet_pton(AF_INET, $0, &sin.sin_addr) }

                    let rc = withUnsafePointer(to: &sin) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                    if rc == 0 || errno == EINPROGRESS {
                        fds.append((fd, ip))
                    } else {
                        close(fd)
                    }
                }

                guard !fds.isEmpty else {
                    cont.resume(returning: [])
                    return
                }

                var pfds = fds.map { pollfd(fd: $0.fd, events: Int16(POLLOUT), revents: 0) }
                // poll ritorna al primo socket pronto: si ripete fino alla scadenza raccogliendo tutti
                let scadenza = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
                var finali: [Int: Int16] = [:]
                while finali.count < pfds.count {
                    let resto = Int32(max(0, scadenza.timeIntervalSinceNow * 1000.0))
                    if resto == 0 { break }
                    _ = poll(&pfds, nfds_t(pfds.count), resto)
                    for i in pfds.indices where pfds[i].fd >= 0 && pfds[i].revents != 0 {
                        finali[i] = pfds[i].revents
                        pfds[i].fd = -1
                    }
                }

                var attivi: [String] = []
                for (indice, elemento) in fds.enumerated() {
                    defer { close(elemento.fd) }
                    let rev = finali[indice] ?? 0
                    guard (rev & Int16(POLLOUT)) != 0, (rev & Int16(POLLERR | POLLHUP)) == 0 else { continue }
                    var errSocket: Int32 = 0
                    var lun = socklen_t(MemoryLayout<Int32>.size)
                    if getsockopt(elemento.fd, SOL_SOCKET, SO_ERROR, &errSocket, &lun) == 0, errSocket == 0 {
                        attivi.append(elemento.ip)
                    }
                }
                cont.resume(returning: attivi)
            }
        }
    }
}
