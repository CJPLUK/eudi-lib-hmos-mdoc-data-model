/*
 * device_engagement.cj
 *
 * Device Engagement structures for ISO 18013-5 mDoc engagement protocol.
 *
 * Covers: CoseEcCurve, CoseKey, CoseKeyPrivate, CoseKeyExchange,
 *         Security, DeviceRetrievalMethod, ConnectionMethodHttp,
 *         ServerRetrievalOption, ServerRetrievalOptions,
 *         OriginInfoWebsite, DeviceEngagement
 *
 * QR encoding:  "mdoc:" + base64url(CBOR(DeviceEngagement))
 *
 * iOS references:
 *   Sources/MdocDataModel18013/DeviceEngagement/DeviceEngagement.swift
 *   Sources/MdocDataModel18013/DeviceEngagement/CoseKey.swift
 *   Sources/MdocDataModel18013/DeviceEngagement/Security.swift
 *   Sources/MdocDataModel18013/DeviceEngagement/DeviceRetrievalMethod.swift
 *   Sources/MdocDataModel18013/DeviceEngagement/ConnectionMethodHttp.swift
 *   Sources/MdocDataModel18013/DeviceEngagement/ServerRetrievalOption.swift
 *   Sources/MdocDataModel18013/DeviceEngagement/ServerRetrievalOptions.swift
 *   Sources/MdocDataModel18013/DeviceEngagement/OriginInfoWebsite.swift
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.engagement

import std.collection.ArrayList
import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.CborTag
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor
import ohos_app_cangjie_eudi_cjcbor.cbor.encodeEmbedded
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeEmbedded
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MdocValidationError
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.Base64UrlHelper
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CBOREncodable

/* ==================================================================== */
/* CoseEcCurve — minimal set needed for engagement (EC key curves)       */
/* ==================================================================== */

/**
 * EC curve identifiers as COSE integer values (RFC 8152 Table 22).
 * Only the three P-curves needed by ISO 18013-5 are defined here.
 * Full curve set (incl. Ed25519) lives in mdoc_securearea once that
 * feature lands; supervisor will coordinate cross-feature sharing.
 */
public enum CoseEcCurve {
    | P256   // COSE value 1
    | P384   // COSE value 2
    | P521   // COSE value 3

    /** COSE integer encoding of this curve. */
    public func rawValue(): UInt64 {
        match (this) {
            case P256 => return UInt64(1)
            case P384 => return UInt64(2)
            case P521 => return UInt64(3)
        }
    }

    /** Try to construct from a COSE integer. Returns None for unsupported values. */
    public static func fromRaw(raw: UInt64): ?CoseEcCurve {
        match (raw) {
            case 1 => return Some(P256)
            case 2 => return Some(P384)
            case 3 => return Some(P521)
            case _ => return None
        }
    }
}

/* ==================================================================== */
/* CoseKey — COSE_Key map (RFC 8152, kty=2 EC2)                         */
/* ==================================================================== */

/**
 * Public EC key in COSE_Key map format.
 *
 * CBOR map keys (negative/positive integers per RFC 8152 Table 23):
 *   kty  (+1) : UInt = 2 (EC2)
 *   crv  (-1) : UInt = curve id
 *   x    (-2) : bstr
 *   y    (-3) : bstr
 *
 * iOS reference: CoseKey.swift
 */
public class CoseKey <: CBOREncodable {
    /** EC curve identifier. */
    public let crv: CoseEcCurve
    /** Key type (always 2 = EC2). */
    public let kty: UInt64
    /** x-coordinate bytes. */
    public let x: Array<UInt8>
    /** y-coordinate bytes. */
    public let y: Array<UInt8>

    public init(crv: CoseEcCurve, x: Array<UInt8>, y: Array<UInt8>) {
        this.crv = crv
        this.kty = UInt64(2)
        this.x = x
        this.y = y
    }

    /** Full constructor (kty explicit, for round-trip fidelity). */
    public init(crv: CoseEcCurve, kty: UInt64, x: Array<UInt8>, y: Array<UInt8>) {
        this.crv = crv
        this.kty = kty
        this.x = x
        this.y = y
    }

