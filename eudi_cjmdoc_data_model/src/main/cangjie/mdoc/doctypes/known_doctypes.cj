/*
 * known_doctypes.cj
 *
 * Cangjie port of the iOS MdocDataModel18013 MdocKnownDocTypes layer.
 *
 * Implements:
 *   AgeAttesting              — interface for age attestation values
 *   DrivingPrivilegeCode      — CBOR map: code/sign/value
 *   DrivingPrivilege          — CBOR map: vehicle_category_code / issue_date / expiry_date / codes[]
 *   DrivingPrivileges         — CBOR array of DrivingPrivilege
 *   IsoMdlModel               — ISO 18013-5.1 mDL model (DocClaimsDecodable)
 *   IsoMdlModelFactory        — factory + auto-registers on load
 *   EuPidModel                — EU PID model (DocClaimsDecodable)
 *   EuPidModelFactory         — factory + auto-registers on load
 *
 * iOS source references:
 *   MdocKnownDocTypes/AgeAttesting.swift
 *   MdocKnownDocTypes/DocClaimsModel.swift
 *   MdocKnownDocTypes/DocClaimsModelConfiguration.swift
 *   MdocKnownDocTypes/IsoMdlModel.swift
 *   MdocKnownDocTypes/EuPidModel.swift
 *   DrivingPrivileges/DrivingPrivilegeCode.swift
 *   DrivingPrivileges/DrivingPrivilege.swift
 *   DrivingPrivileges/DrivingPrivileges.swift
 *
 * Package: ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.doctypes  (S-002)
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.doctypes

import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CBOREncodable
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims.DocClaim
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims.DocDataFormat
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims.DocMetadata
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims.DisplayMetadata
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims.DocClaimsDecodable
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims.DocClaimsDecodableFactory
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims.DocClaimsDecodableRegistry
import std.collection.ArrayList
import std.collection.HashMap

/* ======================================================================
 * AgeAttesting interface
 * Mirrors iOS `AgeAttesting` protocol — age_over_NN claim evaluation.
 * ====================================================================== */

/**
 * A type that carries age-over attestation values.
 * Mirrors iOS `AgeAttesting` protocol.
 *
 * ageOverXX: map from age threshold to bool (is holder over that age).
 */
public interface AgeAttesting {
    /**
     * Return the age attestation map: key = age threshold, value = true if
     * the holder is confirmed to be at or above that age.
     */
    func getAgeOverXX(): HashMap<Int64, Bool>
}

/**
 * Nearest "true" attestation above request (7.2.5 of ISO document).
 * Mirrors iOS `AgeAttesting.isOver(age:)` default implementation.
 *
 * Logic:
 *   1. Among entries where value==true && key>=age, take the smallest key.
 *   2. If none found, among entries where value==false && key<=age, take largest key.
 *   3. Otherwise return None.
 */
public func ageAttestIsOver(ageOverXX: HashMap<Int64, Bool>, age: Int64): ?(Int64, Bool) {
    var trueCandidateKey: Int64 = Int64.Max
    var trueCandidateFound: Bool = false
    for ((k, v) in ageOverXX) {
        if (v && k >= age) {
            if (!trueCandidateFound || k < trueCandidateKey) {
                trueCandidateKey = k
                trueCandidateFound = true
            }
        }
    }
    if (trueCandidateFound) {
        return Some((trueCandidateKey, true))
    }
    var falseCandidateKey: Int64 = Int64.Min
    var falseCandidateFound: Bool = false
    for ((k, v) in ageOverXX) {
        if (!v && k <= age) {
            if (!falseCandidateFound || k > falseCandidateKey) {
                falseCandidateKey = k
                falseCandidateFound = true
            }
        }
    }
    if (falseCandidateFound) {
        return Some((falseCandidateKey, false))
    }
    return None
}

/* ======================================================================
 * DrivingPrivilegeCode
 * Mirrors iOS `DrivingPrivilegeCode: Codable, CBORDecodable, CBOREncodable`
 * ====================================================================== */

/**
 * A code describing a driving privilege restriction or condition.
 * CBOR map keys: "code", "sign", "value"  (all String)
 */
