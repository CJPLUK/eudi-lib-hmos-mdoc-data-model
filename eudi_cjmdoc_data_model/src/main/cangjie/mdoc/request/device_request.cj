/*
 * device_request.cj
 *
 * mDoc device request structures as defined in ISO 18013-5 §8.3.2.
 *
 * Implements:
 *   RequestDataElements  — map of elementIdentifier → intentToRetain (bool)
 *   RequestNameSpaces    — map of nameSpace → RequestDataElements
 *   ItemsRequest         — docType + RequestNameSpaces + optional requestInfo
 *   DocRequest           — Tag24-wrapped ItemsRequest + optional ReaderAuth
 *   DeviceRequest        — version + [DocRequest] + optional deviceRequestInfo
 *   ReaderAuth           — COSE_Sign1 container + x5chain certificates
 *   ZkRequest            — raw ZK system specs (pass-through for future mdoc_zkp)
 *   DocRequestInfo       — optional request metadata (issuer, constraints, etc.)
 *   DeviceRequestInfo    — optional device-level use-case info
 *
 * iOS source references:
 *   Sources/MdocDataModel18013/MdocRequest/RequestDataElements.swift
 *   Sources/MdocDataModel18013/MdocRequest/RequestNameSpaces.swift
 *   Sources/MdocDataModel18013/MdocRequest/ItemsRequest.swift
 *   Sources/MdocDataModel18013/MdocRequest/DocRequest.swift
 *   Sources/MdocDataModel18013/MdocRequest/DeviceRequest.swift
 *   Sources/MdocDataModel18013/MdocRequest/ReaderAuth.swift
 *   Sources/MdocDataModel18013/MdocRequest/ZkRequest.swift
 *   Sources/MdocDataModel18013/MdocRequest/DocRequestInfo.swift
 *   Sources/MdocDataModel18013/MdocRequest/DeviceRequestInfo.swift
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.request

import std.collection.ArrayList
import std.collection.HashMap

import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.CborTag
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CBOREncodable
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MdocValidationError
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CoseSign1
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CoseHeader

/* ------------------------------------------------------------------ */
/* Type aliases (mirror iOS type aliases)                               */
/* ------------------------------------------------------------------ */

/** intentToRetain flag — whether the verifier intends to retain the element. */
public type IntentToRetain = Bool

/** Data element identifier (string key in a namespace map). */
public type DataElementIdentifier = String

/** Document type string (e.g. "org.iso.18013.5.1.mDL"). */
public type DocType = String

/** Namespace string (e.g. "org.iso.18013.5.1"). */
public type NameSpace = String

/* ------------------------------------------------------------------ */
/* RequestDataElements                                                  */
/* ------------------------------------------------------------------ */

/**
 * Map of DataElementIdentifier → IntentToRetain.
 *
 * CBOR encoding: a map where keys are tstr (element identifiers) and
 * values are bool (intentToRetain).
 *
 * ISO 18013-5 §8.3.2.1.2.1:
 *   DataElements = {+ DataElementIdentifier => IntentToRetain}
 */
public class RequestDataElements <: CBOREncodable {
    /** Map from element identifier to intentToRetain flag. */
    public let dataElements: HashMap<DataElementIdentifier, IntentToRetain>

    public init(dataElements: HashMap<DataElementIdentifier, IntentToRetain>) {
        this.dataElements = dataElements
    }

    /** Element identifiers (keys of the dataElements map). */
    public func elementIdentifiers(): Array<DataElementIdentifier> {
        let keys = ArrayList<DataElementIdentifier>()
        for ((k, _) in dataElements) {
            keys.add(k)
        }
        return keys.toArray()
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if the structure is invalid.
     */
    public static func fromCbor(cbor: CborValue): RequestDataElements {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                if (pairs.size == 0) {
                    throw MdocValidationError.invalidCbor("request data elements")
                }
                let map = HashMap<DataElementIdentifier, IntentToRetain>()
                for ((k, v) in pairs) {
                    match ((k, v)) {
                        case (CborValue.TextStringVal(dei), CborValue.BoolVal(ir)) =>
                            map[dei] = ir
                        case _ =>
                            throw MdocValidationError.invalidCbor("request data elements")
                    }
                }
                return RequestDataElements(map)
            case _ =>
                throw MdocValidationError.invalidCbor("request data elements")
        }
    }

    /**
     * Encode to CBOR: a map of tstr → bool.
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        for ((dei, ir) in dataElements) {
            pairs.add((CborValue.TextStringVal(dei), CborValue.BoolVal(ir)))
        }
        return CborValue.MapVal(pairs)
    }
}

/* ------------------------------------------------------------------ */
/* RequestNameSpaces                                                    */
/* ------------------------------------------------------------------ */

/**
 * Map of NameSpace → RequestDataElements.
 *
 * CBOR encoding: a map where keys are tstr (namespace) and values are
 * RequestDataElements maps.
 *
 * ISO 18013-5 §8.3.2.1.2.1:
 *   RequestNameSpaces = {+ NameSpace => DataElements}
 */
public class RequestNameSpaces <: CBOREncodable {
    /** Map from namespace string to its requested data elements. */
    public let nameSpaces: HashMap<NameSpace, RequestDataElements>