    /**
     * Encode as COSE_Key map (untagged).
     * Map keys as signed COSE integers:
     *   +1 -> kty,  -1 -> crv,  -2 -> x,  -3 -> y
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        // kty = +1
        pairs.add((CborValue.UInt64Val(UInt64(1)), CborValue.UInt64Val(kty)))
        // crv = -1  (NInt64Val: value n encodes as -1-n, so crv rawValue encodes as -1-(rawValue) ... wait:
        // COSE integer -1 means: NInt64Val(0) since -1 = -1 - 0
        // COSE integer -2 means: NInt64Val(1) since -2 = -1 - 1
        // COSE integer -3 means: NInt64Val(2) since -3 = -1 - 2
        pairs.add((CborValue.NInt64Val(UInt64(0)), CborValue.UInt64Val(crv.rawValue())))
        // x = -2
        pairs.add((CborValue.NInt64Val(UInt64(1)), CborValue.ByteStringVal(x)))
        // y = -3
        pairs.add((CborValue.NInt64Val(UInt64(2)), CborValue.ByteStringVal(y)))
        return CborValue.MapVal(pairs)
    }

    /**
     * Encode as tag-24 embedded CBOR (the "tagged" form used in Security struct).
     * iOS: deviceKey.taggedEncoded  where taggedEncoded wraps in tag 24.
     */
    public func toTaggedEncoded(): CborValue {
        return encodeEmbedded(this.toCbor())
    }

    /**
     * Decode a CoseKey from an untagged CBOR map.
     * Throws MdocValidationError on malformed input.
     */
    public static func fromCborMap(cbor: CborValue): CoseKey {
        let crvField = cbor.field(CborValue.NInt64Val(UInt64(0)))
        let crvRaw: UInt64 = match (crvField) {
            case Some(CborValue.UInt64Val(n)) => n
            case _ => throw MdocValidationError.invalidCbor("COSE key crv")
        }
        let crvOpt = CoseEcCurve.fromRaw(crvRaw)
        let crv: CoseEcCurve = match (crvOpt) {
            case Some(c) => c
            case None => throw MdocValidationError.invalidCbor("COSE key: unsupported curve")
        }
        let ktyField = cbor.field(CborValue.UInt64Val(UInt64(1)))
        let kty: UInt64 = match (ktyField) {
            case Some(CborValue.UInt64Val(n)) => n
            case _ => throw MdocValidationError.missingField("CoseKey", "kty")
        }
        let xField = cbor.field(CborValue.NInt64Val(UInt64(1)))
        let x: Array<UInt8> = match (xField) {
            case Some(CborValue.ByteStringVal(b)) => b
            case _ => throw MdocValidationError.missingField("CoseKey", "x")
        }
        let yField = cbor.field(CborValue.NInt64Val(UInt64(2)))
        let y: Array<UInt8> = match (yField) {
            case Some(CborValue.ByteStringVal(b)) => b
            case _ => throw MdocValidationError.missingField("CoseKey", "y")
        }
        return CoseKey(crv, kty, x, y)
    }

    /**
     * Decode from a tag-24 embedded CBOR value (the form used in Security).
     */
    public static func fromTaggedEncoded(tagged: CborValue): CoseKey {
        let inner: CborValue
        try {
            inner = decodeEmbedded(tagged)
        } catch (e: Exception) {
            throw MdocValidationError.invalidCbor("COSE key: " + e.message)
        }
        return CoseKey.fromCborMap(inner)
    }
}

/* ==================================================================== */
/* CoseKeyPrivate — public key reference with private key bookkeeping    */
/* ==================================================================== */

/**
 * Holds a CoseKey plus an opaque private-key identifier.
 * In engagement, this is the ephemeral device key pair.
 * The actual private key material is NOT encoded in CBOR (only the public key
 * goes on the wire in Security); this struct is holder-only.
 *
 * iOS reference: CoseKeyPrivate.swift
 */
public class CoseKeyPrivate {
    /** The public COSE key (lazily populated). */
    public var publicKey: ?CoseKey
    /** Opaque identifier for the private key in a secure store. */
    public let privateKeyId: String
    /** Curve type used for this key pair. */
    public let curve: CoseEcCurve

    public init(publicKey: ?CoseKey, privateKeyId: String, curve: CoseEcCurve) {
        this.publicKey = publicKey
        this.privateKeyId = privateKeyId
        this.curve = curve
    }

    /**
     * Construct with a known public key (e.g. after key generation).
     */
    public static func withPublicKey(key: CoseKey, id: String): CoseKeyPrivate {
        return CoseKeyPrivate(Some(key), id, key.crv)
    }
}