public class DrivingPrivilegeCode <: CBOREncodable {
    public let code: String
    public let sign: ?String
    public let value: ?String

    public init(code: String, sign: ?String, value: ?String) {
        this.code = code
        this.sign = sign
        this.value = value
    }

    /**
     * Encode to CBOR map.
     * Always includes "code"; "sign" and "value" only if present.
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal("code"), CborValue.TextStringVal(this.code)))
        match (this.sign) {
            case Some(s) =>
                pairs.add((CborValue.TextStringVal("sign"), CborValue.TextStringVal(s)))
            case None => ()
        }
        match (this.value) {
            case Some(v) =>
                pairs.add((CborValue.TextStringVal("value"), CborValue.TextStringVal(v)))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    /**
     * Decode from CBOR map.
     * Returns None if "code" key is missing or not a text string.
     */
    public static func fromCbor(cbor: CborValue): ?DrivingPrivilegeCode {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let codeOpt = cborMapGetText(pairs, "code")
                match (codeOpt) {
                    case None => return None
                    case Some(codeStr) =>
                        let sign = cborMapGetText(pairs, "sign")
                        let value = cborMapGetText(pairs, "value")
                        return Some(DrivingPrivilegeCode(codeStr, sign, value))
                }
            case _ => return None
        }
    }
}

/* ======================================================================
 * DrivingPrivilege
 * Mirrors iOS `DrivingPrivilege: Codable, CBORDecodable, CBOREncodable`
 * ====================================================================== */

/**
 * Categories of vehicles/restrictions/conditions for an mDL holder.
 *
 * CBOR map keys:
 *   "vehicle_category_code" (text, mandatory)
 *   "issue_date"            (text, optional — ISO 8601 full-date tag or text)
 *   "expiry_date"           (text, optional)
 *   "codes"                 (array of maps, optional)
 */
public class DrivingPrivilege <: CBOREncodable {
    public let vehicleCategoryCode: String
    public let issueDate: ?String
    public let expiryDate: ?String
    public let codes: ?ArrayList<DrivingPrivilegeCode>

    public init(
        vehicleCategoryCode: String,
        issueDate: ?String,
        expiryDate: ?String,
        codes: ?ArrayList<DrivingPrivilegeCode>
    ) {
        this.vehicleCategoryCode = vehicleCategoryCode
        this.issueDate = issueDate
        this.expiryDate = expiryDate
        this.codes = codes
    }

    /**
     * Encode to CBOR map.
     * "vehicle_category_code" always present; others only if Some.
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((
            CborValue.TextStringVal("vehicle_category_code"),
            CborValue.TextStringVal(this.vehicleCategoryCode)
        ))
        match (this.issueDate) {
            case Some(d) =>
                pairs.add((CborValue.TextStringVal("issue_date"), CborValue.TextStringVal(d)))
            case None => ()
        }
        match (this.expiryDate) {
            case Some(d) =>
                pairs.add((CborValue.TextStringVal("expiry_date"), CborValue.TextStringVal(d)))
            case None => ()
        }
        match (this.codes) {
            case Some(cs) =>
                let codeItems = ArrayList<CborValue>()
                var i: Int64 = 0
                while (i < cs.size) {
                    codeItems.add(cs[i].toCbor())
                    i++
                }
                pairs.add((CborValue.TextStringVal("codes"), CborValue.ArrayVal(codeItems)))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    /**
     * Decode from CBOR map.
     * Returns None if "vehicle_category_code" is missing or malformed.
     */
    public static func fromCbor(cbor: CborValue): ?DrivingPrivilege {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let vcCodeOpt = cborMapGetText(pairs, "vehicle_category_code")
                match (vcCodeOpt) {
                    case None => return None
                    case Some(vcCode) =>
                        let issueDate = cborMapGetFullDate(pairs, "issue_date")
                        let expiryDate = cborMapGetFullDate(pairs, "expiry_date")
                        let codesOpt: ?ArrayList<DrivingPrivilegeCode> =
                            cborMapGetArrayOfCodes(pairs, "codes")
                        return Some(DrivingPrivilege(vcCode, issueDate, expiryDate, codesOpt))
                }
            case _ => return None
        }
    }
}