    public init(nameSpaces: HashMap<NameSpace, RequestDataElements>) {
        this.nameSpaces = nameSpaces
    }

    /** Subscript-style lookup by namespace. */
    public func get(ns: String): ?RequestDataElements {
        return nameSpaces.get(ns)
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if the structure is invalid or empty.
     */
    public static func fromCbor(cbor: CborValue): RequestNameSpaces {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                if (pairs.size == 0) {
                    throw MdocValidationError.invalidCbor("request name spaces")
                }
                let map = HashMap<NameSpace, RequestDataElements>()
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.TextStringVal(ns) =>
                            let rde = RequestDataElements.fromCbor(v)
                            map[ns] = rde
                        case _ =>
                            throw MdocValidationError.invalidCbor("request name spaces")
                    }
                }
                return RequestNameSpaces(map)
            case _ =>
                throw MdocValidationError.invalidCbor("request name spaces")
        }
    }

    /**
     * Encode to CBOR: a map of tstr → RequestDataElements.
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        for ((ns, rde) in nameSpaces) {
            pairs.add((CborValue.TextStringVal(ns), rde.toCbor()))
        }
        return CborValue.MapVal(pairs)
    }
}

/* ------------------------------------------------------------------ */
/* ItemsRequest                                                         */
/* ------------------------------------------------------------------ */

/**
 * Requested items for a single document type.
 *
 * CBOR encoding (ISO 18013-5 §8.3.2.1.2.1):
 *   ItemsRequest = {
 *     "docType"      : DocType,
 *     "nameSpaces"   : RequestNameSpaces,
 *     ? "requestInfo": {* tstr => any}
 *   }
 *
 * Note: ItemsRequest is embedded inside DocRequest as a Tag-24 bstr
 * (i.e. the bytes are the CBOR encoding of ItemsRequest, wrapped in
 * tag 24 per §8.3.2.1.2).
 */
public class ItemsRequest <: CBOREncodable {
    /** Requested document type. */
    public let docType: DocType
    /** Requested data elements per namespace. */
    public let requestNameSpaces: RequestNameSpaces
    /** Optional additional request info (raw CBOR map). */
    public let requestInfo: ?CborValue

    static let KEY_DOC_TYPE: String = "docType"
    static let KEY_NAME_SPACES: String = "nameSpaces"
    static let KEY_REQUEST_INFO: String = "requestInfo"

    public init(docType: DocType, requestNameSpaces: RequestNameSpaces, requestInfo: ?CborValue) {
        this.docType = docType
        this.requestNameSpaces = requestNameSpaces
        this.requestInfo = requestInfo
    }

    /**
     * Decode from raw CBOR bytes (Tag-24 unwrapped).
     * Used by DocRequest which receives the tag-24 bytes.
     */
    public static func fromBytes(bytes: Array<UInt8>): ItemsRequest {
        let cbor: CborValue
        try {
            cbor = decodeCbor(bytes)
        } catch (_: Exception) {
            throw MdocValidationError.invalidCbor("items request")
        }
        return ItemsRequest.fromCbor(cbor)
    }

    /**
     * Decode from a CBOR map value.
     * Throws MdocValidationError if the structure is invalid.
     */
    public static func fromCbor(cbor: CborValue): ItemsRequest {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let docTypeVal = cbor.field(CborValue.TextStringVal(ItemsRequest.KEY_DOC_TYPE))
                let docType: DocType = match (docTypeVal) {
                    case Some(CborValue.TextStringVal(s)) => s
                    case _ =>
                        throw MdocValidationError.missingField("ItemsRequest", ItemsRequest.KEY_DOC_TYPE)
                }
                let nameSpacesVal = cbor.field(CborValue.TextStringVal(ItemsRequest.KEY_NAME_SPACES))
                let requestNameSpaces: RequestNameSpaces = match (nameSpacesVal) {
                    case Some(nsVal) => RequestNameSpaces.fromCbor(nsVal)
                    case None =>
                        throw MdocValidationError.missingField("ItemsRequest", ItemsRequest.KEY_NAME_SPACES)
                }
                let requestInfoOpt: ?CborValue = cbor.field(CborValue.TextStringVal(ItemsRequest.KEY_REQUEST_INFO))
                return ItemsRequest(docType, requestNameSpaces, requestInfoOpt)
            case _ =>
                throw MdocValidationError.invalidCbor("items request")
        }
    }

    /**
     * Encode to CBOR map.
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal(ItemsRequest.KEY_DOC_TYPE), CborValue.TextStringVal(docType)))
        pairs.add((CborValue.TextStringVal(ItemsRequest.KEY_NAME_SPACES), requestNameSpaces.toCbor()))
        match (requestInfo) {
            case Some(ri) =>
                pairs.add((CborValue.TextStringVal(ItemsRequest.KEY_REQUEST_INFO), ri))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    /**
     * Encode to raw bytes (CBOR encoding of the map, without Tag-24 wrapper).
     * DocRequest uses these bytes to wrap in Tag-24.
     */
    public func toBytes(): Array<UInt8> {
        return this.toCbor().encode()
    }
}