/* ==================================================================== */
/* CoseKeyExchange — ephemeral key exchange pair                         */
/* ==================================================================== */

/**
 * A COSE_Key exchange pair: remote public key + local private key.
 * Used during ECDH key agreement in the engagement protocol.
 *
 * iOS reference: CoseKeyExchange.swift
 */
public class CoseKeyExchange {
    public let publicKey: ?CoseKey
    public let privateKey: CoseKeyPrivate

    public init(publicKey: ?CoseKey, privateKey: CoseKeyPrivate) {
        this.publicKey = publicKey
        this.privateKey = privateKey
    }
}

/* ==================================================================== */
/* Security — [cipherSuiteId, EDeviceKeyBytes]                           */
/* ==================================================================== */

/**
 * Security structure in DeviceEngagement.
 *
 * Wire: array [1, tag-24(CoseKey-bstr)]
 *   element 0: cipher suite identifier (always 1 per ISO 18013-5)
 *   element 1: tag-24 embedded CBOR of the public device key (CoseKey map)
 *
 * iOS reference: Security.swift
 */
public class Security <: CBOREncodable {
    static let CIPHER_SUITE_ID: UInt64 = 1

    /** The device public key (EDeviceKey). */
    public let deviceKey: CoseKey

    public init(deviceKey: CoseKey) {
        this.deviceKey = deviceKey
    }

    /** Encode as [1, tag-24(CoseKey)]. */
    public func toCbor(): CborValue {
        let items = ArrayList<CborValue>()
        items.add(CborValue.UInt64Val(Security.CIPHER_SUITE_ID))
        items.add(deviceKey.toTaggedEncoded())
        return CborValue.ArrayVal(items)
    }

    /** Decode from CBOR array [cipherSuiteId, EDeviceKeyBytes]. */
    public static func fromCbor(cbor: CborValue): Security {
        let items: ArrayList<CborValue> = match (cbor) {
            case CborValue.ArrayVal(arr) => arr
            case _ => throw MdocValidationError.invalidCbor("security")
        }
        if (items.size < 2) {
            throw MdocValidationError.invalidCbor("security")
        }
        let suiteId: UInt64 = match (items[0]) {
            case CborValue.UInt64Val(n) => n
            case _ => throw MdocValidationError.invalidCbor("security")
        }
        if (suiteId != Security.CIPHER_SUITE_ID) {
            throw MdocValidationError.invalidCbor("security: unsupported cipher suite")
        }
        let key = CoseKey.fromTaggedEncoded(items[1])
        return Security(key)
    }
}

/* ==================================================================== */
/* DeviceRetrievalMethod — NFC / BLE retrieval method                    */
/* ==================================================================== */

/**
 * Constants for DeviceRetrievalMethod CBOR encoding.
 * (Extracted from enum because Cangjie enums cannot hold static let fields.)
 */
class DeviceRetrievalMethodConst {
    static let VERSION: UInt64 = 1
    static let TYPE_NFC: UInt64 = 1
    static let TYPE_BLE: UInt64 = 2
}

/**
 * Device retrieval method descriptor.
 *
 * Wire: array [type: UInt, version: UInt, options: map]
 *   type 1 = NFC, type 2 = BLE
 *   version is always 1 per ISO 18013-5
 *
 * iOS reference: DeviceRetrievalMethod.swift
 */
public enum DeviceRetrievalMethod {
    | Nfc(UInt64, UInt64)          // (maxLenCommand, maxLenResponse)
    | Ble(Bool, Array<UInt8>, ?UInt16)  // (peripheralServerMode, uuidBytes, psm?)