/* ======================================================================
 * DrivingPrivileges
 * Mirrors iOS `DrivingPrivileges: Codable, CBORDecodable, CBOREncodable`
 * ====================================================================== */

/**
 * An array of DrivingPrivilege entries.
 * CBOR representation: array of maps.
 * May be empty.
 */
public class DrivingPrivileges <: CBOREncodable {
    public let drivingPrivileges: ArrayList<DrivingPrivilege>

    public init(privileges: ArrayList<DrivingPrivilege>) {
        this.drivingPrivileges = privileges
    }

    /** Subscript-style access by index. */
    public func get(i: Int64): DrivingPrivilege {
        return this.drivingPrivileges[i]
    }

    /** Number of privileges. */
    public func size(): Int64 {
        return this.drivingPrivileges.size
    }

    /** Encode to CBOR array. */
    public func toCbor(): CborValue {
        let items = ArrayList<CborValue>()
        var i: Int64 = 0
        while (i < this.drivingPrivileges.size) {
            items.add(this.drivingPrivileges[i].toCbor())
            i++
        }
        return CborValue.ArrayVal(items)
    }

    /**
     * Decode from CBOR array.
     * Returns None if top-level CBOR is not an array.
     * Individual items that fail decode are skipped.
     */
    public static func fromCbor(cbor: CborValue): ?DrivingPrivileges {
        match (cbor) {
            case CborValue.ArrayVal(items) =>
                let privileges = ArrayList<DrivingPrivilege>()
                var i: Int64 = 0
                while (i < items.size) {
                    match (DrivingPrivilege.fromCbor(items[i])) {
                        case Some(dp) => privileges.add(dp)
                        case None => ()
                    }
                    i++
                }
                return Some(DrivingPrivileges(privileges))
            case _ => return None
        }
    }
}

/* ======================================================================
 * CBOR map helper utilities (package-private)
 * ====================================================================== */

/**
 * Lookup a text-string value by key in a CBOR map (ArrayList of pairs).
 * Returns None if key absent or value not a text string.
 * (R-104 compliant: no HashMap subscript without contains; uses ArrayList scan)
 */
func cborMapGetText(
    pairs: ArrayList<(CborValue, CborValue)>,
    key: String
): ?String {
    var i: Int64 = 0
    while (i < pairs.size) {
        let (k, v) = pairs[i]
        match (k) {
            case CborValue.TextStringVal(ks) =>
                if (ks == key) {
                    match (v) {
                        case CborValue.TextStringVal(s) => return Some(s)
                        case _ => return None
                    }
                }
            case _ => ()
        }
        i++
    }
    return None
}

/**
 * Lookup a date value by key — accepts plain text string or tagged full-date.
 * iOS uses `decodeFullDate()` which handles both tag(1004) and plain text.
 * Here we accept both TextStringVal and tagged UInt64Val date as plain string.
 */
func cborMapGetFullDate(
    pairs: ArrayList<(CborValue, CborValue)>,
    key: String
): ?String {
    var i: Int64 = 0
    while (i < pairs.size) {
        let (k, v) = pairs[i]
        match (k) {
            case CborValue.TextStringVal(ks) =>
                if (ks == key) {
                    match (v) {
                        case CborValue.TextStringVal(s) => return Some(s)
                        case CborValue.TaggedVal(_, inner) =>
                            match (inner) {
                                case CborValue.TextStringVal(s) => return Some(s)
                                case _ => return None
                            }
                        case _ => return None
                    }
                }
            case _ => ()
        }
        i++
    }
    return None
}

/**
 * Lookup an array of DrivingPrivilegeCode values under the given key.
 * Returns None if key absent or value not an array.
 */
func cborMapGetArrayOfCodes(
    pairs: ArrayList<(CborValue, CborValue)>,
    key: String
): ?ArrayList<DrivingPrivilegeCode> {
    var i: Int64 = 0
    while (i < pairs.size) {
        let (k, v) = pairs[i]
        match (k) {
            case CborValue.TextStringVal(ks) =>
                if (ks == key) {
                    match (v) {
                        case CborValue.ArrayVal(items) =>
                            let result = ArrayList<DrivingPrivilegeCode>()
                            var j: Int64 = 0
                            while (j < items.size) {
                                match (DrivingPrivilegeCode.fromCbor(items[j])) {
                                    case Some(c) => result.add(c)
                                    case None => ()
                                }
                                j++
                            }
                            return Some(result)
                        case _ => return None
                    }
                }
            case _ => ()
        }
        i++
    }
    return None
}