/* ------------------------------------------------------------------ */
/* ReaderAuth                                                           */
/* ------------------------------------------------------------------ */

/**
 * Reader authentication structure — a COSE_Sign1 container with an x5chain
 * certificate chain in the unprotected header.
 *
 * ISO 18013-5 §9.1.4 / RFC 8152:
 *   ReaderAuth = COSE_Sign1 (untagged, x5chain in unprotected header key 33)
 *
 * iOS reference: Sources/MdocDataModel18013/MdocRequest/ReaderAuth.swift
 * Note: signature verification is intentionally left to the upper layer.
 */
public class ReaderAuth <: CBOREncodable {
    /** The underlying COSE_Sign1 container. */
    public let coseSign1: CoseSign1
    /** Certificate chain (one or more DER-encoded X.509 certificates). */
    public let x5chain: Array<Array<UInt8>>

    /** COSE unprotected header key for x5chain (RFC 9360 §2). */
    static let X5CHAIN_HEADER_KEY: UInt64 = 33

    public init(coseSign1: CoseSign1, x5chain: Array<Array<UInt8>>) {
        this.coseSign1 = coseSign1
        this.x5chain = x5chain
    }

    /**
     * Decode from an untagged COSE_Sign1 CBOR array.
     * Throws MdocValidationError if the structure is missing or malformed.
     */
    public static func fromCbor(cbor: CborValue): ReaderAuth {
        let coseOpt = CoseSign1.fromCborArray(cbor)
        let cose: CoseSign1 = match (coseOpt) {
            case Some(c) => c
            case None => throw MdocValidationError.invalidCbor("reader authentication")
        }
        // Extract x5chain from unprotected header (key = UInt 33)
        let uphOpt = cose.unprotectedHeader
        let x5chain: Array<Array<UInt8>> = match (uphOpt) {
            case Some(uph) =>
                let rawOpt = uph.rawHeaderBytes
                match (rawOpt) {
                    case Some(rawBytes) =>
                        let uphCbor: CborValue
                        try {
                            uphCbor = decodeCbor(rawBytes)
                        } catch (_: Exception) {
                            throw MdocValidationError.invalidCbor("reader authentication")
                        }
                        ReaderAuth.extractX5chain(uphCbor)
                    case None => throw MdocValidationError.invalidCbor("reader authentication")
                }
            case None => throw MdocValidationError.invalidCbor("reader authentication")
        }
        return ReaderAuth(cose, x5chain)
    }

    /**
     * Extract x5chain certificate bytes from an unprotected header map.
     * Supports both single bstr (one cert) and array of bstr (chain).
     */
    static func extractX5chain(uphCbor: CborValue): Array<Array<UInt8>> {
        let x5chainKey = CborValue.UInt64Val(ReaderAuth.X5CHAIN_HEADER_KEY)
        let valOpt = uphCbor.field(x5chainKey)
        match (valOpt) {
            case Some(CborValue.ByteStringVal(certBytes)) =>
                return [certBytes]
            case Some(CborValue.ArrayVal(certArray)) =>
                let certs = ArrayList<Array<UInt8>>()
                for (entry in certArray) {
                    match (entry) {
                        case CborValue.ByteStringVal(certBytes) =>
                            certs.add(certBytes)
                        case _ => ()
                    }
                }
                if (certs.size == 0) {
                    throw MdocValidationError.invalidCbor("reader authentication")
                }
                return certs.toArray()
            case _ =>
                throw MdocValidationError.invalidCbor("reader authentication")
        }
    }

    /**
     * Encode to CBOR: the underlying COSE_Sign1 as an untagged 4-element array.
     */
    public func toCbor(): CborValue {
        return coseSign1.toCbor()
    }
}

/* ------------------------------------------------------------------ */
/* DocRequest                                                           */
/* ------------------------------------------------------------------ */

/**
 * A single document request (one docType).
 *
 * CBOR encoding (ISO 18013-5 §8.3.2.1.2):
 *   DocRequest = {
 *     "itemsRequest" : ItemsRequestBytes,    -- #6.24(bstr .cbor ItemsRequest)
 *     ? "readerAuth" : ReaderAuth
 *   }
 *   ItemsRequestBytes = #6.24(bstr .cbor ItemsRequest)
 */
