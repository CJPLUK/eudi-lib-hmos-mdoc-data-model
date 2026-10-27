/*
 * mobile_security_object.cj
 *
 * ISO 18013-5 §9.1.2 — Mobile Security Object (MSO) and IssuerAuth structures.
 *
 * Types defined here (mirrors iOS IssuerAuth/ directory, 7 source files):
 *   DigestAlgorithmKind  — Table 21 digest algorithm identifiers
 *   DigestIDs            — {digestID → digest_bytes} map (per namespace)
 *   ValueDigests         — {namespace → DigestIDs} outer map
 *   ValidityInfo         — signed / validFrom / validUntil timestamps (tdate)
 *   KeyAuthorizations    — optional authorised namespaces + data elements
 *   DeviceKeyInfo        — wraps deviceKey as CborValue (generic; no CoseKey dependency)
 *   StatusIdentifier     — optional revocation status pointer
 *   MobileSecurityObject — full MSO; encoded as Tag-24 bstr inside IssuerAuth payload
 *   IssuerAuth           — COSE_Sign1 container with embedded MSO payload
 *
 * Design notes:
 *   - MSO wire format: #6.24(bstr .cbor MobileSecurityObject)
 *     i.e. Tag 24 → ByteString → re-parsed CBOR map
 *   - IssuerAuth wire format: COSE_Sign1 (tag 18) [protected, unprotected, payload, sig]
 *     where payload = bstr holding the Tag-24-wrapped MSO bytes
 *   - DeviceKeyInfo.deviceKey is kept as CborValue (COSE_Key map) to avoid a hard
 *     dependency on the engagement feature's CoseKey type; cross-feature unification
 *     is deferred to a later supervisor coordination round.
 *   - ValidityInfo timestamps use CBOR tag-0 (tdate / RFC 3339 strings).
 *     ISO 18013-5 forbids fractional seconds in these fields.
 *
 * iOS references:
 *   Sources/MdocDataModel18013/IssuerAuth/MobileSecurityObject.swift
 *   Sources/MdocDataModel18013/IssuerAuth/IssuerAuth.swift
 *   Sources/MdocDataModel18013/IssuerAuth/ValueDigests.swift
 *   Sources/MdocDataModel18013/IssuerAuth/DigestIDs.swift
 *   Sources/MdocDataModel18013/IssuerAuth/ValidityInfo.swift
 *   Sources/MdocDataModel18013/IssuerAuth/DeviceKeyInfo.swift
 *   Sources/MdocDataModel18013/IssuerAuth/StatusIdentifier.swift
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth

import std.collection.ArrayList
import std.collection.HashMap

import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.CborTag
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor
import ohos_app_cangjie_eudi_cjcbor.cbor.encodeEmbedded
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeEmbedded

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CBOREncodable
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MdocValidationError
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CoseSign1

/* ===================================================================== */
/* Type aliases                                                           */
/* ===================================================================== */

/** NameSpace is a UTF-8 string identifying a data element namespace. */
public type NameSpace = String

/** DigestID is an unsigned integer key within a DigestIDs map. */
public type DigestID = UInt64

/* ===================================================================== */
/* DigestAlgorithmKind — Table 21 digest algorithm identifiers           */
/* ===================================================================== */

/**
 * Digest algorithm identifiers used in MSO.digestAlgorithm.
 * Mirrors iOS DigestAlgorithmKind enum.
 */
public enum DigestAlgorithmKind {
    | Sha256   // "SHA-256"
    | Sha384   // "SHA-384"
    | Sha512   // "SHA-512"

    /** Return the canonical string identifier used in CBOR encoding. */
    public func stringValue(): String {
        match (this) {
            case Sha256 => return "SHA-256"
            case Sha384 => return "SHA-384"
            case Sha512 => return "SHA-512"
        }
    }

    /** Parse from the string identifier. Returns None if unrecognised. */
    public static func fromString(s: String): ?DigestAlgorithmKind {
        match (s) {
            case "SHA-256" => return Some(Sha256)
            case "SHA-384" => return Some(Sha384)
            case "SHA-512" => return Some(Sha512)
            case _ => return None
        }
    }
}

/* ===================================================================== */
/* DigestIDs — {digestID: UInt64 → digest_bytes: Array<UInt8>}          */
/* ===================================================================== */

/**
 * Per-namespace digest map: maps each DigestID to its digest byte string.
 *
 * CBOR wire form:  map(uint → bstr)*
 * iOS ref: DigestIDs.swift
 */
public class DigestIDs <: CBOREncodable {
    /** The underlying map from digestID to digest bytes. */
    public let digestIDs: HashMap<DigestID, Array<UInt8>>