    /** Encode as [type, version, options-map]. */
    public func toCbor(): CborValue {
        let arr = ArrayList<CborValue>()
        match (this) {
            case Nfc(maxLenCmd, maxLenResp) =>
                arr.add(CborValue.UInt64Val(DeviceRetrievalMethodConst.TYPE_NFC))
                arr.add(CborValue.UInt64Val(DeviceRetrievalMethodConst.VERSION))
                let opts = ArrayList<(CborValue, CborValue)>()
                opts.add((CborValue.UInt64Val(UInt64(0)), CborValue.UInt64Val(maxLenCmd)))
                opts.add((CborValue.UInt64Val(UInt64(1)), CborValue.UInt64Val(maxLenResp)))
                arr.add(CborValue.MapVal(opts))
            case Ble(isPeripheralServer, uuidBytes, psmOpt) =>
                arr.add(CborValue.UInt64Val(DeviceRetrievalMethodConst.TYPE_BLE))
                arr.add(CborValue.UInt64Val(DeviceRetrievalMethodConst.VERSION))
                let opts = ArrayList<(CborValue, CborValue)>()
                opts.add((CborValue.UInt64Val(UInt64(0)), CborValue.BoolVal(isPeripheralServer)))
                opts.add((CborValue.UInt64Val(UInt64(1)), CborValue.BoolVal(!isPeripheralServer)))
                // peripheral server mode uses key 10; central client mode uses key 11
                let uuidKey: UInt64 = if (isPeripheralServer) { UInt64(10) } else { UInt64(11) }
                opts.add((CborValue.UInt64Val(uuidKey), CborValue.ByteStringVal(uuidBytes)))
                match (psmOpt) {
                    case Some(psm) =>
                        opts.add((CborValue.UInt64Val(UInt64(21)), CborValue.UInt64Val(UInt64(psm))))
                    case None => ()
                }
                arr.add(CborValue.MapVal(opts))
        }
        return CborValue.ArrayVal(arr)
    }

    /** Decode from CBOR array [type, version, options]. */
    public static func fromCbor(cbor: CborValue): DeviceRetrievalMethod {
        let items: ArrayList<CborValue> = match (cbor) {
            case CborValue.ArrayVal(arr) => arr
            case _ => throw MdocValidationError.invalidCbor("device retrieval method")
        }
        if (items.size < 2) {
            throw MdocValidationError.invalidCbor("device retrieval method")
        }
        let methodType: UInt64 = match (items[0]) {
            case CborValue.UInt64Val(n) => n
            case _ => throw MdocValidationError.invalidCbor("device retrieval method")
        }
        let methodVersion: UInt64 = match (items[1]) {
            case CborValue.UInt64Val(n) => n
            case _ => throw MdocValidationError.invalidCbor("device retrieval method")
        }
        if (methodVersion != DeviceRetrievalMethodConst.VERSION) {
            throw MdocValidationError.invalidCbor("device retrieval method: unsupported version")
        }
        if (items.size < 3) {
            throw MdocValidationError.invalidCbor("device retrieval method: missing options")
        }
        match (methodType) {
            case 1 =>
                // NFC
                let maxCmd: UInt64 = match (items[2].field(CborValue.UInt64Val(UInt64(0)))) {
                    case Some(CborValue.UInt64Val(n)) => n
                    case _ => throw MdocValidationError.invalidCbor("device retrieval method: NFC maxLenCommand")
                }
                let maxResp: UInt64 = match (items[2].field(CborValue.UInt64Val(UInt64(1)))) {
                    case Some(CborValue.UInt64Val(n)) => n
                    case _ => throw MdocValidationError.invalidCbor("device retrieval method: NFC maxLenResponse")
                }
                return DeviceRetrievalMethod.Nfc(maxCmd, maxResp)
            case 2 =>
                // BLE
                let psm: ?UInt16 = match (items[2].field(CborValue.UInt64Val(UInt64(21)))) {
                    case Some(CborValue.UInt64Val(n)) => Some(UInt16(n))
                    case _ => None
                }
                // peripheral server mode: options[0] = true
                let isPeripheral: Bool = match (items[2].field(CborValue.UInt64Val(UInt64(0)))) {
                    case Some(CborValue.BoolVal(b)) => b
                    case _ => false
                }
                let uuidKey: UInt64 = if (isPeripheral) { UInt64(10) } else { UInt64(11) }
                let uuidBytes: Array<UInt8> = match (items[2].field(CborValue.UInt64Val(uuidKey))) {
                    case Some(CborValue.ByteStringVal(b)) => b
                    case _ => throw MdocValidationError.invalidCbor("device retrieval method: BLE UUID missing")
                }
                if (uuidBytes.size != 16) {
                    throw MdocValidationError.invalidCbor("device retrieval method: BLE UUID must be 16 bytes")
                }
                return DeviceRetrievalMethod.Ble(isPeripheral, uuidBytes, psm)
            case _ =>
                throw MdocValidationError.invalidCbor("device retrieval method: unknown type")
        }
    }
}

/* ==================================================================== */
/* ConnectionMethodHttp — REST API retrieval method (type 4)             */
/* ==================================================================== */

/**
 * HTTP connection method for server-side retrieval.
 *
 * Wire: array [4, 1, {0: uriWebsite}]
 *
 * iOS reference: ConnectionMethodHttp.swift
 */
