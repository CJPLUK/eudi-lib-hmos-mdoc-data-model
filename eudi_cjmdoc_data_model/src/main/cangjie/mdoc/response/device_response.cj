/*
 * device_response.cj
 *
 * ISO 18013-5 §8.3 — Device Response structures.
 *
 * Types defined here (mirrors iOS MdocResponse/ directory, 13 source files):
 *   DocDataValue        — typed value enum for document data elements
 *   IssuerSignedItem    — single signed data element; preserves raw Tag-24 bytes for digest
 *   IssuerNameSpaces    — {namespace → [IssuerSignedItem]} map
 *   IssuerSigned        — wraps IssuerNameSpaces + IssuerAuth
 *   DeviceSignedItems   — {elementIdentifier → elementValue} map per namespace
 *   DeviceNameSpaces    — {namespace → DeviceSignedItems} map (Tag-24 wrapped on wire)
 *   DeviceAuth          — holds a COSE_Sign1 (deviceSignature) or COSE_Mac0 (deviceMac)
 *   DeviceSigned        — wraps DeviceNameSpaces + DeviceAuth
 *   Errors              — per-namespace error codes for unreturned items
 *   DocumentError       — per-docType error codes
 *   Document            — docType + IssuerSigned + DeviceSigned + optional Errors
 *   DeviceResponse      — top-level: version + [Document]? + [DocumentError]? + status
 *
 * Compliance note (done_when 3):
 *   IssuerSignedItem preserves the raw bytes it was decoded from (rawData).
 *   iOS stores rawData as [UInt8]? and encodes by returning rawData when present,
 *   so that Digest.sha256(rawData) reproduces the digest stored in ValueDigests.
 *   This file mirrors that strategy: fromCborBytes() stores the input bytes in rawData;
 *   toCbor() / encode() returns rawData bytes verbatim when non-None.
 *
 * iOS references:
 *   Sources/MdocDataModel18013/MdocResponse/DeviceResponse.swift
 *   Sources/MdocDataModel18013/MdocResponse/Document.swift
 *   Sources/MdocDataModel18013/MdocResponse/IssuerSigned.swift
 *   Sources/MdocDataModel18013/MdocResponse/IssuerNameSpaces.swift
 *   Sources/MdocDataModel18013/MdocResponse/IssuerSignedItem.swift
 *   Sources/MdocDataModel18013/MdocResponse/DeviceSigned.swift
 *   Sources/MdocDataModel18013/MdocResponse/DeviceAuth.swift
 *   Sources/MdocDataModel18013/MdocResponse/DeviceNameSpaces.swift
 *   Sources/MdocDataModel18013/MdocResponse/DocDataValue.swift
 *   Sources/MdocDataModel18013/MdocResponse/Errors.swift
 *   Sources/MdocDataModel18013/MdocResponse/DocumentError.swift
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response

import std.collection.ArrayList
import std.collection.HashMap

import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.CborTag
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor
import ohos_app_cangjie_eudi_cjcbor.cbor.encodeEmbedded
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeEmbedded

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CBOREncodable
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MdocValidationError
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.IssuerAuth
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.NameSpace

/* ===================================================================== */
/* Type aliases                                                           */
/* ===================================================================== */

/** Document type string (e.g. "org.iso.18013.5.1.mDL"). */
public type DocType = String

/** Data element identifier string. */
public type DataElementIdentifier = String

/** Error code — unsigned integer per ISO 18013-5 Table 9. */
public type ErrorCode = UInt64

/* ===================================================================== */
/* DocDataValue — typed enum for document element values                 */
/* ===================================================================== */

/**
 * Typed representation of a CBOR data element value, mirroring iOS DocDataValue.
 *
 * CBOR mapping (from IssuerSignedItem.swift CBOR extension):
 *   .utf8String        → string(String)
 *   .byteString        → bytes(Array<UInt8>)
 *   .map               → dictionary
 *   .array             → array
 *   .boolean           → boolean(Bool)
 *   .tagged(tdate)     → date(String)
 *   .unsignedInt       → integer(UInt64)
 *   .double            → double(Float64)
 */
public enum DocDataValue {
    | BooleanVal(Bool)
    | IntegerVal(UInt64)
    | DoubleVal(Float64)
    | StringVal(String)
    | DateVal(String)
    | BytesVal(Array<UInt8>)
    | ArrayVal
    | DictionaryVal

    /** Human-readable description (mirrors iOS description computed property). */
    public func describe(): String {
        match (this) {
            case BooleanVal(b) => return b.toString()
            case IntegerVal(i) => return i.toString()
            case DoubleVal(d) => return d.toString()
            case StringVal(s) => return s
            case DateVal(d) => return d
            case BytesVal(b) => return "Bytes " + b.size.toString()
            case ArrayVal => return "Array"
            case DictionaryVal => return "Dictionary"
        }
    }
}

/**
 * Extract a DocDataValue from a CborValue.
 * Returns None for CBOR types that do not map to a supported DocDataValue.
 */