/**
 * Lookup a CborValue in a namespace/element claims map
 * (HashMap<String, HashMap<String, CborValue>>).
 * Returns None if namespace or elementId not present.
 * R-104 compliant: uses .get() which returns ?V.
 */
func claimsGetValue(
    claims: HashMap<String, HashMap<String, CborValue>>,
    namespace: String,
    elementId: String
): ?CborValue {
    match (claims.get(namespace)) {
        case None => return None
        case Some(nsMap) =>
            return nsMap.get(elementId)
    }
}

/**
 * Extract a String claim from the claims map.
 */
func claimsGetString(
    claims: HashMap<String, HashMap<String, CborValue>>,
    namespace: String,
    elementId: String
): ?String {
    match (claimsGetValue(claims, namespace, elementId)) {
        case Some(CborValue.TextStringVal(s)) => return Some(s)
        case _ => return None
    }
}

/**
 * Extract a UInt64 claim from the claims map.
 */
func claimsGetUInt64(
    claims: HashMap<String, HashMap<String, CborValue>>,
    namespace: String,
    elementId: String
): ?UInt64 {
    match (claimsGetValue(claims, namespace, elementId)) {
        case Some(CborValue.UInt64Val(n)) => return Some(n)
        case _ => return None
    }
}

/**
 * Extract a byte array claim from the claims map.
 */
func claimsGetBytes(
    claims: HashMap<String, HashMap<String, CborValue>>,
    namespace: String,
    elementId: String
): ?Array<UInt8> {
    match (claimsGetValue(claims, namespace, elementId)) {
        case Some(CborValue.ByteStringVal(b)) => return Some(b)
        case _ => return None
    }
}

/**
 * Parse a decimal ASCII string to Int64.
 * Digits-only, no sign prefix.
 * Returns None if empty or any non-digit character encountered.
 *
 * Implementation: iterates over Rune array positions, uses Rune.position()
 * (ordinal code point) rather than toString() on each Rune.
 * S-018 compliant: no for-in loop + Rune.toString() combination.
 * '0'.position() == 48, '9'.position() == 57 (ASCII).
 */
func doctypesParseInt64(s: String): ?Int64 {
    let runes = s.toRuneArray()
    if (runes.size == 0) {
        return None
    }
    let digitMin = r'0'.position()
    let digitMax = r'9'.position()
    var result: Int64 = 0
    var i: Int64 = 0
    while (i < runes.size) {
        let pos = runes[i].position()
        if (pos < digitMin || pos > digitMax) {
            return None
        }
        result = result * 10 + (pos - digitMin)
        i++
    }
    return Some(result)
}

/**
 * Extract an age_over_NN map from claims.
 * Scans all elements in namespace whose key starts with "age_over_".
 * key format: "age_over_18", "age_over_21" etc.
 * S-008 compliant: uses String.startsWith, not toLower/toUpper.
 * S-018 compliant: no for-in Rune toString loop.
 */
func extractAgeOverValues(
    claims: HashMap<String, HashMap<String, CborValue>>,
    namespace: String
): HashMap<Int64, Bool> {
    let result = HashMap<Int64, Bool>()
    match (claims.get(namespace)) {
        case None => return result
        case Some(nsMap) =>
            for ((elemId, val) in nsMap) {
                if (elemId.startsWith("age_over_")) {
                    let suffix = elemId[9..]
                    match (doctypesParseInt64(suffix)) {
                        case Some(age) =>
                            match (val) {
                                case CborValue.BoolVal(b) =>
                                    result.add(age, b)
                                case _ => ()
                            }
                        case None => ()
                    }
                }
            }
    }
    return result
}

/**
 * Extract a DrivingPrivileges from claims map.
 */