public class ConnectionMethodHttp <: CBOREncodable {
    static let METHOD_TYPE: UInt64 = 4
    static let METHOD_MAX_VERSION: UInt64 = 1
    static let OPTION_KEY_URI_WEBSITE: UInt64 = 0

    public let uriWebsite: String

    public init(uriWebsite: String) {
        this.uriWebsite = uriWebsite
    }

    public func toCbor(): CborValue {
        let opts = ArrayList<(CborValue, CborValue)>()
        opts.add((CborValue.UInt64Val(ConnectionMethodHttp.OPTION_KEY_URI_WEBSITE),
                  CborValue.TextStringVal(uriWebsite)))
        let items = ArrayList<CborValue>()
        items.add(CborValue.UInt64Val(ConnectionMethodHttp.METHOD_TYPE))
        items.add(CborValue.UInt64Val(ConnectionMethodHttp.METHOD_MAX_VERSION))
        items.add(CborValue.MapVal(opts))
        return CborValue.ArrayVal(items)
    }

    public static func fromCbor(cbor: CborValue): ConnectionMethodHttp {
        let items: ArrayList<CborValue> = match (cbor) {
            case CborValue.ArrayVal(arr) => arr
            case _ => throw MdocValidationError.invalidCbor("Connection method: not an array")
        }
        if (items.size < 3) {
            throw MdocValidationError.invalidCbor("Connection method: not 3 items")
        }
        let methodType: UInt64 = match (items[0]) {
            case CborValue.UInt64Val(n) => n
            case _ => throw MdocValidationError.invalidCbor("Connection method: type not uint")
        }
        if (methodType != ConnectionMethodHttp.METHOD_TYPE) {
            throw MdocValidationError.invalidCbor("Connection method: wrong type")
        }
        let uriOpt = items[2].field(CborValue.UInt64Val(ConnectionMethodHttp.OPTION_KEY_URI_WEBSITE))
        let uri: String = match (uriOpt) {
            case Some(CborValue.TextStringVal(s)) => s
            case _ => throw MdocValidationError.invalidCbor("Connection method: missing uri")
        }
        return ConnectionMethodHttp(uri)
    }
}

/* ==================================================================== */
/* ServerRetrievalOption — single server retrieval entry                 */
/* ==================================================================== */

/**
 * One server retrieval entry: [version, url, token].
 *
 * iOS reference: ServerRetrievalOption.swift
 */
public class ServerRetrievalOption <: CBOREncodable {
    static let VERSION_IMPL: UInt64 = 1

    public let version: UInt64
    public let url: String
    public let token: String

    public init(url: String, token: String) {
        this.version = ServerRetrievalOption.VERSION_IMPL
        this.url = url
        this.token = token
    }

    public init(version: UInt64, url: String, token: String) {
        this.version = version
        this.url = url
        this.token = token
    }

    public func toCbor(): CborValue {
        let items = ArrayList<CborValue>()
        items.add(CborValue.UInt64Val(ServerRetrievalOption.VERSION_IMPL))
        items.add(CborValue.TextStringVal(url))
        items.add(CborValue.TextStringVal(token))
        return CborValue.ArrayVal(items)
    }

    public static func fromCbor(cbor: CborValue): ServerRetrievalOption {
        let items: ArrayList<CborValue> = match (cbor) {
            case CborValue.ArrayVal(arr) => arr
            case _ => throw MdocValidationError.invalidCbor("server retrieval option")
        }
        if (items.size < 3) {
            throw MdocValidationError.invalidCbor("server retrieval option")
        }
        let versionVal: UInt64 = match (items[0]) {
            case CborValue.UInt64Val(n) => n
            case _ => throw MdocValidationError.invalidCbor("server retrieval option: version")
        }
        if (versionVal != ServerRetrievalOption.VERSION_IMPL) {
            throw MdocValidationError.invalidCbor("server retrieval option: unsupported version")
        }
        let urlVal: String = match (items[1]) {
            case CborValue.TextStringVal(s) => s
            case _ => throw MdocValidationError.invalidCbor("server retrieval option: url")
        }
        let tokenVal: String = match (items[2]) {
            case CborValue.TextStringVal(s) => s
            case _ => throw MdocValidationError.invalidCbor("server retrieval option: token")
        }
        return ServerRetrievalOption(versionVal, urlVal, tokenVal)
    }
}