    public init(digestIDs: HashMap<DigestID, Array<UInt8>>) {
        this.digestIDs = digestIDs
    }

    /** Subscript access by DigestID. */
    public func get(digestID: DigestID): ?Array<UInt8> {
        return this.digestIDs.get(digestID)
    }

    /**
     * Decode from a CBOR map of uint → bstr entries.
     * Throws MdocValidationError if the structure is invalid or empty.
     */
    public static func fromCbor(cbor: CborValue): DigestIDs {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let temp = HashMap<DigestID, Array<UInt8>>()
                for ((k, v) in pairs) {
                    match ((k, v)) {
                        case (CborValue.UInt64Val(digestId), CborValue.ByteStringVal(digestBytes)) =>
                            temp.add(digestId, digestBytes)
                        case _ => ()
                    }
                }
                if (temp.size == 0) {
                    throw MdocValidationError.invalidCbor("DigestIDs: empty or no valid uint->bstr entries")
                }
                return DigestIDs(temp)
            case _ =>
                throw MdocValidationError.invalidCbor("DigestIDs")
        }
    }

    /**
     * Encode to CBOR map of uint → bstr.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        for ((k, v) in this.digestIDs) {
            pairs.add((CborValue.UInt64Val(k), CborValue.ByteStringVal(v)))
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* ValueDigests — {namespace: String → DigestIDs}                        */
/* ===================================================================== */

/**
 * Outer digest map: one DigestIDs entry per namespace.
 *
 * CBOR wire form:  map(tstr → map(uint → bstr)*)*
 * iOS ref: ValueDigests.swift
 */
public class ValueDigests <: CBOREncodable {
    /** The underlying map from namespace string to DigestIDs. */
    public let valueDigests: HashMap<NameSpace, DigestIDs>

    public init(valueDigests: HashMap<NameSpace, DigestIDs>) {
        this.valueDigests = valueDigests
    }

    /** Subscript access by NameSpace. */
    public func get(ns: NameSpace): ?DigestIDs {
        return this.valueDigests.get(ns)
    }

    /**
     * Decode from a CBOR map of tstr → map entries.
     * Throws MdocValidationError if the outer CBOR is not a map.
     */
    public static func fromCbor(cbor: CborValue): ValueDigests {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let temp = HashMap<NameSpace, DigestIDs>()
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.TextStringVal(ns) =>
                            let ids = DigestIDs.fromCbor(v)
                            temp.add(ns, ids)
                        case _ => ()
                    }
                }
                return ValueDigests(temp)
            case _ =>
                throw MdocValidationError.invalidCbor("ValueDigests")
        }
    }

    /**
     * Encode to CBOR map of tstr → map(uint → bstr).
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        for ((ns, ids) in this.valueDigests) {
            pairs.add((CborValue.TextStringVal(ns), ids.toCbor()))
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* ValidityInfo — signed / validFrom / validUntil timestamps             */
/* ===================================================================== */

/**
 * Validity information for the MSO.
 *
 * All timestamps are RFC 3339 strings stored as CBOR tag-0 (tdate).
 * ISO 18013-5 forbids fractional seconds (no '.' in the datetime string).
 *
 * CBOR wire form:
 *   {
 *     "signed"        : #6.0(tstr),
 *     "validFrom"     : #6.0(tstr),
 *     "validUntil"    : #6.0(tstr),
 *     "expectedUpdate": #6.0(tstr)  // optional
 *   }
 *
 * iOS ref: ValidityInfo.swift
 */
public class ValidityInfo <: CBOREncodable {
    public let signed: String
    public let validFrom: String
    public let validUntil: String
    public let expectedUpdate: ?String

    static let KEY_SIGNED = "signed"
    static let KEY_VALID_FROM = "validFrom"
    static let KEY_VALID_UNTIL = "validUntil"
    static let KEY_EXPECTED_UPDATE = "expectedUpdate"

    public init(signed: String, validFrom: String, validUntil: String, expectedUpdate: ?String) {
        this.signed = signed
        this.validFrom = validFrom
        this.validUntil = validUntil
        this.expectedUpdate = expectedUpdate
    }