public func cborToDocDataValue(cbor: CborValue): ?DocDataValue {
    match (cbor) {
        case CborValue.TextStringVal(s) => return Some(DocDataValue.StringVal(s))
        case CborValue.ByteStringVal(b) => return Some(DocDataValue.BytesVal(b))
        case CborValue.MapVal(_) => return Some(DocDataValue.DictionaryVal)
        case CborValue.ArrayVal(_) => return Some(DocDataValue.ArrayVal)
        case CborValue.BoolVal(b) => return Some(DocDataValue.BooleanVal(b))
        case CborValue.TaggedVal(tag, inner) =>
            if (tag == CborTag.STANDARD_DATE_TIME || tag == CborTag.FULL_DATE) {
                match (inner) {
                    case CborValue.TextStringVal(s) => return Some(DocDataValue.DateVal(s))
                    case _ => ()
                }
            }
            match (inner) {
                case CborValue.TextStringVal(s) => return Some(DocDataValue.StringVal(s))
                case _ => return None
            }
        case CborValue.UInt64Val(i) => return Some(DocDataValue.IntegerVal(i))
        case CborValue.DoubleVal(d) => return Some(DocDataValue.DoubleVal(d))
        case CborValue.FloatVal(f) => return Some(DocDataValue.DoubleVal(Float64(f)))
        case CborValue.SimpleVal(n) => return Some(DocDataValue.IntegerVal(UInt64(n)))
        case _ => return None
    }
}

/* ===================================================================== */
/* IssuerSignedItem — signed data element with raw-bytes preservation    */
/* ===================================================================== */

/**
 * A single data element signed by the issuer.
 *
 * CBOR map wire form:
 *   {
 *     "digestID"         : uint,
 *     "random"           : bstr,
 *     "elementIdentifier": tstr,
 *     "elementValue"     : any
 *   }
 *
 * Critical ISO compliance:
 *   The digest in ValueDigests is computed over #6.24(bstr .cbor IssuerSignedItem)
 *   i.e. over the Tag-24-wrapped encoding of this map.  To avoid byte drift on
 *   re-encoding, rawData preserves the original bytes this item was decoded from.
 *   encode() returns rawData when present (matching iOS encode(options:) strategy).
 *
 * iOS ref: IssuerSignedItem.swift
 */
public class IssuerSignedItem <: CBOREncodable {
    /** Digest ID used to index into ValueDigests for this item. */
    public let digestID: UInt64
    /** Random nonce for issuer data authentication (bstr). */
    public let random: Array<UInt8>
    /** Data element identifier (tstr). */
    public let elementIdentifier: DataElementIdentifier
    /** Data element value (raw CborValue — may be any CBOR type). */
    public let elementValue: CborValue
    /**
     * Raw bytes of this IssuerSignedItem map as originally received.
     * When present, encode() returns these bytes verbatim to avoid digest drift.
     */
    public var rawData: ?Array<UInt8>

    static let KEY_DIGEST_ID = "digestID"
    static let KEY_RANDOM = "random"
    static let KEY_ELEMENT_IDENTIFIER = "elementIdentifier"
    static let KEY_ELEMENT_VALUE = "elementValue"

    public init(
        digestID: UInt64,
        random: Array<UInt8>,
        elementIdentifier: DataElementIdentifier,
        elementValue: CborValue,
        rawData: ?Array<UInt8>
    ) {
        this.digestID = digestID
        this.random = random
        this.elementIdentifier = elementIdentifier
        this.elementValue = elementValue
        this.rawData = rawData
    }

    /**
     * Decode from raw CBOR bytes and preserve those bytes in rawData.
     *
     * This is the constructor called by IssuerNameSpaces when unwrapping each
     * Tag-24 bstr: the bytes are the canonical encoding of this item and MUST
     * be preserved so that Digest.sha256(rawData) reproduces the digest that
     * the issuer committed to in the MSO ValueDigests.
     *
     * Throws MdocValidationError if the bytes cannot be decoded or the map
     * is missing required fields.
     */
    public static func fromCborBytes(bytes: Array<UInt8>): IssuerSignedItem {
        let cbor: CborValue
        try {
            cbor = decodeCbor(bytes)
        } catch (_: Exception) {
            throw MdocValidationError.invalidCbor("issuer signed item")
        }
        let item = IssuerSignedItem.fromCbor(cbor)
        item.rawData = bytes
        return item
    }