/* ==================================================================== */
/* ServerRetrievalOptions — optional server retrieval map                */
/* ==================================================================== */

/**
 * Container for optional server retrieval methods (webAPI and/or OIDC).
 *
 * Wire: map {"webApi": ServerRetrievalOption, "oidc": ServerRetrievalOption}
 *
 * iOS reference: ServerRetrievalOptions.swift
 */
public class ServerRetrievalOptions <: CBOREncodable {
    static let KEY_WEB_API: String = "webApi"
    static let KEY_OIDC: String = "oidc"

    public let webAPI: ?ServerRetrievalOption
    public let oIDC: ?ServerRetrievalOption

    public init(webAPI: ?ServerRetrievalOption, oIDC: ?ServerRetrievalOption) {
        this.webAPI = webAPI
        this.oIDC = oIDC
    }

    public func isEmpty(): Bool {
        match (webAPI) {
            case Some(_) => return false
            case None => ()
        }
        match (oIDC) {
            case Some(_) => return false
            case None => ()
        }
        return true
    }

    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        match (webAPI) {
            case Some(w) =>
                pairs.add((CborValue.TextStringVal(ServerRetrievalOptions.KEY_WEB_API), w.toCbor()))
            case None => ()
        }
        match (oIDC) {
            case Some(o) =>
                pairs.add((CborValue.TextStringVal(ServerRetrievalOptions.KEY_OIDC), o.toCbor()))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    public static func fromCbor(cbor: CborValue): ServerRetrievalOptions {
        match (cbor) {
            case CborValue.MapVal(_) => ()
            case _ => throw MdocValidationError.invalidCbor("server retrieval options")
        }
        let webAPIField = cbor.field(CborValue.TextStringVal(ServerRetrievalOptions.KEY_WEB_API))
        let webAPI: ?ServerRetrievalOption = match (webAPIField) {
            case Some(v) => Some(ServerRetrievalOption.fromCbor(v))
            case None => None
        }
        let oidcField = cbor.field(CborValue.TextStringVal(ServerRetrievalOptions.KEY_OIDC))
        let oIDC: ?ServerRetrievalOption = match (oidcField) {
            case Some(v) => Some(ServerRetrievalOption.fromCbor(v))
            case None => None
        }
        let result = ServerRetrievalOptions(webAPI, oIDC)
        if (result.isEmpty()) {
            throw MdocValidationError.invalidCbor("server retrieval options: empty")
        }
        return result
    }
}

/* ==================================================================== */
/* OriginInfoWebsite — origin info for website engagement                */
/* ==================================================================== */

/**
 * Origin info for website-based engagement (version 1.1 feature).
 *
 * Wire: map {"cat": UInt, "type": 100, "Details": {"baseUrl": String}}
 *
 * iOS reference: OriginInfoWebsite.swift
 */
public class OriginInfoWebsite <: CBOREncodable {
    static let CAT_DELIVERY: UInt64 = 0
    static let CAT_RECEIVE: UInt64 = 1
    static let TYPE: UInt64 = 100

    public let cat: UInt64
    public let baseUrl: String

    public init(baseUrl: String, cat: UInt64) {
        this.baseUrl = baseUrl
        this.cat = cat
    }

    public init(baseUrl: String) {
        this.baseUrl = baseUrl
        this.cat = OriginInfoWebsite.CAT_RECEIVE
    }

    public func toCbor(): CborValue {
        let detailsPairs = ArrayList<(CborValue, CborValue)>()
        detailsPairs.add((CborValue.TextStringVal("baseUrl"), CborValue.TextStringVal(baseUrl)))
        let detailsMap = CborValue.MapVal(detailsPairs)

        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal("cat"), CborValue.UInt64Val(cat)))
        pairs.add((CborValue.TextStringVal("type"), CborValue.UInt64Val(OriginInfoWebsite.TYPE)))
        pairs.add((CborValue.TextStringVal("Details"), detailsMap))
        return CborValue.MapVal(pairs)
    }

    public static func fromCbor(cbor: CborValue): OriginInfoWebsite {
        match (cbor) {
            case CborValue.MapVal(_) => ()
            case _ => throw MdocValidationError.invalidCbor("origin info website")
        }
        let catField = cbor.field(CborValue.TextStringVal("cat"))
        let catVal: UInt64 = match (catField) {
            case Some(CborValue.UInt64Val(n)) => n
            case _ => throw MdocValidationError.missingField("OriginInfoWebsite", "cat")
        }
        let detailsField = cbor.field(CborValue.TextStringVal("Details"))
        let details: CborValue = match (detailsField) {
            case Some(v) => v
            case None => throw MdocValidationError.missingField("OriginInfoWebsite", "Details")
        }
        let baseUrlField = details.field(CborValue.TextStringVal("baseUrl"))
        let baseUrlVal: String = match (baseUrlField) {
            case Some(CborValue.TextStringVal(s)) => s
            case _ => throw MdocValidationError.missingField("OriginInfoWebsite", "baseUrl")
        }
        return OriginInfoWebsite(baseUrlVal, catVal)
    }
}