    /**
     * Helper: extract a tdate string from a CborValue.
     * A tdate is CborValue.TaggedVal(CborTag.STANDARD_DATE_TIME, CborValue.TextStringVal(s)).
     * Throws if the value is not a valid tdate or contains fractional seconds.
     */
    static func extractTdate(cbor: CborValue, component: String, field: String): String {
        match (cbor) {
            case CborValue.TaggedVal(tag, inner) =>
                if (tag != CborTag.STANDARD_DATE_TIME) {
                    throw MdocValidationError.missingField(component, field)
                }
                match (inner) {
                    case CborValue.TextStringVal(s) =>
                        if (s.contains(".")) {
                            throw MdocValidationError.invalidDateTimeFormat(component, field)
                        }
                        return s
                    case _ =>
                        throw MdocValidationError.missingField(component, field)
                }
            case _ =>
                throw MdocValidationError.missingField(component, field)
        }
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if required fields are absent or malformed.
     */
    public static func fromCbor(cbor: CborValue): ValidityInfo {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let signedOpt = cbor.field(CborValue.TextStringVal(KEY_SIGNED))
                match (signedOpt) {
                    case None =>
                        throw MdocValidationError.missingField("ValidityInfo", KEY_SIGNED)
                    case Some(signedCbor) =>
                        let signedVal = ValidityInfo.extractTdate(signedCbor, "ValidityInfo", KEY_SIGNED)
                        let validFromOpt = cbor.field(CborValue.TextStringVal(KEY_VALID_FROM))
                        match (validFromOpt) {
                            case None =>
                                throw MdocValidationError.missingField("ValidityInfo", KEY_VALID_FROM)
                            case Some(validFromCbor) =>
                                let validFromVal = ValidityInfo.extractTdate(validFromCbor, "ValidityInfo", KEY_VALID_FROM)
                                let validUntilOpt = cbor.field(CborValue.TextStringVal(KEY_VALID_UNTIL))
                                match (validUntilOpt) {
                                    case None =>
                                        throw MdocValidationError.missingField("ValidityInfo", KEY_VALID_UNTIL)
                                    case Some(validUntilCbor) =>
                                        let validUntilVal = ValidityInfo.extractTdate(validUntilCbor, "ValidityInfo", KEY_VALID_UNTIL)
                                        let expectedUpdateVal: ?String
                                        let expectedUpdateOpt = cbor.field(CborValue.TextStringVal(KEY_EXPECTED_UPDATE))
                                        match (expectedUpdateOpt) {
                                            case Some(euCbor) =>
                                                match (euCbor) {
                                                    case CborValue.TaggedVal(tag, inner) =>
                                                        if (tag == CborTag.STANDARD_DATE_TIME) {
                                                            match (inner) {
                                                                case CborValue.TextStringVal(s) =>
                                                                    if (s.contains(".")) {
                                                                        throw MdocValidationError.invalidDateTimeFormat("ValidityInfo", KEY_EXPECTED_UPDATE)
                                                                    }
                                                                    expectedUpdateVal = Some(s)
                                                                case _ =>
                                                                    expectedUpdateVal = None
                                                            }
                                                        } else {
                                                            expectedUpdateVal = None
                                                        }
                                                    case _ =>
                                                        expectedUpdateVal = None
                                                }
                                            case None =>
                                                expectedUpdateVal = None
                                        }
                                        return ValidityInfo(signedVal, validFromVal, validUntilVal, expectedUpdateVal)
                                }
                        }
                }
            case _ =>
                throw MdocValidationError.invalidCbor("ValidityInfo")
        }
    }

    /**
     * Encode to CBOR map with tdate-tagged string values.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((
            CborValue.TextStringVal(ValidityInfo.KEY_SIGNED),
            CborValue.TaggedVal(CborTag.STANDARD_DATE_TIME, CborValue.TextStringVal(this.signed))
        ))
        pairs.add((
            CborValue.TextStringVal(ValidityInfo.KEY_VALID_FROM),
            CborValue.TaggedVal(CborTag.STANDARD_DATE_TIME, CborValue.TextStringVal(this.validFrom))
        ))
        pairs.add((
            CborValue.TextStringVal(ValidityInfo.KEY_VALID_UNTIL),
            CborValue.TaggedVal(CborTag.STANDARD_DATE_TIME, CborValue.TextStringVal(this.validUntil))
        ))
        match (this.expectedUpdate) {
            case Some(eu) =>
                pairs.add((
                    CborValue.TextStringVal(ValidityInfo.KEY_EXPECTED_UPDATE),
                    CborValue.TaggedVal(CborTag.STANDARD_DATE_TIME, CborValue.TextStringVal(eu))
                ))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* KeyAuthorizations — optional key capability constraints               */
/* ===================================================================== */

/**
 * Contains the namespaces and/or data elements the device key is authorised to sign.
 *
 * CBOR wire form:
 *   {
 *     "nameSpaces"   : [tstr*],                     // optional
 *     "dataElements" : {tstr : [tstr*]*}             // optional
 *   }
 *
 * iOS ref: DeviceKeyInfo.swift (KeyAuthorizations struct)
 */
public class KeyAuthorizations <: CBOREncodable {
    public let nameSpaces: ?ArrayList<String>
    public let dataElements: ?HashMap<String, ArrayList<String>>