public class DocRequest <: CBOREncodable {
    /** Decoded items request. */
    public let itemsRequest: ItemsRequest
    /** Raw bytes of the items request (preserved for integrity, NOT tagged). */
    public let itemsRequestRawData: ?Array<UInt8>
    /** Optional reader authentication. */
    public let readerAuth: ?ReaderAuth
    /** Raw CBOR of reader auth (for upper-layer signature verification). */
    public let readerAuthRawCbor: ?CborValue

    static let KEY_ITEMS_REQUEST: String = "itemsRequest"
    static let KEY_READER_AUTH: String = "readerAuth"

    public init(
        itemsRequest: ItemsRequest,
        itemsRequestRawData: ?Array<UInt8>,
        readerAuth: ?ReaderAuth,
        readerAuthRawCbor: ?CborValue
    ) {
        this.itemsRequest = itemsRequest
        this.itemsRequestRawData = itemsRequestRawData
        this.readerAuth = readerAuth
        this.readerAuthRawCbor = readerAuthRawCbor
    }

    /**
     * Decode from a CBOR map.
     * Throws MdocValidationError if the structure is invalid.
     */
    public static func fromCbor(cbor: CborValue): DocRequest {
        match (cbor) {
            case CborValue.MapVal(_) =>
                // itemsRequest must be #6.24(bstr .cbor ItemsRequest)
                let itemsRequestVal = cbor.field(CborValue.TextStringVal(DocRequest.KEY_ITEMS_REQUEST))
                let itemsRequestBytes: Array<UInt8>
                match (itemsRequestVal) {
                    case Some(CborValue.TaggedVal(tag, CborValue.ByteStringVal(bs))) =>
                        if (tag != CborTag.ENCODED_CBOR) {
                            throw MdocValidationError.missingField("DocRequest", DocRequest.KEY_ITEMS_REQUEST)
                        }
                        itemsRequestBytes = bs
                    case _ =>
                        throw MdocValidationError.missingField("DocRequest", DocRequest.KEY_ITEMS_REQUEST)
                }
                let itemsRequest = ItemsRequest.fromBytes(itemsRequestBytes)
                let readerAuthRawOpt = cbor.field(CborValue.TextStringVal(DocRequest.KEY_READER_AUTH))
                let readerAuthOpt: ?ReaderAuth = match (readerAuthRawOpt) {
                    case Some(rawCbor) =>
                        Some(ReaderAuth.fromCbor(rawCbor))
                    case None => None
                }
                return DocRequest(
                    itemsRequest,
                    Some(itemsRequestBytes),
                    readerAuthOpt,
                    readerAuthRawOpt
                )
            case _ =>
                throw MdocValidationError.invalidCbor("document request")
        }
    }

    /**
     * Encode to CBOR map.
     *
     * If itemsRequestRawData is available it is used directly (preserving
     * the original encoding); otherwise itemsRequest is re-encoded.
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        // ItemsRequestBytes: #6.24(bstr)
        let irTagged: CborValue = match (itemsRequestRawData) {
            case Some(rawBytes) =>
                CborValue.TaggedVal(CborTag.ENCODED_CBOR, CborValue.ByteStringVal(rawBytes))
            case None =>
                let encoded = itemsRequest.toBytes()
                CborValue.TaggedVal(CborTag.ENCODED_CBOR, CborValue.ByteStringVal(encoded))
        }
        pairs.add((CborValue.TextStringVal(DocRequest.KEY_ITEMS_REQUEST), irTagged))
        match (readerAuth) {
            case Some(ra) =>
                pairs.add((CborValue.TextStringVal(DocRequest.KEY_READER_AUTH), ra.toCbor()))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}

/* ------------------------------------------------------------------ */
/* DeviceRequestInfo / UseCase (optional, Tag-24 wrapped)              */
/* ------------------------------------------------------------------ */

/**
 * UseCase — one entry in DeviceRequestInfo.useCases.
 *
 * CBOR:
 *   UseCase = {
 *     "mandatory"    : bool,
 *     "documentSets" : [[+ uint]],
 *     ? "purposeHints": { + tstr => int }
 *   }
 */
public class UseCase <: CBOREncodable {
    public let mandatory: Bool
    /** Array of document sets, each document set is an array of DocRequestID (uint). */
    public let documentSets: Array<Array<UInt64>>
    /** Optional purpose hints: controllerId → purposeCode. */
    public let purposeHints: ?HashMap<String, Int64>

    static let KEY_MANDATORY: String = "mandatory"
    static let KEY_DOCUMENT_SETS: String = "documentSets"
    static let KEY_PURPOSE_HINTS: String = "purposeHints"

    public init(
        mandatory: Bool,
        documentSets: Array<Array<UInt64>>,
        purposeHints: ?HashMap<String, Int64>
    ) {
        this.mandatory = mandatory
        this.documentSets = documentSets
        this.purposeHints = purposeHints
    }

