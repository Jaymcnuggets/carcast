//
//  HomeKitPairingService.swift
//  DrivingMode
//
//  Authentic HomeKit SRP-6a Pair-Setup, Pair-Verify, and MFiSAP Auth-Setup Engine
//

import Foundation
import CryptoKit
import Security
import CommonCrypto

public final class HomeKitPairingService: @unchecked Sendable {
    public static let shared = HomeKitPairingService()

    // Canonical MFi Certificate and P-256 private key scalar
    private let mfiCertHex = "3082025b06092a864886f70d010702a082024c308202480201013100300b06092a864886f70d010701a082022e3082022a308201d1a003020102021024acbb48646f8077f7463523085b60d2300a06082a8648ce3d040302308189310b300906035504061302555331133011060355040a130a4170706c6520496e632e31263024060355040b131d4170706c652043657274696669636174696f6e20417574686f72697479313d303b060355040313344170706c65204163636573736f726965732043657274696669636174696f6e20417574686f72697479202d203030303030303032301e170d3138303631333038333235395a170d3439313233313233353935395a306d310b300906035504061302555331133011060355040a130a4170706c6520496e632e311a3018060355040b13114170706c65204163636573736f72696573312d302b060355040314244950415f32344143424234383634364638303737463734363335323330383542363044323059301306072a8648ce3d020106082a8648ce3d03010703420004f498f7c8b4915ab5e62649ef3d67d0697f81f0a2059ec25cf765f5204246eec6fbafc3dbc69aec8c962b5892bed034933dfc9e2c84546037519eb29b5b567129a3363034303206092a864886f7636406240101ff042204200000000000000000000000000000000000000000000000000000000000000002300a06082a8648ce3d040302034700304402206982f4df2f178defc429d12a841a1124b074ef52423faf5898d3905d5bfea9f9022059e0b0f29a71300055abe2d44e3b976f25b4842c95373b001b90e5cfa5b78ec0a1003100"
    private let mfiScalarHex = "2fe02fbb687cb9db321464c5b66c02556fe7f603e13cf304bd7a9fef5c98ba86"

    private var mfiCertData: Data
    private var mfiSecKey: SecKey?

    // CoreUtils C Function pointers
    private typealias PairingSessionCreateFunc = @convention(c) (
        UnsafeMutablePointer<UnsafeMutableRawPointer?>,
        UnsafeRawPointer?,
        UInt32
    ) -> Int32

    private typealias PairingSessionSetSetupCodeFunc = @convention(c) (
        UnsafeMutableRawPointer,
        UnsafePointer<CChar>,
        Int
    ) -> Int32

    private typealias PairingSessionExchangeFunc = @convention(c) (
        UnsafeMutableRawPointer,
        UnsafeRawPointer?,
        Int,
        UnsafeMutablePointer<UnsafeMutableRawPointer?>,
        UnsafeMutablePointer<Int>,
        UnsafeMutablePointer<UInt8>
    ) -> Int32

    private typealias PairingSessionDeleteFunc = @convention(c) (UnsafeMutableRawPointer) -> Void

    private var createFn: PairingSessionCreateFunc?
    private var setCodeFn: PairingSessionSetSetupCodeFunc?
    private var exchangeFn: PairingSessionExchangeFunc?
    private var deleteFn: PairingSessionDeleteFunc?

    // OSStatus PairingSessionDeriveKey(session, salt, saltLen, info, infoLen, keyLen, outKey)
    private typealias PairingSessionDeriveKeyFunc = @convention(c) (
        UnsafeMutableRawPointer, UnsafeRawPointer, Int, UnsafeRawPointer, Int, Int, UnsafeMutablePointer<UInt8>
    ) -> Int32
    private var deriveKeyFn: PairingSessionDeriveKeyFunc?
    private var pendingControlKeys: (decrypt: Data, encrypt: Data)?
    private var completedVerifySession: UnsafeMutableRawPointer?