    /**
     * Decode from a CborValue map.
     * Does NOT set rawData (rawData remains None after this call).
     * Callers that need rawData should use fromCborBytes() instead.
     *
     * Throws MdocValidationError if required fields are absent.
     */
    public static func fromCbor(cbor: CborValue): IssuerSignedItem {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let digestIdOpt = cbor.field(CborValue.TextStringVal(KEY_DIGEST_ID))
                let digestIdVal: UInt64
                match (digestIdOpt) {
                    case Some(CborValue.UInt64Val(id)) => digestIdVal = id
                    case _ => throw MdocValidationError.missingField("IssuerSignedItem", KEY_DIGEST_ID)
                }
                let randomOpt = cbor.field(CborValue.TextStringVal(KEY_RANDOM))
                let randomVal: Array<UInt8>
                match (randomOpt) {
                    case Some(CborValue.ByteStringVal(r)) => randomVal = r
                    case _ => throw MdocValidationError.missingField("IssuerSignedItem", KEY_RANDOM)
                }
                let eiOpt = cbor.field(CborValue.TextStringVal(KEY_ELEMENT_IDENTIFIER))
                let eiVal: String
                match (eiOpt) {
                    case Some(CborValue.TextStringVal(s)) => eiVal = s
                    case _ => throw MdocValidationError.missingField("IssuerSignedItem", KEY_ELEMENT_IDENTIFIER)
                }
                let evOpt = cbor.field(CborValue.TextStringVal(KEY_ELEMENT_VALUE))
                let evVal: CborValue
                match (evOpt) {
                    case Some(v) => evVal = v
                    case None => throw MdocValidationError.missingField("IssuerSignedItem", KEY_ELEMENT_VALUE)
                }
                return IssuerSignedItem(digestIdVal, randomVal, eiVal, evVal, None)
            case _ =>
                throw MdocValidationError.invalidCbor("issuer signed item")
        }
    }

    /**
     * Return the canonical CBOR encoding of this item map.
     *
     * When rawData is present (item was decoded from wire bytes), the raw bytes
     * are returned verbatim — this guarantees Digest.sha256(encode()) matches the
     * digest committed to in the issuer's MSO ValueDigests.
     *
     * When rawData is None (item was constructed programmatically), the map is
     * freshly encoded. Note: the iOS reference warns "it is not recommended to
     * encode again, the digest may change" for this path.
     */
    public func encode(): Array<UInt8> {
        match (this.rawData) {
            case Some(raw) => return raw
            case None => return this.toCbor().encode()
        }
    }

    /**
     * Produce the CborValue map form of this item.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((
            CborValue.TextStringVal(IssuerSignedItem.KEY_DIGEST_ID),
            CborValue.UInt64Val(this.digestID)
        ))
        pairs.add((
            CborValue.TextStringVal(IssuerSignedItem.KEY_RANDOM),
            CborValue.ByteStringVal(this.random)
        ))
        pairs.add((
            CborValue.TextStringVal(IssuerSignedItem.KEY_ELEMENT_IDENTIFIER),
            CborValue.TextStringVal(this.elementIdentifier)
        ))
        pairs.add((
            CborValue.TextStringVal(IssuerSignedItem.KEY_ELEMENT_VALUE),
            this.elementValue
        ))
        return CborValue.MapVal(pairs)
    }

    /** Convenience: extract the DocDataValue interpretation of elementValue. */
    public func docDataValue(): ?DocDataValue {
        return cborToDocDataValue(this.elementValue)
    }
}

/* ===================================================================== */
/* IssuerNameSpaces — {namespace → [IssuerSignedItem]}                  */
/* ===================================================================== */

/**
 * Returned data elements grouped by namespace.
 *
 * CBOR wire form:
 *   {
 *     tstr: [ #6.24(bstr .cbor IssuerSignedItem)* ]+
 *   }
 *
 * Each array element is a Tag-24 wrapped IssuerSignedItem. The inner bstr is
 * passed verbatim to IssuerSignedItem.fromCborBytes() so rawData is preserved.
 *
 * iOS ref: IssuerNameSpaces.swift
 */
public class IssuerNameSpaces <: CBOREncodable {
    /** Map from namespace string to list of signed items. */
    public let nameSpaces: HashMap<NameSpace, ArrayList<IssuerSignedItem>>

    public init(nameSpaces: HashMap<NameSpace, ArrayList<IssuerSignedItem>>) {
        this.nameSpaces = nameSpaces
    }

    /** Return the items for a given namespace, or None if not present. */
    public func get(ns: NameSpace): ?ArrayList<IssuerSignedItem> {
        return this.nameSpaces.get(ns)
    }

    /**
     * Decode from a CBOR map of tstr → array-of-Tag24 entries.
     *
     * Throws MdocValidationError if:
     *   - cbor is not a map
     *   - a namespace array is empty
     *   - an array element is not a properly Tag-24-wrapped bstr
     *   - the inner bstr cannot be decoded as an IssuerSignedItem map
     *   - the resulting map is empty
     */
    public static func fromCbor(cbor: CborValue): IssuerNameSpaces {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let temp = HashMap<NameSpace, ArrayList<IssuerSignedItem>>()
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.TextStringVal(ns) =>
                            match (v) {
                                case CborValue.ArrayVal(items) =>
                                    if (items.size == 0) {
                                        throw MdocValidationError.invalidCbor("issuer namespace '" + ns + "' empty array")
                                    }
                                    let parsedItems = ArrayList<IssuerSignedItem>()
                                    for (item in items) {
                                        match (item) {
                                            case CborValue.TaggedVal(tag, inner) =>
                                                if (tag != CborTag.ENCODED_CBOR) {
                                                    throw MdocValidationError.invalidCbor("issuer signed item not Tag-24")
                                                }
                                                match (inner) {
                                                    case CborValue.ByteStringVal(bs) =>
                                                        let parsed = IssuerSignedItem.fromCborBytes(bs)
                                                        parsedItems.add(parsed)
                                                    case _ =>
                                                        throw MdocValidationError.invalidCbor("issuer signed item Tag-24 payload not bstr")
                                                }
                                            case _ =>
                                                throw MdocValidationError.invalidCbor("issuer signed item not Tag-24 wrapped")
                                        }
                                    }
                                    temp.add(ns, parsedItems)
                                case _ => ()
                            }
                        case _ => ()
                    }
                }
                if (temp.size == 0) {
                    throw MdocValidationError.invalidCbor("issuer name spaces: no valid namespaces")
                }
                return IssuerNameSpaces(temp)
            case _ =>
                throw MdocValidationError.invalidCbor("issuer namespaces")
        }
    }

    /**
     * Encode to CBOR map of tstr → array of Tag-24-wrapped IssuerSignedItem bytes.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let outerPairs = ArrayList<(CborValue, CborValue)>()
        for ((ns, items) in this.nameSpaces) {
            let encodedItems = ArrayList<CborValue>()
            for (item in items) {
                let itemBytes = item.encode()
                encodedItems.add(CborValue.TaggedVal(CborTag.ENCODED_CBOR, CborValue.ByteStringVal(itemBytes)))
            }
            outerPairs.add((CborValue.TextStringVal(ns), CborValue.ArrayVal(encodedItems)))
        }
        return CborValue.MapVal(outerPairs)
    }
}

/* ===================================================================== */
/* IssuerSigned — IssuerNameSpaces + IssuerAuth                         */
/* ===================================================================== */