    public static func fromCbor(cbor: CborValue): UseCase {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let mandatoryVal = cbor.field(CborValue.TextStringVal(UseCase.KEY_MANDATORY))
                let mandatory: Bool = match (mandatoryVal) {
                    case Some(CborValue.BoolVal(b)) => b
                    case _ => throw MdocValidationError.missingField("UseCase", UseCase.KEY_MANDATORY)
                }
                let documentSetsVal = cbor.field(CborValue.TextStringVal(UseCase.KEY_DOCUMENT_SETS))
                let documentSets: Array<Array<UInt64>> = match (documentSetsVal) {
                    case Some(CborValue.ArrayVal(outerArr)) =>
                        if (outerArr.size == 0) {
                            throw MdocValidationError.invalidCbor("UseCase.documentSets empty array")
                        }
                        let sets = ArrayList<Array<UInt64>>()
                        for (setVal in outerArr) {
                            match (setVal) {
                                case CborValue.ArrayVal(innerArr) =>
                                    if (innerArr.size == 0) {
                                        throw MdocValidationError.invalidCbor("DocumentSet")
                                    }
                                    let ids = ArrayList<UInt64>()
                                    for (idVal in innerArr) {
                                        match (idVal) {
                                            case CborValue.UInt64Val(id) => ids.add(id)
                                            case _ =>
                                                throw MdocValidationError.invalidCbor("DocRequestID")
                                        }
                                    }
                                    sets.add(ids.toArray())
                                case _ => throw MdocValidationError.invalidCbor("DocumentSet")
                            }
                        }
                        sets.toArray()
                    case _ => throw MdocValidationError.missingField("UseCase", UseCase.KEY_DOCUMENT_SETS)
                }
                let purposeHintsOpt: ?HashMap<String, Int64> = match (
                    cbor.field(CborValue.TextStringVal(UseCase.KEY_PURPOSE_HINTS))
                ) {
                    case Some(CborValue.MapVal(hintPairs)) =>
                        let hints = HashMap<String, Int64>()
                        for ((hk, hv) in hintPairs) {
                            match (hk) {
                                case CborValue.TextStringVal(cid) =>
                                    let code: Int64 = match (hv) {
                                        case CborValue.UInt64Val(n) => Int64(n)
                                        case CborValue.NInt64Val(n) => -1 - Int64(n)
                                        case _ =>
                                            throw MdocValidationError.invalidCbor("UseCase")
                                    }
                                    hints[cid] = code
                                case _ => throw MdocValidationError.invalidCbor("UseCase")
                            }
                        }
                        if (hints.size == 0) { None } else { Some(hints) }
                    case _ => None
                }
                return UseCase(mandatory, documentSets, purposeHintsOpt)
            case _ =>
                throw MdocValidationError.invalidCbor("UseCase")
        }
    }

    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal(UseCase.KEY_MANDATORY), CborValue.BoolVal(mandatory)))
        let setsArr = ArrayList<CborValue>()
        for (docSet in documentSets) {
            let innerArr = ArrayList<CborValue>()
            for (id in docSet) {
                innerArr.add(CborValue.UInt64Val(id))
            }
            setsArr.add(CborValue.ArrayVal(innerArr))
        }
        pairs.add((CborValue.TextStringVal(UseCase.KEY_DOCUMENT_SETS), CborValue.ArrayVal(setsArr)))
        match (purposeHints) {
            case Some(hints) =>
                let hintPairs = ArrayList<(CborValue, CborValue)>()
                for ((cid, code) in hints) {
                    let encodedCode: CborValue = if (code >= 0) {
                        CborValue.UInt64Val(UInt64(code))
                    } else {
                        CborValue.NInt64Val(UInt64(-1 - code))
                    }
                    hintPairs.add((CborValue.TextStringVal(cid), encodedCode))
                }
                pairs.add((CborValue.TextStringVal(UseCase.KEY_PURPOSE_HINTS), CborValue.MapVal(hintPairs)))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}

/**
 * DeviceRequestInfo — optional top-level metadata (use-cases).
 * Embedded in DeviceRequest as a Tag-24 bstr.
 *
 * CBOR:
 *   DeviceRequestInfo = {
 *     ? "useCases" : [+ UseCase]
 *   }
 */
public class DeviceRequestInfo <: CBOREncodable {
    public let useCases: ?Array<UseCase>

    static let KEY_USE_CASES: String = "useCases"

    public init(useCases: ?Array<UseCase>) {
        this.useCases = useCases
    }