func claimsGetDrivingPrivileges(
    claims: HashMap<String, HashMap<String, CborValue>>,
    namespace: String,
    elementId: String
): ?DrivingPrivileges {
    match (claimsGetValue(claims, namespace, elementId)) {
        case Some(cbor) => return DrivingPrivileges.fromCbor(cbor)
        case None => return None
    }
}

/* ======================================================================
 * IsoMdlModel
 * Mirrors iOS `IsoMdlModel: DocClaimsModel`
 * Implements DocClaimsDecodable + AgeAttesting.
 * ====================================================================== */

/** docType constant for ISO 18013-5.1 mDL. */
public let ISO_MDL_DOC_TYPE: String = "org.iso.18013.5.1.mDL"
/** Namespace for ISO 18013-5.1 mDL claims. */
public let ISO_MDL_NAMESPACE: String = "org.iso.18013.5.1"

/**
 * ISO 18013-5.1 mDL document model.
 *
 * Constructed from a CBOR claims map; exposes all mDL fields as optional
 * properties and implements DocClaimsDecodable for registry dispatch.
 */
public class IsoMdlModel <: DocClaimsDecodable & AgeAttesting {
    /* Core DocClaimsDecodable fields */
    private let id_: String
    private let docClaims_: ArrayList<DocClaim>
    private let displayName_: ?String
    private let display_: ?ArrayList<DisplayMetadata>
    private let issuerDisplay_: ?ArrayList<DisplayMetadata>
    private let ageOverXX_: HashMap<Int64, Bool>

    /* mDL specific fields — all optional as per iOS source */
    public let familyName: ?String
    public let givenName: ?String
    public let birthDate: ?String
    public let birthPlace: ?String
    public let issueDate: ?String
    public let expiryDate: ?String
    public let issuingCountry: ?String
    public let issuingAuthority: ?String
    public let documentNumber: ?String
    public let administrativeNumber: ?String
    public let drivingPrivileges: ?DrivingPrivileges
    public let nationality: ?String
    public let eyeColour: ?String
    public let hairColour: ?String
    public let heightCm: ?UInt64
    public let weightKg: ?UInt64
    public let sex: ?UInt64
    public let residentAddress: ?String
    public let residentCountry: ?String
    public let residentCity: ?String
    public let residentState: ?String
    public let residentPostalCode: ?String
    public let ageInYears: ?UInt64
    public let ageBirthYear: ?UInt64
    public let portrait: ?Array<UInt8>
    public let unDistinguishingSign: ?String
    public let issuingJurisdiction: ?String
    public let portraitCaptureDate: ?String
    public let familyNameNationalCharacter: ?String
    public let givenNameNationalCharacter: ?String
    public let signatureUsualMark: ?Array<UInt8>
    public let biometricTemplateFace: ?String
    public let biometricTemplateSignatureSign: ?String