/**
 * Contains the mobile security object for issuer data authentication and the
 * data elements protected by issuer data authentication.
 *
 * CBOR wire form:
 *   {
 *     "nameSpaces": { tstr: [#6.24(bstr .cbor IssuerSignedItem)*]* },  // optional
 *     "issuerAuth": COSE_Sign1 (untagged bare 4-element array)
 *   }
 *
 * iOS ref: IssuerSigned.swift
 */
public class IssuerSigned <: CBOREncodable {
    public let issuerNameSpaces: ?IssuerNameSpaces
    public let issuerAuth: IssuerAuth

    static let KEY_NAME_SPACES = "nameSpaces"
    static let KEY_ISSUER_AUTH = "issuerAuth"

    public init(issuerNameSpaces: ?IssuerNameSpaces, issuerAuth: IssuerAuth) {
        this.issuerNameSpaces = issuerNameSpaces
        this.issuerAuth = issuerAuth
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if issuerAuth is absent or malformed.
     */
    public static func fromCbor(cbor: CborValue): IssuerSigned {
        match (cbor) {
            case CborValue.MapVal(_) =>
                var issuerNsOpt: ?IssuerNameSpaces = None
                let nsFieldOpt = cbor.field(CborValue.TextStringVal(KEY_NAME_SPACES))
                match (nsFieldOpt) {
                    case Some(nsCbor) =>
                        try {
                            issuerNsOpt = Some(IssuerNameSpaces.fromCbor(nsCbor))
                        } catch (_: MdocValidationError) {
                            issuerNsOpt = None
                        }
                    case None =>
                        issuerNsOpt = None
                }
                let iaFieldOpt = cbor.field(CborValue.TextStringVal(KEY_ISSUER_AUTH))
                match (iaFieldOpt) {
                    case None =>
                        throw MdocValidationError.missingField("IssuerSigned", KEY_ISSUER_AUTH)
                    case Some(iaCbor) =>
                        let ia = IssuerAuth.fromCbor(iaCbor)
                        return IssuerSigned(issuerNsOpt, ia)
                }
            case _ =>
                throw MdocValidationError.invalidCbor("issuer signed must be a map")
        }
    }

    /**
     * Encode to CBOR map.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        match (this.issuerNameSpaces) {
            case Some(ns) =>
                pairs.add((CborValue.TextStringVal(IssuerSigned.KEY_NAME_SPACES), ns.toCbor()))
            case None => ()
        }
        pairs.add((CborValue.TextStringVal(IssuerSigned.KEY_ISSUER_AUTH), this.issuerAuth.toCbor()))
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* DeviceSignedItems — {elementIdentifier → elementValue} per namespace */
/* ===================================================================== */

/**
 * Data elements signed by the device for one namespace.
 *
 * CBOR wire form: map(tstr → any)*
 *
 * iOS ref: DeviceSigned.swift (DeviceSignedItems struct)
 */
public class DeviceSignedItems <: CBOREncodable {
    /** Ordered map from element identifier to element value. */
    public let items: ArrayList<(DataElementIdentifier, CborValue)>

    public init(items: ArrayList<(DataElementIdentifier, CborValue)>) {
        this.items = items
    }

    /** Subscript access by element identifier. Returns None if not present. */
    public func get(ei: DataElementIdentifier): ?CborValue {
        for ((k, v) in this.items) {
            if (k == ei) {
                return Some(v)
            }
        }
        return None
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if cbor is not a map, or the map is empty.
     */
    public static func fromCbor(cbor: CborValue): DeviceSignedItems {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let result = ArrayList<(DataElementIdentifier, CborValue)>()
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.TextStringVal(dei) =>
                            result.add((dei, v))
                        case _ =>
                            throw MdocValidationError.invalidCbor("Invalid device signed item key")
                    }
                }
                if (result.size == 0) {
                    throw MdocValidationError.invalidCbor("device signed items empty")
                }
                return DeviceSignedItems(result)
            case _ =>
                throw MdocValidationError.invalidCbor("device signed items")
        }
    }

    /**
     * Encode to CBOR map.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        for ((k, v) in this.items) {
            pairs.add((CborValue.TextStringVal(k), v))
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* DeviceNameSpaces — {namespace → DeviceSignedItems}                   */
/* ===================================================================== */

/**
 * Device data elements per namespace.
 *
 * CBOR wire form: map(tstr → map(tstr → any)*)*
 * Wire form in DeviceSigned: #6.24(bstr .cbor DeviceNameSpaces)
 *
 * iOS ref: DeviceSigned.swift (DeviceNameSpaces struct)
 */
public class DeviceNameSpaces <: CBOREncodable {
    /** Map from namespace string to DeviceSignedItems. */
    public let deviceNameSpaces: ArrayList<(NameSpace, DeviceSignedItems)>