    /// Derives the per-stream ChaCha20-Poly1305 keys exactly like CarCast (libcarcast.so @ 0x3aef88):
    /// salt = "DataStream-Salt" + "%lu"(streamConnectionID), info = "DataStream-Output-Encryption-Key" / "DataStream-Input-Encryption-Key".
    /// Derives keys for an arbitrary salt string (diagnostics / variants).
    public func deriveKey(salt saltString: String, info: String) -> Data? {
        queue.sync {
            guard let session = completedVerifySession, let derive = deriveKeyFn else { return nil }
            var out = Data(count: 32)
            let salt = Array(saltString.utf8), inf = Array(info.utf8)
            let st = out.withUnsafeMutableBytes { derive(session, salt, salt.count, inf, inf.count, 32, $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
            return st == 0 ? out : nil
        }
    }

    public func deriveDataStreamKeys(streamConnectionID: UInt64) -> (output: Data, input: Data)? {
        queue.sync {
            guard let session = completedVerifySession, let derive = deriveKeyFn else {
                NSLog("[DrivingMode][Pairing] Cannot derive DataStream keys: verifySession=%d deriveFn=%d", completedVerifySession != nil ? 1 : 0, deriveKeyFn != nil ? 1 : 0)
                return nil
            }
            let salt = Array("DataStream-Salt\(streamConnectionID)".utf8)
            func key(_ info: String) -> Data? {
                var out = Data(count: 32)
                let inf = Array(info.utf8)
                let st = out.withUnsafeMutableBytes { derive(session, salt, salt.count, inf, inf.count, 32, $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
                return st == 0 ? out : nil
            }
            guard let o = key("DataStream-Output-Encryption-Key"), let i = key("DataStream-Input-Encryption-Key") else { return nil }
            NSLog("[DrivingMode][Pairing] Derived DataStream keys for streamConnectionID=%llu", streamConnectionID)
            return (o, i)
        }
    }

    /// Derives the per-event ChaCha20-Poly1305 keys (CarCast @ 0x10052ec04):
    /// salt = "Events-Salt", read info = "Events-Read-Encryption-Key", write info = "Events-Write-Encryption-Key".
    public func deriveEventsKeys() -> (decrypt: Data, encrypt: Data)? {
        queue.sync {
            guard let session = completedVerifySession, let derive = deriveKeyFn else {
                NSLog("[DrivingMode][Pairing] Cannot derive Events keys: verifySession=%d deriveFn=%d", completedVerifySession != nil ? 1 : 0, deriveKeyFn != nil ? 1 : 0)
                return nil
            }
            let salt = Array("Events-Salt".utf8)
            func key(_ info: String) -> Data? {
                var out = Data(count: 32)
                let inf = Array(info.utf8)
                let st = out.withUnsafeMutableBytes { derive(session, salt, salt.count, inf, inf.count, 32, $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
                return st == 0 ? out : nil
            }
            guard let r = key("Events-Read-Encryption-Key"), let w = key("Events-Write-Encryption-Key") else {
                NSLog("[DrivingMode][Pairing] Failed to derive Events keys")
                return nil
            }
            NSLog("[DrivingMode][Pairing] Derived Events channel keys (ChaCha20-Poly1305)")
            return (decrypt: r, encrypt: w)
        }
    }

    /// Returns (and clears) the control-channel keys derived by the last completed pair-verify.
    public func takeControlKeys() -> (decrypt: Data, encrypt: Data)? {
        queue.sync {
            defer { pendingControlKeys = nil }
            return pendingControlKeys
        }
    }

    private var setupSession: UnsafeMutableRawPointer?
    private var verifySession: UnsafeMutableRawPointer?
    private let queue = DispatchQueue(label: "dev.unordinarylabs.carplay.pairing", qos: .userInteractive)

    // MARK: - PairingDelegate (CoreUtils)
    //
    // Verified against CoreUtils (_PairingSessionCreate @ dyld cache): the delegate is 9 pointers (0x48 bytes) copied to
    // session+0x18: [0] context, [1] showSetupCode_f, [2] hideSetupCode_f, [3] promptForSetupCode_f,
    // [4] copyIdentity_f (+0x38), [5] findPeer_f (+0x40), [6] savePeer_f (+0x48), [7..8] reserved.
    // With NULL callbacks CoreUtils falls back to _PairingSessionCopyIdentity/_PairingSessionSavePeerKeychain against
    // Apple's private pairing keychain group, which a sandboxed app can't access -> pair-setup M5 fails with
    // kTLVError_Unknown (t7=01). Supplying our own identity + peer store fixes M5/M6 and pair-verify.
    private typealias CopyIdentityFn = @convention(c) (UInt8, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutableRawPointer?) -> Int32
    private typealias FindPeerFn = @convention(c) (UnsafeRawPointer?, Int, UnsafeMutablePointer<UInt8>?, UnsafeMutableRawPointer?) -> Int32
    private typealias SavePeerFn = @convention(c) (UnsafeRawPointer?, Int, UnsafePointer<UInt8>?, UnsafeMutableRawPointer?) -> Int32

    private static let identityKeyDefaultsKey = "drivingmode.pairing.ed25519.sk"
    private static let peersDefaultsKey = "drivingmode.pairing.peers"

    private static var accessoryIdentifier: String {
        UserDefaults.standard.string(forKey: "drivingmode.device.id") ?? "02:55:4E:44:52:56"
    }

    private static func loadOrCreateIdentity() -> Curve25519.Signing.PrivateKey {
        if let raw = UserDefaults.standard.data(forKey: identityKeyDefaultsKey),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            return key
        }
        let key = Curve25519.Signing.PrivateKey()
        UserDefaults.standard.set(key.rawRepresentation, forKey: identityKeyDefaultsKey)
        NSLog("[DrivingMode][Pairing] Created new Ed25519 accessory identity")
        return key
    }

    private static let copyIdentityCallback: CopyIdentityFn = { _, outIdentifier, outPK, outSK, _ in
        let key = HomeKitPairingService.loadOrCreateIdentity()
        let ident = HomeKitPairingService.accessoryIdentifier
        if let outIdentifier = outIdentifier { outIdentifier.pointee = strdup(ident) }
        if let outPK = outPK { key.publicKey.rawRepresentation.copyBytes(to: outPK, count: 32) }
        if let outSK = outSK { key.rawRepresentation.copyBytes(to: outSK, count: 32) }
        NSLog("[DrivingMode][Pairing] copyIdentity -> id=%@ pk=%@", ident, key.publicKey.rawRepresentation.prefix(4).map { String(format: "%02X", $0) }.joined())
        return 0
    }

    private static func peerKey(_ ptr: UnsafeRawPointer?, _ len: Int) -> String {
        guard let ptr = ptr else { return "" }
        let n = (len == -1) ? strlen(ptr.assumingMemoryBound(to: CChar.self)) : len
        return String(decoding: UnsafeRawBufferPointer(start: ptr, count: n), as: UTF8.self)
    }

    private static let findPeerCallback: FindPeerFn = { idPtr, idLen, outPK, _ in
        let id = HomeKitPairingService.peerKey(idPtr, idLen)
        let peers = UserDefaults.standard.dictionary(forKey: HomeKitPairingService.peersDefaultsKey) as? [String: Data] ?? [:]
        guard let pk = peers[id], pk.count == 32 else {
            NSLog("[DrivingMode][Pairing] findPeer id=%@ -> NOT FOUND (%d known peers)", id, peers.count)
            return -6727 // kNotFoundErr
        }
        if let outPK = outPK { pk.copyBytes(to: outPK, count: 32) }
        NSLog("[DrivingMode][Pairing] findPeer id=%@ -> found", id)
        return 0
    }

    private static let savePeerCallback: SavePeerFn = { idPtr, idLen, pkPtr, _ in
        let id = HomeKitPairingService.peerKey(idPtr, idLen)
        guard let pkPtr = pkPtr else { return -6705 } // kParamErr
        var peers = UserDefaults.standard.dictionary(forKey: HomeKitPairingService.peersDefaultsKey) as? [String: Data] ?? [:]
        peers[id] = Data(bytes: pkPtr, count: 32)
        UserDefaults.standard.set(peers, forKey: HomeKitPairingService.peersDefaultsKey)
        NSLog("[DrivingMode][Pairing] savePeer id=%@ (now %d peers)", id, peers.count)
        return 0
    }

    /// Stable 9-pointer delegate struct passed to every PairingSessionCreate call.
    private static let pairingDelegate: UnsafeMutablePointer<UnsafeRawPointer?> = {
        let p = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 9)
        p.initialize(repeating: nil, count: 9)
        p[4] = unsafeBitCast(copyIdentityCallback, to: UnsafeRawPointer.self)
        p[5] = unsafeBitCast(findPeerCallback, to: UnsafeRawPointer.self)
        p[6] = unsafeBitCast(savePeerCallback, to: UnsafeRawPointer.self)
        return p
    }()

    private init() {
        self.mfiCertData = HomeKitPairingService.hexToData(mfiCertHex)
        self.mfiSecKey = HomeKitPairingService.createSecKey(scalarHex: mfiScalarHex)

        // Dynamically resolve CoreUtils
        if let handle = dlopen("/System/Library/PrivateFrameworks/CoreUtils.framework/CoreUtils", RTLD_NOW) {
            if let ptr = dlsym(handle, "PairingSessionCreate") {
                createFn = unsafeBitCast(ptr, to: PairingSessionCreateFunc.self)
            }
            if let ptr = dlsym(handle, "PairingSessionSetSetupCode") {
                setCodeFn = unsafeBitCast(ptr, to: PairingSessionSetSetupCodeFunc.self)
            }
            if let ptr = dlsym(handle, "PairingSessionExchange") {
                exchangeFn = unsafeBitCast(ptr, to: PairingSessionExchangeFunc.self)
            }
            if let ptr = dlsym(handle, "PairingSessionDelete") {
                deleteFn = unsafeBitCast(ptr, to: PairingSessionDeleteFunc.self)
            }
            if let ptr = dlsym(handle, "PairingSessionDeriveKey") {
                deriveKeyFn = unsafeBitCast(ptr, to: PairingSessionDeriveKeyFunc.self)
            }
            print("[HomeKitPairingService] CoreUtils dynamic binding initialized")
        } else {
            print("[HomeKitPairingService] Warning: Failed to dlopen CoreUtils")
        }
    }

    public func reset() {
        queue.sync {
            if let s = setupSession {
                if let del = deleteFn {
                    del(s)
                } else {
                    Unmanaged<AnyObject>.fromOpaque(s).release()
                }
                setupSession = nil
            }
            if let v = verifySession {
                if let del = deleteFn {
                    del(v)
                } else {
                    Unmanaged<AnyObject>.fromOpaque(v).release()
                }
                verifySession = nil
            }
        }
    }

    // MARK: - POST /pair-setup
    public func exchangePairSetup(data: Data, pin: String = "3939") -> (response: Data?, hkpState: Int?) {
        return queue.sync {
            guard let create = createFn, let setCode = setCodeFn, let exchange = exchangeFn else {
                print("[HomeKitPairingService] CoreUtils functions unavailable for pair-setup")
                return (nil, nil)
            }

            if setupSession == nil {
                var s: UnsafeMutableRawPointer?
                // 2 = Server / Accessory Mode
                let err = create(&s, UnsafeRawPointer(HomeKitPairingService.pairingDelegate), 2)
                guard err == 0, let validSession = s else {
                    print("[HomeKitPairingService] Failed to create pair-setup session: \(err)")
                    return (nil, nil)
                }
                setupSession = validSession
                _ = pin.withCString { cstr in
                    setCode(validSession, cstr, pin.utf8.count)
                }
            }

            guard let session = setupSession else { return (nil, nil) }

            var outPtr: UnsafeMutableRawPointer?
            var outLen: Int = 0
            var outDone: UInt8 = 0

            let err = data.withUnsafeBytes { inPtr in
                exchange(session, inPtr.baseAddress, data.count, &outPtr, &outLen, &outDone)
            }

            guard err == 0, let out = outPtr, outLen > 0 else {
                NSLog("[DrivingMode][Pairing] pair-setup exchange failed: OSStatus %d", Int32(err))
                return (nil, nil)
            }

            let respData = Data(bytes: out, count: outLen)

            // Diagnostics: decode TLV8 types (6=State, 7=Error, 5=EncryptedData, 3=PublicKey, 4=Proof, 2=Salt, 19=Flags)
            func tlvSummary(_ d: Data) -> String {
                var parts: [String] = []
                var i = d.startIndex
                while i + 1 < d.endIndex {
                    let t = d[i], l = Int(d[i + 1])
                    let end = min(i + 2 + l, d.endIndex)
                    let v = d[(i + 2)..<end]
                    parts.append(l <= 4 ? "t\(t)=\(v.map { String(format: "%02X", $0) }.joined())" : "t\(t)[\(l)]")
                    i = end
                }
                return parts.joined(separator: " ")
            }
            NSLog("[DrivingMode][PairSetup] RX %d bytes: %@ -> TX %d bytes: %@ (done=%d)", data.count, tlvSummary(data), respData.count, tlvSummary(respData), outDone)

            // Extract HKP state from TLV8 if present (type 6)
            var hkpState: Int? = nil
            if respData.count >= 3 && respData[0] == 0x06 && respData[1] == 0x01 {
                hkpState = Int(respData[2])
            }

            if outDone != 0 {
                print("[HomeKitPairingService] pair-setup complete, releasing session")
                if let del = deleteFn {
                    del(session)
                } else {
                    Unmanaged<AnyObject>.fromOpaque(session).release()
                }
                setupSession = nil
            }

            return (respData, hkpState)
        }
    }

    // MARK: - POST /pair-verify
    public func exchangePairVerify(data: Data) -> Data? {
        return queue.sync {
            guard let create = createFn, let exchange = exchangeFn else {
                print("[HomeKitPairingService] CoreUtils functions unavailable for pair-verify")
                return nil
            }

            if verifySession == nil {
                var s: UnsafeMutableRawPointer?
                // 4 = Pair-Verify Server Mode
                let err = create(&s, UnsafeRawPointer(HomeKitPairingService.pairingDelegate), 4)
                guard err == 0, let validSession = s else {
                    print("[HomeKitPairingService] Failed to create pair-verify session: \(err)")
                    return nil
                }
                verifySession = validSession
            }

            guard let session = verifySession else { return nil }

            var outPtr: UnsafeMutableRawPointer?
            var outLen: Int = 0
            var outDone: UInt8 = 0

            let err = data.withUnsafeBytes { inPtr in
                exchange(session, inPtr.baseAddress, data.count, &outPtr, &outLen, &outDone)
            }

            guard err == 0, let out = outPtr, outLen > 0 else {
                NSLog("[DrivingMode][Pairing] pair-verify exchange failed: OSStatus %d", Int32(err))
                return nil
            }

            let respData = Data(bytes: out, count: outLen)

            // Diagnostics: decode TLV8 types (6=State, 7=Error, 5=EncryptedData, 3=PublicKey, 4=Proof, 2=Salt, 19=Flags)
            func tlvSummary(_ d: Data) -> String {
                var parts: [String] = []
                var i = d.startIndex
                while i + 1 < d.endIndex {
                    let t = d[i], l = Int(d[i + 1])
                    let end = min(i + 2 + l, d.endIndex)
                    let v = d[(i + 2)..<end]
                    parts.append(l <= 4 ? "t\(t)=\(v.map { String(format: "%02X", $0) }.joined())" : "t\(t)[\(l)]")
                    i = end
                }
                return parts.joined(separator: " ")
            }
            NSLog("[DrivingMode][PairVerify] RX %d bytes: %@ -> TX %d bytes: %@ (done=%d)", data.count, tlvSummary(data), respData.count, tlvSummary(respData), outDone)

            if outDone != 0 {
                // Derive the encrypted-control-channel keys before releasing the verify session.
                // Accessory side: decrypt controller->accessory with "Control-Write-Encryption-Key",
                // encrypt accessory->controller with "Control-Read-Encryption-Key" (salt "Control-Salt").
                if let derive = deriveKeyFn {
                    func deriveKey(_ info: String) -> Data? {
                        var key = Data(count: 32)
                        let salt = Array("Control-Salt".utf8), inf = Array(info.utf8)
                        let st = key.withUnsafeMutableBytes { k in
                            derive(session, salt, salt.count, inf, inf.count, 32, k.baseAddress!.assumingMemoryBound(to: UInt8.self))
                        }
                        if st != 0 { NSLog("[DrivingMode][Pairing] PairingSessionDeriveKey(%@) failed: %d", info, st) }
                        return st == 0 ? key : nil
                    }
                    if let w = deriveKey("Control-Write-Encryption-Key"), let r = deriveKey("Control-Read-Encryption-Key") {
                        pendingControlKeys = (decrypt: w, encrypt: r)
                        NSLog("[DrivingMode][Pairing] Derived control channel keys (ChaCha20-Poly1305)")
                    }
                } else {
                    NSLog("[DrivingMode][Pairing] PairingSessionDeriveKey unavailable — cannot encrypt control channel")
                }
                // Keep the completed verify session: per-stream keys (DataStream-Salt<streamConnectionID>) are derived
                // from it later when the screen/audio streams are SETUP.
                if let old = completedVerifySession, let del = deleteFn { del(old) }
                completedVerifySession = session
                verifySession = nil
                NSLog("[DrivingMode][Pairing] pair-verify complete; retaining session for stream key derivation")
            }

            return respData
        }
    }

    // MARK: - POST /auth-setup (MFiSAP)
    public func exchangeAuthSetup(data: Data) -> Data? {
        guard data.count >= 33, data[0] == 0x01 else {
            print("[HomeKitPairingService] Invalid auth-setup request length: \(data.count)")
            return nil
        }

        let clientPubBytes = data.subdata(in: 1..<33)
        guard let clientPub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientPubBytes) else {
            print("[HomeKitPairingService] Failed to parse client Curve25519 public key")
            return nil
        }

        let serverPriv = Curve25519.KeyAgreement.PrivateKey()
        let serverPubBytes = serverPriv.publicKey.rawRepresentation

        guard let sharedSecret = try? serverPriv.sharedSecretFromKeyAgreement(with: clientPub) else {
            print("[HomeKitPairingService] Failed to compute ECDH shared secret")
            return nil
        }

        var hashInput = Data(serverPubBytes)
        hashInput.append(clientPubBytes)
        let sha256Digest = SHA256.hash(data: hashInput)
        let sha256Data = Data(sha256Digest)

        guard let secKey = mfiSecKey else {
            print("[HomeKitPairingService] MFi SecKey unavailable")
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let rawSig = SecKeyCreateSignature(secKey, .ecdsaSignatureDigestRFC4754, sha256Data as CFData, &error) as Data? else {
            print("[HomeKitPairingService] Failed to sign digest: \(String(describing: error?.takeRetainedValue()))")
            return nil
        }

        // Verified against CoreUtils MFiSAP_Exchange (client side, which the iPhone runs):
        //   key = SHA1("AES-KEY" || sharedSecret)[0..<16], iv = SHA1("AES-IV" || sharedSecret)[0..<16], AES-128-CTR.
        //   Signature check: MFiPlatform_VerifySignatureEx -> SHA256(serverPub || clientPub) with
        //   kSecKeyAlgorithmECDSASignatureDigestRFC4754 (raw 64-byte r||s); SHA1/RSA only when sigLen == 128.
        let shared = sharedSecret.withUnsafeBytes { Data($0) }
        func sha1Prefix(_ label: String) -> Data {
            var input = Data(label.utf8)
            input.append(shared)
            return Data(Insecure.SHA1.hash(data: input)).prefix(16)
        }
        let keyData = sha1Prefix("AES-KEY")
        let ivData = sha1Prefix("AES-IV")

        var cryptor: CCCryptorRef?

        let status = keyData.withUnsafeBytes { kPtr in
            ivData.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivPtr.baseAddress,
                    kPtr.baseAddress,
                    16,
                    nil, 0, 0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }

        guard status == 0, let c = cryptor else {
            print("[HomeKitPairingService] Failed to create AES-128-CTR cryptor: \(status)")
            return nil
        }

        var encSig = Data(count: 64)
        var outLen = 0
        let updateStatus = encSig.withUnsafeMutableBytes { outPtr in
            rawSig.withUnsafeBytes { inPtr in
                CCCryptorUpdate(c, inPtr.baseAddress, 64, outPtr.baseAddress, 64, &outLen)
            }
        }
        CCCryptorRelease(c)

        guard updateStatus == 0, outLen == 64 else {
            print("[HomeKitPairingService] AES-128-CTR encryption failed: \(updateStatus)")
            return nil
        }

        var response = Data()
        // 1. Server Curve25519 Pubkey (32 bytes)
        response.append(serverPubBytes)

        // 2. Big-endian UInt32 certificate length
        var cLen = UInt32(mfiCertData.count).bigEndian
        response.append(Data(bytes: &cLen, count: 4))

        // 3. DER Certificate (607 bytes)
        response.append(mfiCertData)

        // 4. Big-endian UInt32 signature length
        var sLen = UInt32(encSig.count).bigEndian
        response.append(Data(bytes: &sLen, count: 4))

        // 5. Encrypted signature (64 bytes)
        response.append(encSig)

        NSLog("[DrivingMode][AuthSetup] MFi-SAP reply: serverPub=32 cert=%d sig=%d (SHA1 AES key/iv, SHA256+RFC4754 ECDSA)", mfiCertData.count, encSig.count)
        guard response.count == 711 else {
            print("[HomeKitPairingService] Warning: AuthSetup response size is \(response.count) instead of 711")
            return response
        }

        return response
    }

    // MARK: - Helpers
    private static func hexToData(_ hex: String) -> Data {
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let nextIdx = hex.index(idx, offsetBy: 2)
            if let byte = UInt8(hex[idx..<nextIdx], radix: 16) {
                data.append(byte)
            }
            idx = nextIdx
        }
        return data
    }

    private static func createSecKey(scalarHex: String) -> SecKey? {
        let scalarData = hexToData(scalarHex)
        guard let p256Key = try? P256.Signing.PrivateKey(rawRepresentation: scalarData) else {
            print("[HomeKitPairingService] Failed to parse P256 key from scalar")
            return nil
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(p256Key.x963Representation as CFData, attributes as CFDictionary, &error) else {
            print("[HomeKitPairingService] SecKeyCreateWithData failed: \(String(describing: error?.takeRetainedValue()))")
            return nil
        }
        return secKey
    }
}