/* ==================================================================== */
/* DeviceEngagement — top-level engagement structure                     */
/* ==================================================================== */

/**
 * Device engagement information exchanged during QR / NFC handshake.
 *
 * CBOR map structure (ISO 18013-5 §8.2.2.3):
 *   0: version (String, "1.0")
 *   1: Security [1, EDeviceKeyBytes]
 *   2: [DeviceRetrievalMethod, ...]   (optional)
 *   3: ServerRetrievalOptions          (optional)
 *   5: [OriginInfoWebsite, ...]         (optional, version 1.1)
 *
 * QR payload: "mdoc:" + base64url(CBOR(DeviceEngagement))
 *
 * iOS reference: DeviceEngagement.swift
 */
public class DeviceEngagement <: CBOREncodable {
    static let VERSION: String = "1.0"
    static let VERSION_1_1: String = "1.1"
    static let QR_PREFIX: String = "mdoc:"

    public let version: String
    public let security: Security
    public let deviceRetrievalMethods: ?ArrayList<DeviceRetrievalMethod>
    public let serverRetrievalOptions: ?ServerRetrievalOptions
    public let originInfos: ?ArrayList<OriginInfoWebsite>

    /**
     * Primary constructor.
     */
    public init(
        version: String,
        security: Security,
        deviceRetrievalMethods: ?ArrayList<DeviceRetrievalMethod>,
        serverRetrievalOptions: ?ServerRetrievalOptions,
        originInfos: ?ArrayList<OriginInfoWebsite>
    ) {
        this.version = version
        this.security = security
        this.deviceRetrievalMethods = deviceRetrievalMethods
        this.serverRetrievalOptions = serverRetrievalOptions
        this.originInfos = originInfos
    }

    /**
     * Convenience constructor for typical BLE holder use.
     * Caller must supply a pre-built Security (with the device public key).
     */
    public static func forBle(
        security: Security,
        supportsCentral: Bool,
        supportsPeripheral: Bool,
        uuidBytes: Array<UInt8>
    ): ?DeviceEngagement {
        if ((!supportsCentral && !supportsPeripheral) || uuidBytes.size != 16) {
            return None
        }
        let methods = ArrayList<DeviceRetrievalMethod>()
        if (supportsCentral) {
            methods.add(DeviceRetrievalMethod.Ble(false, uuidBytes, None))
        }
        if (supportsPeripheral) {
            methods.add(DeviceRetrievalMethod.Ble(true, uuidBytes, None))
        }
        return Some(DeviceEngagement(
            DeviceEngagement.VERSION,
            security,
            Some(methods),
            None,
            None
        ))
    }

    /* ---- CBOREncodable ---- */

    /**
     * Encode as CBOR map.
     * Keys: 0=version, 1=security, 2=retrievalMethods(opt), 3=serverOptions(opt), 5=originInfos(opt)
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.UInt64Val(UInt64(0)), CborValue.TextStringVal(version)))
        pairs.add((CborValue.UInt64Val(UInt64(1)), security.toCbor()))
        match (deviceRetrievalMethods) {
            case Some(drms) =>
                if (drms.size > 0) {
                    let arr = ArrayList<CborValue>()
                    for (m in drms) {
                        arr.add(m.toCbor())
                    }
                    pairs.add((CborValue.UInt64Val(UInt64(2)), CborValue.ArrayVal(arr)))
                }
            case None => ()
        }
        match (serverRetrievalOptions) {
            case Some(sro) =>
                pairs.add((CborValue.UInt64Val(UInt64(3)), sro.toCbor()))
            case None => ()
        }
        match (originInfos) {
            case Some(ois) =>
                if (ois.size > 0) {
                    let arr = ArrayList<CborValue>()
                    for (oi in ois) {
                        arr.add(oi.toCbor())
                    }
                    pairs.add((CborValue.UInt64Val(UInt64(5)), CborValue.ArrayVal(arr)))
                }
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    /**
     * Encode to raw CBOR bytes.
     */
    public func toCborBytes(): Array<UInt8> {
        return this.toCbor().encode()
    }