    public init(deviceNameSpaces: ArrayList<(NameSpace, DeviceSignedItems)>) {
        this.deviceNameSpaces = deviceNameSpaces
    }

    /** Return DeviceSignedItems for a given namespace. Returns None if absent. */
    public func get(ns: NameSpace): ?DeviceSignedItems {
        for ((k, v) in this.deviceNameSpaces) {
            if (k == ns) {
                return Some(v)
            }
        }
        return None
    }

    /**
     * Decode from a CBOR map (after Tag-24 unwrapping by DeviceSigned).
     * An empty map (no namespaces) is valid per spec.
     * Throws MdocValidationError if cbor is not a map.
     */
    public static func fromCbor(cbor: CborValue): DeviceNameSpaces {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let result = ArrayList<(NameSpace, DeviceSignedItems)>()
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.TextStringVal(ns) =>
                            let dsi = DeviceSignedItems.fromCbor(v)
                            result.add((ns, dsi))
                        case _ =>
                            throw MdocValidationError.invalidCbor("Invalid device namespace key")
                    }
                }
                return DeviceNameSpaces(result)
            case _ =>
                throw MdocValidationError.invalidCbor("device name spaces")
        }
    }

    /**
     * Encode to CBOR map.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        for ((ns, dsi) in this.deviceNameSpaces) {
            pairs.add((CborValue.TextStringVal(ns), dsi.toCbor()))
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* DeviceAuth — COSE_Sign1 or COSE_Mac0 authentication container        */
/* ===================================================================== */

/**
 * Contains either the DeviceSignature (COSE_Sign1) or DeviceMac (COSE_Mac0) element.
 *
 * CBOR wire form:
 *   {
 *     "deviceSignature": COSE_Sign1 (untagged bare array),  // OR
 *     "deviceMac"      : COSE_Mac0 (untagged bare array)
 *   }
 *
 * Exactly one of deviceSignature or deviceMac must be present.
 *
 * iOS ref: DeviceAuth.swift
 */
public class DeviceAuth <: CBOREncodable {
    /** Whether this is a COSE_Sign1 (true) or COSE_Mac0 (false). */
    public let isSign1: Bool
    /** Raw COSE structure preserved as CborValue for round-trip fidelity. */
    public let coseCbor: CborValue

    static let KEY_DEVICE_SIGNATURE = "deviceSignature"
    static let KEY_DEVICE_MAC = "deviceMac"

    public init(isSign1: Bool, coseCbor: CborValue) {
        this.isSign1 = isSign1
        this.coseCbor = coseCbor
    }

    /**
     * Decode from a CBOR map.
     * Exactly one of deviceSignature or deviceMac must be present.
     * Throws MdocValidationError if neither or both are present, or the value is malformed.
     */
    public static func fromCbor(cbor: CborValue): DeviceAuth {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let dsSig = cbor.field(CborValue.TextStringVal(KEY_DEVICE_SIGNATURE))
                let dsMac = cbor.field(CborValue.TextStringVal(KEY_DEVICE_MAC))
                match ((dsSig, dsMac)) {
                    case (Some(sigCbor), None) =>
                        return DeviceAuth(true, sigCbor)
                    case (None, Some(macCbor)) =>
                        return DeviceAuth(false, macCbor)
                    case (Some(_), Some(_)) =>
                        throw MdocValidationError.invalidCbor("DeviceMac and DeviceSignature cannot both be present")
                    case (None, None) =>
                        throw MdocValidationError.invalidCbor("Either DeviceMac or DeviceSignature must be present")
                }
            case _ =>
                throw MdocValidationError.invalidCbor("Device authentication must be a map")
        }
    }

    /**
     * Encode to CBOR map.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        let key = if (this.isSign1) {
            CborValue.TextStringVal(DeviceAuth.KEY_DEVICE_SIGNATURE)
        } else {
            CborValue.TextStringVal(DeviceAuth.KEY_DEVICE_MAC)
        }
        pairs.add((key, this.coseCbor))
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* DeviceSigned — DeviceNameSpaces (Tag-24) + DeviceAuth                */
/* ===================================================================== */

/**
 * Contains the mdoc authentication structure and device-signed data elements.
 *
 * CBOR wire form:
 *   {
 *     "nameSpaces": #6.24(bstr .cbor DeviceNameSpaces),
 *     "deviceAuth" : DeviceAuth map
 *   }
 *
 * The nameSpaces field is Tag-24 wrapped (DeviceNameSpacesBytes in the spec).
 *
 * iOS ref: DeviceSigned.swift
 */
public class DeviceSigned <: CBOREncodable {
    public let nameSpaces: DeviceNameSpaces
    public let deviceAuth: DeviceAuth

    static let KEY_NAME_SPACES = "nameSpaces"
    static let KEY_DEVICE_AUTH = "deviceAuth"

    public init(nameSpaces: DeviceNameSpaces, deviceAuth: DeviceAuth) {
        this.nameSpaces = nameSpaces
        this.deviceAuth = deviceAuth
    }