    public init(
        id: String,
        claims: HashMap<String, HashMap<String, CborValue>>,
        metadata: ?DocMetadata
    ) {
        this.id_ = id
        let ns = ISO_MDL_NAMESPACE

        this.familyName = claimsGetString(claims, ns, "family_name")
        this.givenName = claimsGetString(claims, ns, "given_name")
        this.birthDate = claimsGetString(claims, ns, "birth_date")
        this.birthPlace = claimsGetString(claims, ns, "birth_place")
        this.issueDate = claimsGetString(claims, ns, "issue_date")
        this.expiryDate = claimsGetString(claims, ns, "expiry_date")
        this.issuingCountry = claimsGetString(claims, ns, "issuing_country")
        this.issuingAuthority = claimsGetString(claims, ns, "issuing_authority")
        this.documentNumber = claimsGetString(claims, ns, "document_number")
        this.administrativeNumber = claimsGetString(claims, ns, "administrative_number")
        this.drivingPrivileges = claimsGetDrivingPrivileges(claims, ns, "driving_privileges")
        this.nationality = claimsGetString(claims, ns, "nationality")
        this.eyeColour = claimsGetString(claims, ns, "eye_colour")
        this.hairColour = claimsGetString(claims, ns, "hair_colour")
        this.heightCm = claimsGetUInt64(claims, ns, "height")
        this.weightKg = claimsGetUInt64(claims, ns, "weight")
        this.sex = claimsGetUInt64(claims, ns, "sex")
        this.residentAddress = claimsGetString(claims, ns, "resident_address")
        this.residentCountry = claimsGetString(claims, ns, "resident_country")
        this.residentCity = claimsGetString(claims, ns, "resident_city")
        this.residentState = claimsGetString(claims, ns, "resident_state")
        this.residentPostalCode = claimsGetString(claims, ns, "resident_postal_code")
        this.ageInYears = claimsGetUInt64(claims, ns, "age_in_years")
        this.ageBirthYear = claimsGetUInt64(claims, ns, "age_birth_year")
        this.portrait = claimsGetBytes(claims, ns, "portrait")
        this.unDistinguishingSign = claimsGetString(claims, ns, "un_distinguishing_sign")
        this.issuingJurisdiction = claimsGetString(claims, ns, "issuing_jurisdiction")
        this.portraitCaptureDate = claimsGetString(claims, ns, "portrait_capture_date")
        this.familyNameNationalCharacter = claimsGetString(claims, ns, "family_name_national_character")
        this.givenNameNationalCharacter = claimsGetString(claims, ns, "given_name_national_character")
        this.signatureUsualMark = claimsGetBytes(claims, ns, "signature_usual_mark")
        this.biometricTemplateFace = claimsGetString(claims, ns, "biometric_template_face")
        this.biometricTemplateSignatureSign = claimsGetString(claims, ns, "biometric_template_signature_sign")

        this.ageOverXX_ = extractAgeOverValues(claims, ns)

        /* Build DocClaim list from all extracted fields */
        this.docClaims_ = buildDocClaimsFromCborMap(claims, ns)

        /* Extract display metadata from DocMetadata if provided */
        match (metadata) {
            case Some(m) =>
                this.displayName_ = m.getDisplayName(None)
                this.display_ = m.display
                this.issuerDisplay_ = m.issuerDisplay
            case None =>
                this.displayName_ = None
                this.display_ = None
                this.issuerDisplay_ = None
        }
    }

    /* --- DocClaimsDecodable implementation --- */

    public func getId(): String {
        return this.id_
    }

    public func getDocType(): String {
        return ISO_MDL_DOC_TYPE
    }

    public func getDocClaims(): ArrayList<DocClaim> {
        return this.docClaims_
    }

    public func getDocDataFormat(): DocDataFormat {
        return DocDataFormat.Cbor
    }

    public func getDisplayName(): ?String {
        return this.displayName_
    }

    public func getDisplay(): ?ArrayList<DisplayMetadata> {
        return this.display_
    }

    public func getIssuerDisplay(): ?ArrayList<DisplayMetadata> {
        return this.issuerDisplay_
    }

    /* --- AgeAttesting implementation --- */

    public func getAgeOverXX(): HashMap<Int64, Bool> {
        return this.ageOverXX_
    }

    /**
     * Determines if the age is over a specified threshold.
     * Mirrors iOS `AgeAttesting.isOver(age:)`.
     * Returns (key, value) tuple or None.
     */
    public func isOver(age: Int64): ?(Int64, Bool) {
        return ageAttestIsOver(this.ageOverXX_, age)
    }
}

/* ======================================================================
 * IsoMdlModelFactory
 * ====================================================================== */

/**
 * Factory that constructs IsoMdlModel instances from CBOR claim data.
 * Registers itself in DocClaimsDecodableRegistry for ISO_MDL_DOC_TYPE.
 */
public class IsoMdlModelFactory <: DocClaimsDecodableFactory {
    public init() {}

    public func make(
        docType: String,
        claims: HashMap<String, HashMap<String, CborValue>>,
        metadata: ?DocMetadata
    ): ?DocClaimsDecodable {
        if (docType != ISO_MDL_DOC_TYPE) {
            return None
        }
        let id = "mdl-" + docType
        let model = IsoMdlModel(id, claims, metadata)
        return Some(model)
    }
}

/* ======================================================================
 * EuPidModel
 * Mirrors iOS `EuPidModel: DocClaimsModel`
 * Implements DocClaimsDecodable + AgeAttesting.
 * ====================================================================== */