    static let KEY_NAMESPACES = "nameSpaces"
    static let KEY_DATA_ELEMENTS = "dataElements"

    public init(nameSpaces: ?ArrayList<String>, dataElements: ?HashMap<String, ArrayList<String>>) {
        this.nameSpaces = nameSpaces
        this.dataElements = dataElements
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if the outer CBOR is not a map.
     */
    public static func fromCbor(cbor: CborValue): KeyAuthorizations {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let nsOpt: ?ArrayList<String>
                let nsFieldOpt = cbor.field(CborValue.TextStringVal(KEY_NAMESPACES))
                match (nsFieldOpt) {
                    case Some(CborValue.ArrayVal(nsItems)) =>
                        let nsList = ArrayList<String>()
                        for (item in nsItems) {
                            match (item) {
                                case CborValue.TextStringVal(s) => nsList.add(s)
                                case _ => ()
                            }
                        }
                        if (nsList.size > 0) {
                            nsOpt = Some(nsList)
                        } else {
                            nsOpt = None
                        }
                    case _ => nsOpt = None
                }
                let deOpt: ?HashMap<String, ArrayList<String>>
                let deFieldOpt = cbor.field(CborValue.TextStringVal(KEY_DATA_ELEMENTS))
                match (deFieldOpt) {
                    case Some(CborValue.MapVal(dePairs)) =>
                        let deMap = HashMap<String, ArrayList<String>>()
                        for ((k, v) in dePairs) {
                            match ((k, v)) {
                                case (CborValue.TextStringVal(ns), CborValue.ArrayVal(elemItems)) =>
                                    let elems = ArrayList<String>()
                                    for (ei in elemItems) {
                                        match (ei) {
                                            case CborValue.TextStringVal(s) => elems.add(s)
                                            case _ => ()
                                        }
                                    }
                                    if (elems.size > 0) {
                                        deMap.add(ns, elems)
                                    }
                                case _ => ()
                            }
                        }
                        if (deMap.size > 0) {
                            deOpt = Some(deMap)
                        } else {
                            deOpt = None
                        }
                    case _ => deOpt = None
                }
                return KeyAuthorizations(nsOpt, deOpt)
            case _ =>
                throw MdocValidationError.invalidCbor("KeyAuthorizations")
        }
    }

    /**
     * Encode to CBOR map.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        match (this.nameSpaces) {
            case Some(nsList) =>
                let nsItems = ArrayList<CborValue>()
                for (ns in nsList) {
                    nsItems.add(CborValue.TextStringVal(ns))
                }
                pairs.add((
                    CborValue.TextStringVal(KeyAuthorizations.KEY_NAMESPACES),
                    CborValue.ArrayVal(nsItems)
                ))
            case None => ()
        }
        match (this.dataElements) {
            case Some(deMap) =>
                let dePairs = ArrayList<(CborValue, CborValue)>()
                for ((ns, elems) in deMap) {
                    let elemItems = ArrayList<CborValue>()
                    for (e in elems) {
                        elemItems.add(CborValue.TextStringVal(e))
                    }
                    dePairs.add((CborValue.TextStringVal(ns), CborValue.ArrayVal(elemItems)))
                }
                pairs.add((
                    CborValue.TextStringVal(KeyAuthorizations.KEY_DATA_ELEMENTS),
                    CborValue.MapVal(dePairs)
                ))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* DeviceKeyInfo — mdoc authentication public key info                   */
/* ===================================================================== */

/**
 * Device key information: holds the device public key (as a generic CborValue)
 * plus optional authorisations and key-info metadata.
 *
 * The deviceKey is stored as CborValue (COSE_Key map form) to avoid
 * a cross-feature dependency on the engagement feature's CoseKey type.
 *
 * CBOR wire form:
 *   {
 *     "deviceKey"        : COSE_Key map,
 *     "keyAuthorizations": { ... }    // optional
 *     "keyInfo"          : any        // optional
 *   }
 *
 * iOS ref: DeviceKeyInfo.swift
 */
public class DeviceKeyInfo <: CBOREncodable {
    public let deviceKey: CborValue
    public let keyAuthorizations: ?KeyAuthorizations
    public let keyInfo: ?CborValue

    static let KEY_DEVICE_KEY = "deviceKey"
    static let KEY_KEY_AUTHORIZATIONS = "keyAuthorizations"
    static let KEY_KEY_INFO = "keyInfo"