    /**
     * Decode from a CBOR map.
     * nameSpaces must be a Tag-24-wrapped bstr containing an encoded DeviceNameSpaces map.
     * Throws MdocValidationError on structural violations.
     */
    public static func fromCbor(cbor: CborValue): DeviceSigned {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let nsFieldOpt = cbor.field(CborValue.TextStringVal(KEY_NAME_SPACES))
                match (nsFieldOpt) {
                    case None =>
                        throw MdocValidationError.missingField("DeviceSigned", KEY_NAME_SPACES)
                    case Some(nsCbor) =>
                        match (nsCbor) {
                            case CborValue.TaggedVal(tag, inner) =>
                                if (tag != CborTag.ENCODED_CBOR) {
                                    throw MdocValidationError.missingField("DeviceSigned", KEY_NAME_SPACES)
                                }
                                match (inner) {
                                    case CborValue.ByteStringVal(nsBytes) =>
                                        let nsDecoded: CborValue
                                        try {
                                            nsDecoded = decodeCbor(nsBytes)
                                        } catch (_: Exception) {
                                            throw MdocValidationError.invalidCbor("DeviceSigned nameSpaces inner CBOR")
                                        }
                                        let ns = DeviceNameSpaces.fromCbor(nsDecoded)
                                        let daFieldOpt = cbor.field(CborValue.TextStringVal(KEY_DEVICE_AUTH))
                                        match (daFieldOpt) {
                                            case None =>
                                                throw MdocValidationError.missingField("DeviceSigned", KEY_DEVICE_AUTH)
                                            case Some(daCbor) =>
                                                let da = DeviceAuth.fromCbor(daCbor)
                                                return DeviceSigned(ns, da)
                                        }
                                    case _ =>
                                        throw MdocValidationError.missingField("DeviceSigned", KEY_NAME_SPACES)
                                }
                            case _ =>
                                throw MdocValidationError.missingField("DeviceSigned", KEY_NAME_SPACES)
                        }
                }
            case _ =>
                throw MdocValidationError.invalidCbor("device signed")
        }
    }

    /**
     * Encode to CBOR map with Tag-24-wrapped nameSpaces.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        let nsTag24 = encodeEmbedded(this.nameSpaces.toCbor())
        pairs.add((CborValue.TextStringVal(DeviceSigned.KEY_NAME_SPACES), nsTag24))
        pairs.add((CborValue.TextStringVal(DeviceSigned.KEY_DEVICE_AUTH), this.deviceAuth.toCbor()))
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* Errors — per-namespace error codes for unreturned items              */
/* ===================================================================== */

/**
 * Error codes for each namespace for data elements that are not returned.
 *
 * CBOR wire form:
 *   {
 *     tstr: { tstr: uint }
 *   }
 *
 * iOS ref: Errors.swift
 */
public class MdocErrors <: CBOREncodable {
    public let errors: HashMap<NameSpace, HashMap<DataElementIdentifier, ErrorCode>>

    public init(errors: HashMap<NameSpace, HashMap<DataElementIdentifier, ErrorCode>>) {
        this.errors = errors
    }

    /** Return error items for a given namespace. Returns None if absent. */
    public func get(ns: NameSpace): ?HashMap<DataElementIdentifier, ErrorCode> {
        return this.errors.get(ns)
    }

    /**
     * Decode from a CBOR map of namespace → (elementId → errorCode).
     * Throws MdocValidationError if cbor is not a map, or the map is empty.
     */
    public static func fromCbor(cbor: CborValue): MdocErrors {
        match (cbor) {
            case CborValue.MapVal(outerPairs) =>
                if (outerPairs.size == 0) {
                    throw MdocValidationError.invalidCbor("errors: empty map")
                }
                let result = HashMap<NameSpace, HashMap<DataElementIdentifier, ErrorCode>>()
                for ((k, v) in outerPairs) {
                    match (k) {
                        case CborValue.TextStringVal(ns) =>
                            match (v) {
                                case CborValue.MapVal(innerPairs) =>
                                    let nsErrors = HashMap<DataElementIdentifier, ErrorCode>()
                                    for ((ek, ev) in innerPairs) {
                                        match ((ek, ev)) {
                                            case (CborValue.TextStringVal(dei), CborValue.UInt64Val(ec)) =>
                                                nsErrors.add(dei, ec)
                                            case _ =>
                                                throw MdocValidationError.invalidCbor("errors: invalid error item")
                                        }
                                    }
                                    if (nsErrors.size == 0) {
                                        throw MdocValidationError.invalidCbor("errors: empty namespace error map")
                                    }
                                    result.add(ns, nsErrors)
                                case _ =>
                                    throw MdocValidationError.invalidCbor("errors: namespace value is not a map")
                            }
                        case _ =>
                            throw MdocValidationError.invalidCbor("errors: namespace key is not a string")
                    }
                }
                return MdocErrors(result)
            case _ =>
                throw MdocValidationError.invalidCbor("errors")
        }
    }

    /**
     * Encode to CBOR map of namespace → {elementId: uint}.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let outerPairs = ArrayList<(CborValue, CborValue)>()
        for ((ns, nsErrors) in this.errors) {
            let innerPairs = ArrayList<(CborValue, CborValue)>()
            for ((dei, ec) in nsErrors) {
                innerPairs.add((CborValue.TextStringVal(dei), CborValue.UInt64Val(ec)))
            }
            outerPairs.add((CborValue.TextStringVal(ns), CborValue.MapVal(innerPairs)))
        }
        return CborValue.MapVal(outerPairs)
    }
}

/* ===================================================================== */
/* DocumentError — per-docType error codes                              */
/* ===================================================================== */

/**
 * Error codes for documents that are not returned.
 *
 * CBOR wire form: map(tstr → uint)*
 *
 * iOS ref: DocumentError.swift
 */
public class DocumentError <: CBOREncodable {
    public let docErrors: HashMap<DocType, ErrorCode>