/** docType constant for EU PID. */
public let EU_PID_DOC_TYPE: String = "eu.europa.ec.eudi.pid.1"
/** Namespace for EU PID claims. */
public let EU_PID_NAMESPACE: String = "eu.europa.ec.eudi.pid.1"

/**
 * EU PID document model.
 *
 * Constructed from a CBOR claims map; exposes all PID fields as optional
 * properties and implements DocClaimsDecodable for registry dispatch.
 */
public class EuPidModel <: DocClaimsDecodable & AgeAttesting {
    /* Core DocClaimsDecodable fields */
    private let id_: String
    private let docClaims_: ArrayList<DocClaim>
    private let displayName_: ?String
    private let display_: ?ArrayList<DisplayMetadata>
    private let issuerDisplay_: ?ArrayList<DisplayMetadata>
    private let ageOverXX_: HashMap<Int64, Bool>

    /* PID specific fields — all optional as per iOS source */
    public let familyName: ?String
    public let givenName: ?String
    public let birthDate: ?String
    public let familyNameBirth: ?String
    public let givenNameBirth: ?String
    public let birthPlace: ?String
    public let birthCountry: ?String
    public let birthState: ?String
    public let birthCity: ?String
    public let residentAddress: ?String
    public let residentCity: ?String
    public let residentPostalCode: ?String
    public let residentState: ?String
    public let residentCountry: ?String
    public let residentStreet: ?String
    public let residentHouseNumber: ?String
    public let sex: ?UInt64
    public let ageInYears: ?UInt64
    public let ageBirthYear: ?UInt64
    public let expiryDate: ?String
    public let issuingAuthority: ?String
    public let issuanceDate: ?String
    public let documentNumber: ?String
    public let personalAdministrativeNumber: ?String
    public let issuingCountry: ?String
    public let issuingJurisdiction: ?String
    public let emailAddress: ?String
    public let mobilePhoneNumber: ?String
    public let trustAnchor: ?String

    public init(
        id: String,
        claims: HashMap<String, HashMap<String, CborValue>>,
        metadata: ?DocMetadata
    ) {
        this.id_ = id
        let ns = EU_PID_NAMESPACE

        this.familyName = claimsGetString(claims, ns, "family_name")
        this.givenName = claimsGetString(claims, ns, "given_name")
        this.birthDate = claimsGetString(claims, ns, "birth_date")
        this.familyNameBirth = claimsGetString(claims, ns, "family_name_birth")
        this.givenNameBirth = claimsGetString(claims, ns, "given_name_birth")
        this.birthPlace = claimsGetString(claims, ns, "birth_place")
        this.birthCountry = claimsGetString(claims, ns, "birth_country")
        this.birthState = claimsGetString(claims, ns, "birth_state")
        this.birthCity = claimsGetString(claims, ns, "birth_city")
        this.residentAddress = claimsGetString(claims, ns, "resident_address")
        this.residentCity = claimsGetString(claims, ns, "resident_city")
        this.residentPostalCode = claimsGetString(claims, ns, "resident_postal_code")
        this.residentState = claimsGetString(claims, ns, "resident_state")
        this.residentCountry = claimsGetString(claims, ns, "resident_country")
        this.residentStreet = claimsGetString(claims, ns, "resident_street")
        this.residentHouseNumber = claimsGetString(claims, ns, "resident_house_number")
        this.sex = claimsGetUInt64(claims, ns, "sex")
        this.ageInYears = claimsGetUInt64(claims, ns, "age_in_years")
        this.ageBirthYear = claimsGetUInt64(claims, ns, "age_birth_year")
        this.expiryDate = claimsGetString(claims, ns, "expiry_date")
        this.issuingAuthority = claimsGetString(claims, ns, "issuing_authority")
        this.issuanceDate = claimsGetString(claims, ns, "issuance_date")
        this.documentNumber = claimsGetString(claims, ns, "document_number")
        this.personalAdministrativeNumber = claimsGetString(claims, ns, "personal_administrative_number")
        this.issuingCountry = claimsGetString(claims, ns, "issuing_country")
        this.issuingJurisdiction = claimsGetString(claims, ns, "issuing_jurisdiction")
        this.emailAddress = claimsGetString(claims, ns, "email_address")
        this.mobilePhoneNumber = claimsGetString(claims, ns, "mobile_phone_number")
        this.trustAnchor = claimsGetString(claims, ns, "trust_anchor")

        this.ageOverXX_ = extractAgeOverValues(claims, ns)

        /* Build DocClaim list from all extracted fields */
        this.docClaims_ = buildDocClaimsFromCborMap(claims, ns)

        /* Extract display metadata from DocMetadata if provided */
        match (metadata) {
            case Some(m) =>
                this.displayName_ = m.getDisplayName(None)
                this.display_ = m.display
                this.issuerDisplay_ = m.issuerDisplay
            case None =>
                this.displayName_ = None
                this.display_ = None
                this.issuerDisplay_ = None
        }
    }