    public init(deviceKey: CborValue, keyAuthorizations: ?KeyAuthorizations, keyInfo: ?CborValue) {
        this.deviceKey = deviceKey
        this.keyAuthorizations = keyAuthorizations
        this.keyInfo = keyInfo
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if the deviceKey field is absent.
     */
    public static func fromCbor(cbor: CborValue): DeviceKeyInfo {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let deviceKeyOpt = cbor.field(CborValue.TextStringVal(KEY_DEVICE_KEY))
                match (deviceKeyOpt) {
                    case None =>
                        throw MdocValidationError.missingField("DeviceKeyInfo", KEY_DEVICE_KEY)
                    case Some(deviceKeyCbor) =>
                        let keyAuthOpt: ?KeyAuthorizations
                        let kaFieldOpt = cbor.field(CborValue.TextStringVal(KEY_KEY_AUTHORIZATIONS))
                        match (kaFieldOpt) {
                            case Some(kaCbor) =>
                                keyAuthOpt = Some(KeyAuthorizations.fromCbor(kaCbor))
                            case None =>
                                keyAuthOpt = None
                        }
                        let keyInfoOpt = cbor.field(CborValue.TextStringVal(KEY_KEY_INFO))
                        return DeviceKeyInfo(deviceKeyCbor, keyAuthOpt, keyInfoOpt)
                }
            case _ =>
                throw MdocValidationError.invalidCbor("DeviceKeyInfo")
        }
    }

    /**
     * Encode to CBOR map.
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal(DeviceKeyInfo.KEY_DEVICE_KEY), this.deviceKey))
        match (this.keyAuthorizations) {
            case Some(ka) =>
                pairs.add((
                    CborValue.TextStringVal(DeviceKeyInfo.KEY_KEY_AUTHORIZATIONS),
                    ka.toCbor()
                ))
            case None => ()
        }
        match (this.keyInfo) {
            case Some(ki) =>
                pairs.add((CborValue.TextStringVal(DeviceKeyInfo.KEY_KEY_INFO), ki))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}

/* ===================================================================== */
/* StatusIdentifier — optional revocation status list pointer            */
/* ===================================================================== */

/**
 * Revocation status list pointer extracted from the MSO "status" field.
 *
 * iOS ref: StatusIdentifier.swift
 */
public class StatusIdentifier {
    public let idx: Int64
    public let uriString: String

    public init(idx: Int64, uriString: String) {
        this.idx = idx
        this.uriString = uriString
    }

    /**
     * Try to extract a StatusIdentifier from already-decoded MSO map CBOR.
     * Returns None if the "status" field is absent or malformed.
     */
    public static func fromMsoCbor(msoCbor: CborValue): ?StatusIdentifier {
        let statusFieldOpt = msoCbor.field(CborValue.TextStringVal("status"))
        match (statusFieldOpt) {
            case None => return None
            case Some(statusCbor) =>
                let statusListOpt = statusCbor.field(CborValue.TextStringVal("status_list"))
                match (statusListOpt) {
                    case None => return None
                    case Some(statusListCbor) =>
                        let idxOpt = statusListCbor.field(CborValue.TextStringVal("idx"))
                        let uriOpt = statusListCbor.field(CborValue.TextStringVal("uri"))
                        match ((idxOpt, uriOpt)) {
                            case (Some(CborValue.UInt64Val(idxVal)), Some(CborValue.TextStringVal(uriVal))) =>
                                return Some(StatusIdentifier(Int64(idxVal), uriVal))
                            case _ => return None
                        }
                }
        }
    }
}

/* ===================================================================== */
/* MobileSecurityObject — ISO 18013-5 §9.1.2 MSO                        */
/* ===================================================================== */

/**
 * Mobile Security Object (MSO).
 *
 * On the wire, the MSO is wrapped as Tag-24 (encoded-CBOR):
 *   IssuerAuth.payload = bstr holding #6.24(bstr .cbor MSO_map)
 *
 * This class implements both CBOREncodable (for producing the inner map) and
 * provides fromCborBytes / fromCborMap factory methods for decoding.
 *
 * CBOR map wire form (field order from iOS reference):
 *   {
 *     "version"         : tstr,
 *     "digestAlgorithm" : tstr,
 *     "valueDigests"    : { tstr : { uint : bstr }* }*,
 *     "deviceKeyInfo"   : { "deviceKey" : COSE_Key, ... },
 *     "docType"         : tstr,
 *     "validityInfo"    : { ... }
 *   }
 *
 * iOS ref: MobileSecurityObject.swift
 */
public class MobileSecurityObject <: CBOREncodable {
    public let version: String
    /** Default version per ISO 18013-5. */
    public static let DEFAULT_VERSION: String = "1.0"
    public let digestAlgorithm: String
    public let valueDigests: ValueDigests
    public let deviceKeyInfo: DeviceKeyInfo
    public let docType: String
    public let validityInfo: ValidityInfo