    public static func fromCbor(cbor: CborValue): DeviceRequestInfo {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let useCasesOpt: ?Array<UseCase> = match (
                    cbor.field(CborValue.TextStringVal(DeviceRequestInfo.KEY_USE_CASES))
                ) {
                    case Some(CborValue.ArrayVal(arr)) =>
                        if (arr.size == 0) {
                            throw MdocValidationError.invalidCbor("DeviceRequestInfo.useCases")
                        }
                        let cases = ArrayList<UseCase>()
                        for (ucVal in arr) {
                            cases.add(UseCase.fromCbor(ucVal))
                        }
                        Some(cases.toArray())
                    case _ => None
                }
                return DeviceRequestInfo(useCasesOpt)
            case _ =>
                throw MdocValidationError.invalidCbor("DeviceRequestInfo")
        }
    }

    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        match (useCases) {
            case Some(cases) =>
                let arr = ArrayList<CborValue>()
                for (uc in cases) {
                    arr.add(uc.toCbor())
                }
                pairs.add((CborValue.TextStringVal(DeviceRequestInfo.KEY_USE_CASES), CborValue.ArrayVal(arr)))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}

/* ------------------------------------------------------------------ */
/* ZkRequest (pass-through for mdoc_zkp feature)                       */
/* ------------------------------------------------------------------ */

/**
 * ZkRequest — holds raw ZK system spec CBOR values.
 *
 * ZkSystemSpec decoding belongs to the future mdoc_zkp feature.
 * Here we parse the structure and preserve raw CborValue items so that
 * round-trip encoding is lossless without depending on mdoc_zkp.
 *
 * CBOR:
 *   ZkRequest = {
 *     "systemSpecs" : [+ ZkSystemSpec]
 *   }
 */
public class ZkRequest <: CBOREncodable {
    /** Raw CborValue entries for each ZkSystemSpec (parsed by mdoc_zkp layer). */
    public let systemSpecsRaw: Array<CborValue>

    static let KEY_SYSTEM_SPECS: String = "systemSpecs"

    public init(systemSpecsRaw: Array<CborValue>) {
        this.systemSpecsRaw = systemSpecsRaw
    }

    public static func fromCbor(cbor: CborValue): ZkRequest {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let systemSpecsVal = cbor.field(CborValue.TextStringVal(ZkRequest.KEY_SYSTEM_SPECS))
                match (systemSpecsVal) {
                    case Some(CborValue.ArrayVal(arr)) =>
                        let specs = ArrayList<CborValue>()
                        for (specVal in arr) {
                            specs.add(specVal)
                        }
                        return ZkRequest(specs.toArray())
                    case _ =>
                        throw MdocValidationError.missingField("ZkRequest", ZkRequest.KEY_SYSTEM_SPECS)
                }
            case _ =>
                throw MdocValidationError.invalidCbor("ZkRequest")
        }
    }

    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        let arr = ArrayList<CborValue>()
        for (spec in systemSpecsRaw) {
            arr.add(spec)
        }
        pairs.add((CborValue.TextStringVal(ZkRequest.KEY_SYSTEM_SPECS), CborValue.ArrayVal(arr)))
        return CborValue.MapVal(pairs)
    }
}

/* ------------------------------------------------------------------ */
/* DocRequestInfo                                                       */
/* ------------------------------------------------------------------ */

/**
 * Optional per-document request metadata.
 *
 * CBOR:
 *   DocRequestInfo = {
 *     ? "alternativeDataElements" : [...],
 *     ? "issuerIdentifiers"       : [+ bstr],
 *     ? "uniqueDocSetRequired"    : bool,
 *     ? "maximumResponseSize"     : uint,
 *     ? "zkRequest"               : ZkRequest
 *   }
 *
 * All fields are optional; unknown extension keys are preserved as raw CborValue.
 */
public class DocRequestInfo <: CBOREncodable {
    public let issuerIdentifiers: ?Array<Array<UInt8>>
    public let uniqueDocSetRequired: ?Bool
    public let maximumResponseSize: ?UInt64
    public let zkRequest: ?ZkRequest
    /** Raw CBOR for alternativeDataElements (complex structure, passed through). */
    public let alternativeDataElementsRaw: ?CborValue

    static let KEY_ALT_DATA: String = "alternativeDataElements"
    static let KEY_ISSUER_IDS: String = "issuerIdentifiers"
    static let KEY_UNIQUE_DOC: String = "uniqueDocSetRequired"
    static let KEY_MAX_RESP: String = "maximumResponseSize"
    static let KEY_ZK_REQ: String = "zkRequest"

    public init(
        issuerIdentifiers: ?Array<Array<UInt8>>,
        uniqueDocSetRequired: ?Bool,
        maximumResponseSize: ?UInt64,
        zkRequest: ?ZkRequest,
        alternativeDataElementsRaw: ?CborValue
    ) {
        this.issuerIdentifiers = issuerIdentifiers
        this.uniqueDocSetRequired = uniqueDocSetRequired
        this.maximumResponseSize = maximumResponseSize
        this.zkRequest = zkRequest
        this.alternativeDataElementsRaw = alternativeDataElementsRaw
    }