    /* --- DocClaimsDecodable implementation --- */

    public func getId(): String {
        return this.id_
    }

    public func getDocType(): String {
        return EU_PID_DOC_TYPE
    }

    public func getDocClaims(): ArrayList<DocClaim> {
        return this.docClaims_
    }

    public func getDocDataFormat(): DocDataFormat {
        return DocDataFormat.Cbor
    }

    public func getDisplayName(): ?String {
        return this.displayName_
    }

    public func getDisplay(): ?ArrayList<DisplayMetadata> {
        return this.display_
    }

    public func getIssuerDisplay(): ?ArrayList<DisplayMetadata> {
        return this.issuerDisplay_
    }

    /* --- AgeAttesting implementation --- */

    public func getAgeOverXX(): HashMap<Int64, Bool> {
        return this.ageOverXX_
    }

    /**
     * Determines if the age is over a specified threshold.
     * Mirrors iOS `AgeAttesting.isOver(age:)`.
     */
    public func isOver(age: Int64): ?(Int64, Bool) {
        return ageAttestIsOver(this.ageOverXX_, age)
    }
}

/* ======================================================================
 * EuPidModelFactory
 * ====================================================================== */

/**
 * Factory that constructs EuPidModel instances from CBOR claim data.
 * Registers itself in DocClaimsDecodableRegistry for EU_PID_DOC_TYPE.
 */
public class EuPidModelFactory <: DocClaimsDecodableFactory {
    public init() {}

    public func make(
        docType: String,
        claims: HashMap<String, HashMap<String, CborValue>>,
        metadata: ?DocMetadata
    ): ?DocClaimsDecodable {
        if (docType != EU_PID_DOC_TYPE) {
            return None
        }
        let id = "pid-" + docType
        let model = EuPidModel(id, claims, metadata)
        return Some(model)
    }
}

/* ======================================================================
 * Registry initialisation helpers
 * ====================================================================== */

/**
 * Register both IsoMdlModel and EuPidModel factories in the global registry.
 * Call once at application startup before any DocClaimsDecodableRegistry.make()
 * calls for mDL or EU PID docTypes.
 */
public func registerKnownDocTypeFactories(): Unit {
    DocClaimsDecodableRegistry.register(ISO_MDL_DOC_TYPE, IsoMdlModelFactory())
    DocClaimsDecodableRegistry.register(EU_PID_DOC_TYPE, EuPidModelFactory())
}

/* ======================================================================
 * Internal helper: build DocClaim list from a CBOR claims namespace map
 * ====================================================================== */

/**
 * Build a flat ArrayList<DocClaim> from a namespace's claim elements.
 * Each top-level element becomes a DocClaim node; nested maps/arrays
 * are expanded recursively via DocClaim.fromCbor.
 */
func buildDocClaimsFromCborMap(
    claims: HashMap<String, HashMap<String, CborValue>>,
    namespace: String
): ArrayList<DocClaim> {
    let result = ArrayList<DocClaim>()
    match (claims.get(namespace)) {
        case None => return result
        case Some(nsMap) =>
            var order: Int64 = 0
            for ((elemId, cbor) in nsMap) {
                let path = ArrayList<String>()
                path.add(namespace)
                path.add(elemId)
                let claim = DocClaim.fromCbor(
                    elemId, path, cbor, namespace, order, None, None
                )
                result.add(claim)
                order++
            }
    }
    return result
}