    static let KEY_VERSION = "version"
    static let KEY_DIGEST_ALGORITHM = "digestAlgorithm"
    static let KEY_VALUE_DIGESTS = "valueDigests"
    static let KEY_DEVICE_KEY_INFO = "deviceKeyInfo"
    static let KEY_DOC_TYPE = "docType"
    static let KEY_VALIDITY_INFO = "validityInfo"

    public init(
        version: String,
        digestAlgorithm: String,
        valueDigests: ValueDigests,
        deviceKeyInfo: DeviceKeyInfo,
        docType: String,
        validityInfo: ValidityInfo
    ) {
        this.version = version
        this.digestAlgorithm = digestAlgorithm
        this.valueDigests = valueDigests
        this.deviceKeyInfo = deviceKeyInfo
        this.docType = docType
        this.validityInfo = validityInfo
    }

    /**
     * Decode from a CBOR map (inner MSO map, not Tag-24 wrapped).
     * Throws MdocValidationError if any required field is absent or malformed.
     */
    public static func fromCborMap(cbor: CborValue): MobileSecurityObject {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let versionOpt = cbor.field(CborValue.TextStringVal(KEY_VERSION))
                let versionVal: String
                match (versionOpt) {
                    case Some(CborValue.TextStringVal(s)) => versionVal = s
                    case _ => throw MdocValidationError.missingField("MobileSecurityObject", KEY_VERSION)
                }
                let digestAlgOpt = cbor.field(CborValue.TextStringVal(KEY_DIGEST_ALGORITHM))
                let digestAlgVal: String
                match (digestAlgOpt) {
                    case Some(CborValue.TextStringVal(s)) => digestAlgVal = s
                    case _ => throw MdocValidationError.missingField("MobileSecurityObject", KEY_DIGEST_ALGORITHM)
                }
                let vdOpt = cbor.field(CborValue.TextStringVal(KEY_VALUE_DIGESTS))
                match (vdOpt) {
                    case None => throw MdocValidationError.missingField("MobileSecurityObject", KEY_VALUE_DIGESTS)
                    case Some(vdCbor) =>
                        let vd = ValueDigests.fromCbor(vdCbor)
                        let dkiOpt = cbor.field(CborValue.TextStringVal(KEY_DEVICE_KEY_INFO))
                        match (dkiOpt) {
                            case None => throw MdocValidationError.missingField("MobileSecurityObject", KEY_DEVICE_KEY_INFO)
                            case Some(dkiCbor) =>
                                let dki = DeviceKeyInfo.fromCbor(dkiCbor)
                                let docTypeOpt = cbor.field(CborValue.TextStringVal(KEY_DOC_TYPE))
                                let docTypeVal: String
                                match (docTypeOpt) {
                                    case Some(CborValue.TextStringVal(s)) => docTypeVal = s
                                    case _ => throw MdocValidationError.missingField("MobileSecurityObject", KEY_DOC_TYPE)
                                }
                                let viOpt = cbor.field(CborValue.TextStringVal(KEY_VALIDITY_INFO))
                                match (viOpt) {
                                    case None => throw MdocValidationError.missingField("MobileSecurityObject", KEY_VALIDITY_INFO)
                                    case Some(viCbor) =>
                                        let vi = ValidityInfo.fromCbor(viCbor)
                                        return MobileSecurityObject(
                                            versionVal, digestAlgVal, vd, dki, docTypeVal, vi
                                        )
                                }
                        }
                }
            case _ =>
                throw MdocValidationError.invalidCbor("MobileSecurityObject")
        }
    }

    /**
     * Decode from Tag-24-wrapped bytes as found in CoseSign1.payload.
     *
     * Wire format: payload = bstr containing #6.24(bstr .cbor MSO_map)
     * i.e. the payload bytes ARE the Tag-24 wrapper; we decode it once to get
     * the inner MSO CBOR map, then call fromCborMap.
     *
     * Throws MdocValidationError if the bytes are malformed.
     */
    public static func fromTag24Bytes(bytes: Array<UInt8>): MobileSecurityObject {
        let outer: CborValue
        try {
            outer = decodeCbor(bytes)
        } catch (_: Exception) {
            throw MdocValidationError.invalidCbor("MobileSecurityObject: cannot decode outer CBOR")
        }
        let inner: CborValue
        try {
            inner = decodeEmbedded(outer)
        } catch (_: Exception) {
            throw MdocValidationError.invalidCbor("MobileSecurityObject: expected Tag-24 wrapper")
        }
        return MobileSecurityObject.fromCborMap(inner)
    }