    public static func fromCbor(cbor: CborValue): DocRequestInfo {
        match (cbor) {
            case CborValue.MapVal(_) =>
                let altDataRaw = cbor.field(CborValue.TextStringVal(DocRequestInfo.KEY_ALT_DATA))
                let issuerIdsOpt: ?Array<Array<UInt8>> = match (
                    cbor.field(CborValue.TextStringVal(DocRequestInfo.KEY_ISSUER_IDS))
                ) {
                    case Some(CborValue.ArrayVal(arr)) =>
                        let ids = ArrayList<Array<UInt8>>()
                        for (idVal in arr) {
                            match (idVal) {
                                case CborValue.ByteStringVal(bs) => ids.add(bs)
                                case _ =>
                                    throw MdocValidationError.invalidCbor("DocRequestInfo")
                            }
                        }
                        Some(ids.toArray())
                    case _ => None
                }
                let uniqueDocOpt: ?Bool = match (
                    cbor.field(CborValue.TextStringVal(DocRequestInfo.KEY_UNIQUE_DOC))
                ) {
                    case Some(CborValue.BoolVal(b)) => Some(b)
                    case _ => None
                }
                let maxRespOpt: ?UInt64 = match (
                    cbor.field(CborValue.TextStringVal(DocRequestInfo.KEY_MAX_RESP))
                ) {
                    case Some(CborValue.UInt64Val(n)) => Some(n)
                    case _ => None
                }
                let zkReqOpt: ?ZkRequest = match (
                    cbor.field(CborValue.TextStringVal(DocRequestInfo.KEY_ZK_REQ))
                ) {
                    case Some(zkCbor) => Some(ZkRequest.fromCbor(zkCbor))
                    case None => None
                }
                return DocRequestInfo(issuerIdsOpt, uniqueDocOpt, maxRespOpt, zkReqOpt, altDataRaw)
            case _ =>
                throw MdocValidationError.invalidCbor("DocRequestInfo")
        }
    }

    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        match (alternativeDataElementsRaw) {
            case Some(altData) =>
                pairs.add((CborValue.TextStringVal(DocRequestInfo.KEY_ALT_DATA), altData))
            case None => ()
        }
        match (issuerIdentifiers) {
            case Some(ids) =>
                let arr = ArrayList<CborValue>()
                for (id in ids) {
                    arr.add(CborValue.ByteStringVal(id))
                }
                pairs.add((CborValue.TextStringVal(DocRequestInfo.KEY_ISSUER_IDS), CborValue.ArrayVal(arr)))
            case None => ()
        }
        match (uniqueDocSetRequired) {
            case Some(b) =>
                pairs.add((CborValue.TextStringVal(DocRequestInfo.KEY_UNIQUE_DOC), CborValue.BoolVal(b)))
            case None => ()
        }
        match (maximumResponseSize) {
            case Some(n) =>
                pairs.add((CborValue.TextStringVal(DocRequestInfo.KEY_MAX_RESP), CborValue.UInt64Val(n)))
            case None => ()
        }
        match (zkRequest) {
            case Some(zk) =>
                pairs.add((CborValue.TextStringVal(DocRequestInfo.KEY_ZK_REQ), zk.toCbor()))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}

/* ------------------------------------------------------------------ */
/* DeviceRequest                                                        */
/* ------------------------------------------------------------------ */

/**
 * Top-level mDoc device request structure.
 *
 * CBOR encoding (ISO 18013-5 §8.3.2.1.2):
 *   DeviceRequest = {
 *     "version"           : tstr,
 *     "docRequests"       : [+ DocRequest],
 *     ? "deviceRequestInfo" : DeviceRequestInfoBytes,  -- #6.24(bstr .cbor DeviceRequestInfo)
 *     ? "readerAuthAll"   : [+ ReaderAuth]
 *   }
 *
 * iOS reference: Sources/MdocDataModel18013/MdocRequest/DeviceRequest.swift
 */
public class DeviceRequest <: CBOREncodable {
    /** Current protocol version. */
    public let version: String
    /** One or more document requests. */
    public let docRequests: Array<DocRequest>
    /** Optional device-level request info (Tag-24 wrapped). */
    public let deviceRequestInfo: ?DeviceRequestInfo
    /** Optional reader auth for all docs (raw CBORs preserved for verification). */
    public let readerAuthAll: ?Array<ReaderAuth>

    /** Known version strings. */
    public static let VERSION_1_0: String = "1.0"
    public static let VERSION_1_1: String = "1.1"

    static let KEY_VERSION: String = "version"
    static let KEY_DOC_REQUESTS: String = "docRequests"
    static let KEY_DEVICE_REQUEST_INFO: String = "deviceRequestInfo"
    static let KEY_READER_AUTH_ALL: String = "readerAuthAll"

    public init(
        version: String,
        docRequests: Array<DocRequest>,
        deviceRequestInfo: ?DeviceRequestInfo,
        readerAuthAll: ?Array<ReaderAuth>
    ) {
        this.version = version
        this.docRequests = docRequests
        this.deviceRequestInfo = deviceRequestInfo
        this.readerAuthAll = readerAuthAll
    }