    public init(docErrors: HashMap<DocType, ErrorCode>) {
        this.docErrors = docErrors
    }

    /** Return error code for a given document type. Returns None if absent. */
    public func get(dt: DocType): ?ErrorCode {
        return this.docErrors.get(dt)
    }

    /**
     * Decode from a CBOR map of docType → errorCode.
     * Throws MdocValidationError if cbor is not a map, or the map is empty.
     */
    public static func fromCbor(cbor: CborValue): DocumentError {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let result = HashMap<DocType, ErrorCode>()
                for ((k, v) in pairs) {
                    match ((k, v)) {
                        case (CborValue.TextStringVal(dt), CborValue.UInt64Val(ec)) =>
                            result.add(dt, ec)
                        case _ =>
                            throw MdocValidationError.invalidCbor("document error: invalid entry")
                    }
                }
                if (result.size == 0) {
                    throw MdocValidationError.invalidCbor("document error: empty map")
                }
                return DocumentError(result)
            case _ =>
                throw MdocValidationError.invalidCbor("document error")
        }
    }

    /**
     * Encode to CBOR map of docType → errorCode.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        for ((dt, ec) in this.docErrors) {
            pairs.add((CborValue.TextStringVal(dt), CborValue.UInt64Val(ec)))
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* Document — docType + IssuerSigned + DeviceSigned + optional Errors   */
/* ===================================================================== */

/**
 * A single returned document in the device response.
 *
 * CBOR wire form:
 *   {
 *     "docType"     : tstr,
 *     "issuerSigned": IssuerSigned map,
 *     "deviceSigned": DeviceSigned map,
 *     "errors"      : Errors map  // optional
 *   }
 *
 * iOS ref: Document.swift
 */
public class Document <: CBOREncodable {
    public let docType: DocType
    public let issuerSigned: IssuerSigned
    public let deviceSigned: DeviceSigned
    public let errors: ?MdocErrors

    static let KEY_DOC_TYPE = "docType"
    static let KEY_ISSUER_SIGNED = "issuerSigned"
    static let KEY_DEVICE_SIGNED = "deviceSigned"
    static let KEY_ERRORS = "errors"

    public init(
        docType: DocType,
        issuerSigned: IssuerSigned,
        deviceSigned: DeviceSigned,
        errors: ?MdocErrors
    ) {
        this.docType = docType
        this.issuerSigned = issuerSigned
        this.deviceSigned = deviceSigned
        this.errors = errors
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if required fields are absent.
     */
    public static func fromCbor(cbor: CborValue): Document {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let dtOpt = cbor.field(CborValue.TextStringVal(KEY_DOC_TYPE))
                let dtVal: String
                match (dtOpt) {
                    case Some(CborValue.TextStringVal(s)) => dtVal = s
                    case _ => throw MdocValidationError.missingField("Document", KEY_DOC_TYPE)
                }
                let isOpt = cbor.field(CborValue.TextStringVal(KEY_ISSUER_SIGNED))
                match (isOpt) {
                    case None => throw MdocValidationError.missingField("Document", KEY_ISSUER_SIGNED)
                    case Some(isCbor) =>
                        let is_ = IssuerSigned.fromCbor(isCbor)
                        let dsOpt = cbor.field(CborValue.TextStringVal(KEY_DEVICE_SIGNED))
                        match (dsOpt) {
                            case None => throw MdocValidationError.missingField("Document", KEY_DEVICE_SIGNED)
                            case Some(dsCbor) =>
                                let ds = DeviceSigned.fromCbor(dsCbor)
                                var errorsOpt: ?MdocErrors = None
                                let errorsFieldOpt = cbor.field(CborValue.TextStringVal(KEY_ERRORS))
                                match (errorsFieldOpt) {
                                    case Some(eCbor) =>
                                        try {
                                            errorsOpt = Some(MdocErrors.fromCbor(eCbor))
                                        } catch (_: MdocValidationError) {
                                            errorsOpt = None
                                        }
                                    case None =>
                                        errorsOpt = None
                                }
                                return Document(dtVal, is_, ds, errorsOpt)
                        }
                }
            case _ =>
                throw MdocValidationError.invalidCbor("document")
        }
    }

    /**
     * Encode to CBOR map.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal(Document.KEY_DOC_TYPE), CborValue.TextStringVal(this.docType)))
        pairs.add((CborValue.TextStringVal(Document.KEY_ISSUER_SIGNED), this.issuerSigned.toCbor()))
        pairs.add((CborValue.TextStringVal(Document.KEY_DEVICE_SIGNED), this.deviceSigned.toCbor()))
        match (this.errors) {
            case Some(e) =>
                pairs.add((CborValue.TextStringVal(Document.KEY_ERRORS), e.toCbor()))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* DeviceResponse — top-level ISO 18013-5 §8.3 response container      */
/* ===================================================================== */

/**
 * Device retrieval mdoc response.
 *
 * CBOR wire form:
 *   {
 *     "version"       : tstr,
 *     "documents"     : [Document*],       // optional
 *     "documentErrors": [DocumentError*],  // optional
 *     "status"        : uint
 *   }
 *
 * In mdoc reader: initialise from CBOR data received from holder (data exchange).
 * In mdoc holder: initialise from CBOR data received from server (registration).
 *
 * iOS ref: DeviceResponse.swift
 */
public class DeviceResponse <: CBOREncodable {
    public let version: String
    public let documents: ?ArrayList<Document>
    public let documentErrors: ?ArrayList<DocumentError>
    public let status: UInt64