    /**
     * Encode to CBOR map (inner MSO map).
     * To get the Tag-24-wrapped form use toTag24Cbor() or toTag24Bytes().
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal(MobileSecurityObject.KEY_VERSION), CborValue.TextStringVal(this.version)))
        pairs.add((CborValue.TextStringVal(MobileSecurityObject.KEY_DIGEST_ALGORITHM), CborValue.TextStringVal(this.digestAlgorithm)))
        pairs.add((CborValue.TextStringVal(MobileSecurityObject.KEY_VALUE_DIGESTS), this.valueDigests.toCbor()))
        pairs.add((CborValue.TextStringVal(MobileSecurityObject.KEY_DEVICE_KEY_INFO), this.deviceKeyInfo.toCbor()))
        pairs.add((CborValue.TextStringVal(MobileSecurityObject.KEY_DOC_TYPE), CborValue.TextStringVal(this.docType)))
        pairs.add((CborValue.TextStringVal(MobileSecurityObject.KEY_VALIDITY_INFO), this.validityInfo.toCbor()))
        return CborValue.MapVal(pairs)
    }

    /**
     * Encode to Tag-24-wrapped CborValue: #6.24(bstr .cbor MSO_map).
     * This is the form used as the payload of a CoseSign1 IssuerAuth.
     */
    public func toTag24Cbor(): CborValue {
        return encodeEmbedded(this.toCbor())
    }

    /**
     * Encode the Tag-24 wrapper to raw bytes.
     * These bytes become the payload of the outer CoseSign1 structure.
     */
    public func toTag24Bytes(): Array<UInt8> {
        return this.toTag24Cbor().encode()
    }
}

/* ===================================================================== */
/* IssuerAuth — COSE_Sign1 container with embedded MSO                  */
/* ===================================================================== */

/**
 * IssuerAuth: a COSE_Sign1 message (tag 18) where the payload is the
 * Tag-24-wrapped Mobile Security Object.
 *
 * Wire form (RFC 8152 §4.2):
 *   #6.18([
 *     protected   : bstr .cbor { 1: alg },
 *     unprotected : { 33: x5chain_bytes_or_array },
 *     payload     : bstr,                   // Tag-24-wrapped MSO
 *     signature   : bstr
 *   ])
 *
 * The x5chain (header key 33) in the unprotected header may be a single
 * bstr (one certificate) or an array of bstr (certificate chain).
 *
 * iOS ref: IssuerAuth.swift
 */
public class IssuerAuth <: CBOREncodable {
    public let mso: MobileSecurityObject
    /** Raw Tag-24-wrapped MSO bytes (= payload field of CoseSign1). */
    public let msoRawData: Array<UInt8>
    public let verifyAlgorithm: Int64
    public let signature: Array<UInt8>
    /** Certificate chain (DER bytes per certificate). */
    public let x5chain: ArrayList<Array<UInt8>>
    /** Optional revocation status pointer parsed from MSO. */
    public let statusIdentifier: ?StatusIdentifier

    /** COSE unprotected header key for x5chain: integer 33. */
    static let X5CHAIN_HEADER_KEY: UInt64 = 33

    public init(
        mso: MobileSecurityObject,
        msoRawData: Array<UInt8>,
        verifyAlgorithm: Int64,
        signature: Array<UInt8>,
        x5chain: ArrayList<Array<UInt8>>,
        statusIdentifier: ?StatusIdentifier
    ) {
        this.mso = mso
        this.msoRawData = msoRawData
        this.verifyAlgorithm = verifyAlgorithm
        this.signature = signature
        this.x5chain = x5chain
        this.statusIdentifier = statusIdentifier
    }