    /**
     * Decode from raw CBOR bytes.
     * Throws MdocValidationError if the structure is invalid.
     */
    public static func fromBytes(bytes: Array<UInt8>): DeviceRequest {
        let cbor: CborValue
        try {
            cbor = decodeCbor(bytes)
        } catch (_: Exception) {
            throw MdocValidationError.cborDecodingError()
        }
        return DeviceRequest.fromCbor(cbor)
    }

    /**
     * Decode from a CborValue map.
     * Throws MdocValidationError if the structure is invalid.
     */
    public static func fromCbor(cbor: CborValue): DeviceRequest {
        match (cbor) {
            case CborValue.MapVal(_) =>
                // version
                let versionVal = cbor.field(CborValue.TextStringVal(DeviceRequest.KEY_VERSION))
                let version: String = match (versionVal) {
                    case Some(CborValue.TextStringVal(v)) => v
                    case _ =>
                        throw MdocValidationError.missingField("DeviceRequest", DeviceRequest.KEY_VERSION)
                }
                // docRequests
                let docRequestsVal = cbor.field(CborValue.TextStringVal(DeviceRequest.KEY_DOC_REQUESTS))
                let docRequests: Array<DocRequest> = match (docRequestsVal) {
                    case Some(CborValue.ArrayVal(arr)) =>
                        if (arr.size == 0) {
                            throw MdocValidationError.invalidCbor("device request")
                        }
                        let reqs = ArrayList<DocRequest>()
                        for (drVal in arr) {
                            reqs.add(DocRequest.fromCbor(drVal))
                        }
                        reqs.toArray()
                    case _ =>
                        throw MdocValidationError.missingField("DeviceRequest", DeviceRequest.KEY_DOC_REQUESTS)
                }
                // deviceRequestInfo (Tag-24 wrapped)
                let deviceRequestInfoOpt: ?DeviceRequestInfo = match (
                    cbor.field(CborValue.TextStringVal(DeviceRequest.KEY_DEVICE_REQUEST_INFO))
                ) {
                    case Some(CborValue.TaggedVal(tag, CborValue.ByteStringVal(bs))) =>
                        if (tag != CborTag.ENCODED_CBOR) {
                            throw MdocValidationError.invalidCbor("DeviceRequest")
                        }
                        let innerCbor: CborValue
                        try {
                            innerCbor = decodeCbor(bs)
                        } catch (_: Exception) {
                            throw MdocValidationError.invalidCbor("DeviceRequest")
                        }
                        Some(DeviceRequestInfo.fromCbor(innerCbor))
                    case _ => None
                }
                // readerAuthAll
                let readerAuthAllOpt: ?Array<ReaderAuth> = match (
                    cbor.field(CborValue.TextStringVal(DeviceRequest.KEY_READER_AUTH_ALL))
                ) {
                    case Some(CborValue.ArrayVal(arr)) =>
                        if (arr.size == 0) {
                            throw MdocValidationError.invalidCbor("readerAuthAll array is empty")
                        }
                        let ras = ArrayList<ReaderAuth>()
                        for (raVal in arr) {
                            ras.add(ReaderAuth.fromCbor(raVal))
                        }
                        Some(ras.toArray())
                    case _ => None
                }
                return DeviceRequest(version, docRequests, deviceRequestInfoOpt, readerAuthAllOpt)
            case _ =>
                throw MdocValidationError.invalidCbor("device request")
        }
    }

    /**
     * Encode to CBOR bytes.
     */
    public func toBytes(): Array<UInt8> {
        return this.toCbor().encode()
    }

    /**
     * Encode to a CBOR map.
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal(DeviceRequest.KEY_VERSION), CborValue.TextStringVal(version)))
        // docRequests array
        let drArr = ArrayList<CborValue>()
        for (dr in docRequests) {
            drArr.add(dr.toCbor())
        }
        pairs.add((CborValue.TextStringVal(DeviceRequest.KEY_DOC_REQUESTS), CborValue.ArrayVal(drArr)))
        // deviceRequestInfo: Tag-24 wrapped
        match (deviceRequestInfo) {
            case Some(dri) =>
                let driBytes = dri.toCbor().encode()
                let driTagged = CborValue.TaggedVal(CborTag.ENCODED_CBOR, CborValue.ByteStringVal(driBytes))
                pairs.add((CborValue.TextStringVal(DeviceRequest.KEY_DEVICE_REQUEST_INFO), driTagged))
            case None => ()
        }
        // readerAuthAll
        match (readerAuthAll) {
            case Some(ras) =>
                let raArr = ArrayList<CborValue>()
                for (ra in ras) {
                    raArr.add(ra.toCbor())
                }
                pairs.add((CborValue.TextStringVal(DeviceRequest.KEY_READER_AUTH_ALL), CborValue.ArrayVal(raArr)))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }
}