    /** Default version per ISO 18013-5 §8.3. */
    public static let DEFAULT_VERSION: String = "1.0"
    /** Version 1.1 (ZK documents). */
    public static let VERSION_1_1: String = "1.1"

    static let KEY_VERSION = "version"
    static let KEY_DOCUMENTS = "documents"
    static let KEY_DOCUMENT_ERRORS = "documentErrors"
    static let KEY_STATUS = "status"

    public init(
        version: String,
        documents: ?ArrayList<Document>,
        documentErrors: ?ArrayList<DocumentError>,
        status: UInt64
    ) {
        this.version = version
        this.documents = documents
        this.documentErrors = documentErrors
        this.status = status
    }

    /**
     * Decode from raw CBOR bytes (convenience entry point mirroring iOS init(data:)).
     * Throws MdocValidationError if the bytes cannot be decoded or the structure is invalid.
     */
    public static func fromCborBytes(bytes: Array<UInt8>): DeviceResponse {
        let cbor: CborValue
        try {
            cbor = decodeCbor(bytes)
        } catch (_: Exception) {
            throw MdocValidationError.cborDecodingError()
        }
        return DeviceResponse.fromCbor(cbor)
    }

    /**
     * Decode from a CborValue map.
     * Throws MdocValidationError if:
     *   - cbor is not a map
     *   - version field is absent or malformed
     *   - documents array is present but empty
     *   - documentErrors array is present but empty
     *   - status field is absent
     */
    public static func fromCbor(cbor: CborValue): DeviceResponse {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let versionOpt = cbor.field(CborValue.TextStringVal(KEY_VERSION))
                let versionVal: String
                match (versionOpt) {
                    case Some(CborValue.TextStringVal(s)) => versionVal = s
                    case _ => throw MdocValidationError.missingField("DeviceResponse", KEY_VERSION)
                }

                let docsOpt: ?ArrayList<Document>
                let docsFieldOpt = cbor.field(CborValue.TextStringVal(KEY_DOCUMENTS))
                match (docsFieldOpt) {
                    case Some(CborValue.ArrayVal(docsCbors)) =>
                        if (docsCbors.size == 0) {
                            throw MdocValidationError.invalidCbor("DeviceResponse.documents empty array")
                        }
                        let parsedDocs = ArrayList<Document>()
                        for (dc in docsCbors) {
                            parsedDocs.add(Document.fromCbor(dc))
                        }
                        docsOpt = Some(parsedDocs)
                    case _ =>
                        docsOpt = None
                }

                let docErrorsOpt: ?ArrayList<DocumentError>
                let docErrorsFieldOpt = cbor.field(CborValue.TextStringVal(KEY_DOCUMENT_ERRORS))
                match (docErrorsFieldOpt) {
                    case Some(CborValue.ArrayVal(deCbors)) =>
                        if (deCbors.size == 0) {
                            throw MdocValidationError.invalidCbor("DeviceResponse.documentErrors empty array")
                        }
                        let parsedDocErrors = ArrayList<DocumentError>()
                        for (dec in deCbors) {
                            parsedDocErrors.add(DocumentError.fromCbor(dec))
                        }
                        docErrorsOpt = Some(parsedDocErrors)
                    case _ =>
                        docErrorsOpt = None
                }

                let statusOpt = cbor.field(CborValue.TextStringVal(KEY_STATUS))
                let statusVal: UInt64
                match (statusOpt) {
                    case Some(CborValue.UInt64Val(s)) => statusVal = s
                    case _ => throw MdocValidationError.missingField("DeviceResponse", KEY_STATUS)
                }

                return DeviceResponse(versionVal, docsOpt, docErrorsOpt, statusVal)
            case _ =>
                throw MdocValidationError.invalidCbor("device response")
        }
    }

    /**
     * Encode to CBOR map.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal(DeviceResponse.KEY_VERSION), CborValue.TextStringVal(this.version)))
        match (this.documents) {
            case Some(docs) =>
                let docItems = ArrayList<CborValue>()
                for (doc in docs) {
                    docItems.add(doc.toCbor())
                }
                pairs.add((CborValue.TextStringVal(DeviceResponse.KEY_DOCUMENTS), CborValue.ArrayVal(docItems)))
            case None => ()
        }
        match (this.documentErrors) {
            case Some(deList) =>
                let deItems = ArrayList<CborValue>()
                for (de in deList) {
                    deItems.add(de.toCbor())
                }
                pairs.add((CborValue.TextStringVal(DeviceResponse.KEY_DOCUMENT_ERRORS), CborValue.ArrayVal(deItems)))
            case None => ()
        }
        pairs.add((CborValue.TextStringVal(DeviceResponse.KEY_STATUS), CborValue.UInt64Val(this.status)))
        return CborValue.MapVal(pairs)
    }
}