    /* ---- Decoding ---- */

    /**
     * Decode a DeviceEngagement from raw CBOR bytes.
     * Throws MdocValidationError on malformed input.
     */
    public static func fromCborBytes(bytes: Array<UInt8>): DeviceEngagement {
        let cbor: CborValue
        try {
            cbor = decodeCbor(bytes)
        } catch (e: Exception) {
            throw MdocValidationError.invalidCbor("device engagement: " + e.message)
        }
        return DeviceEngagement.fromCborMap(cbor)
    }

    /**
     * Decode from a CborValue (must be a map).
     */
    public static func fromCborMap(cbor: CborValue): DeviceEngagement {
        match (cbor) {
            case CborValue.MapVal(_) => ()
            case _ => throw MdocValidationError.invalidCbor("device engagement")
        }
        let versionField = cbor.field(CborValue.UInt64Val(UInt64(0)))
        let versionVal: String = match (versionField) {
            case Some(CborValue.TextStringVal(s)) => s
            case _ => throw MdocValidationError.invalidCbor("device engagement: version")
        }
        let secField = cbor.field(CborValue.UInt64Val(UInt64(1)))
        let sec: Security = match (secField) {
            case Some(v) => Security.fromCbor(v)
            case None => throw MdocValidationError.invalidCbor("device engagement: security")
        }
        let drmsField = cbor.field(CborValue.UInt64Val(UInt64(2)))
        let drms: ?ArrayList<DeviceRetrievalMethod> = match (drmsField) {
            case Some(CborValue.ArrayVal(arr)) =>
                if (arr.size > 0) {
                    let list = ArrayList<DeviceRetrievalMethod>()
                    for (item in arr) {
                        list.add(DeviceRetrievalMethod.fromCbor(item))
                    }
                    Some(list)
                } else {
                    None
                }
            case _ => None
        }
        let sroField = cbor.field(CborValue.UInt64Val(UInt64(3)))
        let sro: ?ServerRetrievalOptions = match (sroField) {
            case Some(v) =>
                try {
                    Some(ServerRetrievalOptions.fromCbor(v))
                } catch (_: Exception) {
                    None
                }
            case None => None
        }
        let oisField = cbor.field(CborValue.UInt64Val(UInt64(5)))
        let ois: ?ArrayList<OriginInfoWebsite> = match (oisField) {
            case Some(CborValue.ArrayVal(arr)) =>
                if (arr.size > 0) {
                    let list = ArrayList<OriginInfoWebsite>()
                    for (item in arr) {
                        list.add(OriginInfoWebsite.fromCbor(item))
                    }
                    Some(list)
                } else {
                    None
                }
            case _ => None
        }
        return DeviceEngagement(versionVal, sec, drms, sro, ois)
    }

    /* ---- QR Code support ---- */

    /**
     * Generate the QR code payload string: "mdoc:" + base64url(CBOR bytes).
     *
     * iOS: de.getQrCodePayload()
     */
    public func getQrCodePayload(): String {
        let bytes = this.toCborBytes()
        let b64 = Base64UrlHelper.encode(bytes)
        return DeviceEngagement.QR_PREFIX + b64
    }

    /**
     * Decode a DeviceEngagement from a QR code payload string.
     * Input must start with "mdoc:".
     * Throws MdocValidationError if the prefix is absent or CBOR is malformed.
     *
     * iOS: DeviceEngagement(data: bytes) where bytes came from parsing the QR payload
     */
    public static func fromQrCodePayload(payload: String): DeviceEngagement {
        if (!payload.startsWith(DeviceEngagement.QR_PREFIX)) {
            throw MdocValidationError.invalidCbor("device engagement: QR payload missing 'mdoc:' prefix")
        }
        let b64 = payload.removePrefix(DeviceEngagement.QR_PREFIX)
        let bytes: Array<UInt8>
        try {
            bytes = Base64UrlHelper.decode(b64)
        } catch (e: Exception) {
            throw MdocValidationError.invalidCbor("device engagement: invalid base64url in QR payload")
        }
        return DeviceEngagement.fromCborBytes(bytes)
    }
}