    /**
     * Decode from a tagged COSE_Sign1 CborValue (tag 18).
     *
     * Steps:
     *   1. Unwrap tag-18 → CoseSign1 array
     *   2. Extract payload bytes (= Tag-24-wrapped MSO bytes)
     *   3. Decode MSO from the Tag-24 bytes
     *   4. Extract algorithm from protected header
     *   5. Extract x5chain from unprotected header (key 33)
     *   6. Extract StatusIdentifier from MSO raw bytes (optional)
     *
     * Throws MdocValidationError on any structural violation.
     */
    public static func fromCbor(cbor: CborValue): IssuerAuth {
        // ISO 18013-5: IssuerAuth is an *untagged* COSE_Sign1 (bare 4-element
        // array), matching ReaderAuth/DeviceAuth. Decode the bare form first;
        // tolerate a legacy tag-18 wrapper on input for lenient interop.
        var coseOpt = CoseSign1.fromCborArray(cbor)
        match (coseOpt) {
            case None => coseOpt = CoseSign1.fromTaggedCbor(cbor)
            case _ => ()
        }
        let cose: CoseSign1
        match (coseOpt) {
            case None =>
                throw MdocValidationError.invalidCbor("IssuerAuth must be a COSE_Sign1 (untagged 4-element array per ISO 18013-5)")
            case Some(c) => cose = c
        }

        let msoBytes: Array<UInt8>
        match (cose.payload) {
            case None =>
                throw MdocValidationError.invalidCbor("IssuerAuth must contain a non-detached payload")
            case Some(b) => msoBytes = b
        }

        let mso = MobileSecurityObject.fromTag24Bytes(msoBytes)

        let algVal: Int64
        match (cose.protectedHeader.algorithm) {
            case None =>
                throw MdocValidationError.invalidCbor("IssuerAuth: protected header missing algorithm")
            case Some(a) => algVal = a
        }

        let x5chainList = ArrayList<Array<UInt8>>()
        let uphOpt = cose.unprotectedHeader
        match (uphOpt) {
            case None =>
                throw MdocValidationError.invalidCbor("IssuerAuth must contain a valid unprotected header")
            case Some(uph) =>
                let uphRawOpt = uph.rawHeaderBytes
                match (uphRawOpt) {
                    case None =>
                        throw MdocValidationError.invalidCbor("IssuerAuth: unprotected header has no bytes")
                    case Some(uphBytes) =>
                        let uphCbor: CborValue
                        try {
                            uphCbor = decodeCbor(uphBytes)
                        } catch (_: Exception) {
                            throw MdocValidationError.invalidCbor("IssuerAuth: cannot decode unprotected header")
                        }
                        let x5chainKeyOpt = uphCbor.field(CborValue.UInt64Val(X5CHAIN_HEADER_KEY))
                        match (x5chainKeyOpt) {
                            case None =>
                                throw MdocValidationError.invalidCbor("IssuerAuth must contain a valid x5chain")
                            case Some(x5Val) =>
                                match (x5Val) {
                                    case CborValue.ByteStringVal(certBytes) =>
                                        x5chainList.add(certBytes)
                                    case CborValue.ArrayVal(certArray) =>
                                        for (item in certArray) {
                                            match (item) {
                                                case CborValue.ByteStringVal(certBytes) =>
                                                    x5chainList.add(certBytes)
                                                case _ =>
                                                    throw MdocValidationError.invalidCbor("IssuerAuth: x5chain array elements must be byte strings")
                                            }
                                        }
                                    case _ =>
                                        throw MdocValidationError.invalidCbor("IssuerAuth must contain a valid x5chain")
                                }
                        }
                }
        }

        if (x5chainList.size == 0) {
            throw MdocValidationError.invalidCbor("IssuerAuth must contain a valid x5chain")
        }

        let statusId = IssuerAuth.extractStatusIdentifier(msoBytes)

        return IssuerAuth(mso, msoBytes, algVal, cose.signature, x5chainList, statusId)
    }

    /**
     * Extract optional StatusIdentifier from Tag-24-wrapped MSO bytes.
     * Returns None if the bytes are malformed or "status" field is absent.
     */
    static func extractStatusIdentifier(msoBytes: Array<UInt8>): ?StatusIdentifier {
        try {
            let outerCbor = decodeCbor(msoBytes)
            let innerCbor = decodeEmbedded(outerCbor)
            return StatusIdentifier.fromMsoCbor(innerCbor)
        } catch (_: Exception) {
            return None
        }
    }

    /**
     * Encode to a tagged COSE_Sign1 CborValue (tag 18).
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let x5chainValue: CborValue
        if (this.x5chain.size == 1) {
            x5chainValue = CborValue.ByteStringVal(this.x5chain[0])
        } else {
            let certItems = ArrayList<CborValue>()
            for (cert in this.x5chain) {
                certItems.add(CborValue.ByteStringVal(cert))
            }
            x5chainValue = CborValue.ArrayVal(certItems)
        }

        let uphPairs = ArrayList<(CborValue, CborValue)>()
        uphPairs.add((CborValue.UInt64Val(IssuerAuth.X5CHAIN_HEADER_KEY), x5chainValue))
        let uphCbor = CborValue.MapVal(uphPairs)

        let cose = CoseSign1.create(
            this.verifyAlgorithm,
            Some(this.msoRawData),
            Some(uphCbor),
            this.signature
        )
        // ISO 18013-5: IssuerAuth is an *untagged* COSE_Sign1 (bare 4-element
        // array), consistent with ReaderAuth/DeviceAuth. Tag 18 is reserved for
        // standalone top-level COSE messages, not the embedded mdoc IssuerAuth.
        return cose.toCbor()
    }
}
