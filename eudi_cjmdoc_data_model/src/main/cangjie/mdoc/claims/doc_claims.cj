/*
 * doc_claims.cj
 *
 * Cangjie port of the iOS MdocDataModel18013 DocumentClaims layer.
 *
 * Implements:
 *   DocDataFormat             — enum mirroring iOS DocDataFormat
 *   LogoMetadata              — JSON-serialisable logo
 *   DisplayMetadata           — JSON-serialisable display metadata
 *   DocClaimMetadata          — JSON-serialisable claim metadata
 *   DocMetadata               — JSON-serialisable document metadata
 *   DocDataValue              — typed claim value (CBOR-convertible)
 *   DocClaim                  — recursive claim model (CBOREncodable)
 *   DocClaimsDecodable        — interface for decoded document claims
 *   DocClaimsDecodableFactory — interface + in-process registry
 *
 * iOS source references:
 *   DocumentClaims/DocDataFormat.swift
 *   DocumentClaims/LogoMetadata.swift
 *   DocumentClaims/DisplayMetadata.swift
 *   DocumentClaims/DocClaimMetadata.swift
 *   DocumentClaims/DocMetadata.swift
 *   DocumentClaims/DocClaim.swift
 *   DocumentClaims/DocClaimsDecodable.swift
 *   DocumentClaims/DocClaimsDecodableFactory.swift
 *
 * Package: ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims  (S-002)
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.claims

import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CBOREncodable
import std.collection.ArrayList
import std.collection.HashMap
import stdx.encoding.json.JsonValue
import stdx.encoding.json.JsonObject
import stdx.encoding.json.JsonArray
import stdx.encoding.json.JsonString
import stdx.encoding.json.JsonBool
import stdx.encoding.json.JsonNull

/* ======================================================================
 * DocDataFormat
 * Mirrors iOS `DocDataFormat: String, Sendable, Codable` enum.
 * ====================================================================== */

/**
 * Format of document data.
 *
 * Cbor  — ISO 18013-5 mso_mdoc (IssuerSigned CBOR-encoded)
 * Sdjwt — vc+sd-jwt encoded
 */
public enum DocDataFormat {
    | Cbor
    | Sdjwt

    /** Human-readable description, mirrors iOS .description. */
    public func description(): String {
        match (this) {
            case Cbor  => return "mso_mdoc"
            case Sdjwt => return "vc+sd-jwt"
        }
    }

    /** Raw string value for JSON serialisation (mirrors iOS rawValue). */
    public func rawValue(): String {
        match (this) {
            case Cbor  => return "cbor"
            case Sdjwt => return "sjwt"
        }
    }

    /** Parse from raw string. Returns None if unrecognised. */
    public static func fromRaw(raw: String): ?DocDataFormat {
        match (raw) {
            case "cbor" => return Some(DocDataFormat.Cbor)
            case "sjwt" => return Some(DocDataFormat.Sdjwt)
            case _      => return None
        }
    }
}

/* ======================================================================
 * LogoMetadata
 * Mirrors iOS `LogoMetadata: Codable, Equatable, Sendable`
 * ====================================================================== */

/** Logo metadata for display purposes. */
public class LogoMetadata {
    public let urlString: ?String
    public let alternativeText: ?String

    public init(urlString: ?String, alternativeText: ?String) {
        this.urlString = urlString
        this.alternativeText = alternativeText
    }

    /** Serialise to JsonObject. */
    public func toJson(): JsonObject {
        let obj = JsonObject()
        match (this.urlString) {
            case Some(s) => obj.put("urlString", JsonString(s))
            case None    => obj.put("urlString", JsonNull())
        }
        match (this.alternativeText) {
            case Some(s) => obj.put("alternativeText", JsonString(s))
            case None    => obj.put("alternativeText", JsonNull())
        }
        return obj
    }

    /** Deserialise from JsonObject. */
    public static func fromJson(obj: JsonObject): ?LogoMetadata {
        return Some(LogoMetadata(jsonOptString(obj, "urlString"),
                                 jsonOptString(obj, "alternativeText")))
    }
}

/* ======================================================================
 * DisplayMetadata
 * Mirrors iOS `DisplayMetadata: Codable, Equatable, Sendable`
 * ====================================================================== */

/** Display properties for a document or issuer (localised). */
public class DisplayMetadata {
    public let name: ?String
    public let localeIdentifier: ?String
    public let logo: ?LogoMetadata
    public let description: ?String
    public let backgroundColor: ?String
    public let textColor: ?String
    public let backgroundImageURL: ?String

    public init(name: ?String, localeIdentifier: ?String, logo: ?LogoMetadata,
                description: ?String, backgroundColor: ?String,
                textColor: ?String, backgroundImageURL: ?String) {
        this.name = name
        this.localeIdentifier = localeIdentifier
        this.logo = logo
        this.description = description
        this.backgroundColor = backgroundColor
        this.textColor = textColor
        this.backgroundImageURL = backgroundImageURL
    }

    /** Serialise to JsonObject. */
    public func toJson(): JsonObject {
        let obj = JsonObject()
        match (this.name) {
            case Some(s) => obj.put("name", JsonString(s))
            case None    => obj.put("name", JsonNull())
        }
        match (this.localeIdentifier) {
            case Some(s) => obj.put("localeIdentifier", JsonString(s))
            case None    => obj.put("localeIdentifier", JsonNull())
        }
        match (this.logo) {
            case Some(l) => obj.put("logo", l.toJson())
            case None    => obj.put("logo", JsonNull())
        }
        match (this.description) {
            case Some(s) => obj.put("description", JsonString(s))
            case None    => obj.put("description", JsonNull())
        }
        match (this.backgroundColor) {
            case Some(s) => obj.put("backgroundColor", JsonString(s))
            case None    => obj.put("backgroundColor", JsonNull())
        }
        match (this.textColor) {
            case Some(s) => obj.put("textColor", JsonString(s))
            case None    => obj.put("textColor", JsonNull())
        }
        match (this.backgroundImageURL) {
            case Some(s) => obj.put("backgroundImageURL", JsonString(s))
            case None    => obj.put("backgroundImageURL", JsonNull())
        }
        return obj
    }

    /** Deserialise from JsonObject. */
    public static func fromJson(obj: JsonObject): ?DisplayMetadata {
        let logoOpt: ?LogoMetadata = match (obj.get("logo")) {
            case Some(v) =>
                match (v as JsonObject) {
                    case Some(lo) => LogoMetadata.fromJson(lo)
                    case None     => None
                }
            case None => None
        }
        return Some(DisplayMetadata(
            jsonOptString(obj, "name"),
            jsonOptString(obj, "localeIdentifier"),
            logoOpt,
            jsonOptString(obj, "description"),
            jsonOptString(obj, "backgroundColor"),
            jsonOptString(obj, "textColor"),
            jsonOptString(obj, "backgroundImageURL")
        ))
    }

    /**
     * Returns true if this entry matches the requested locale/culture string.
     * Used by getDisplayName() to pick the best locale match.
     */
    public func matchesLocale(uiCulture: ?String): Bool {
        match (uiCulture) {
            case None => return true
            case Some(culture) =>
                match (this.localeIdentifier) {
                    case None => return true
                    case Some(lid) =>
                        return lid.startsWith(culture) || culture.startsWith(lid)
                }
        }
    }
}

/**
 * Get display name from an ArrayList<DisplayMetadata> for the given locale.
 * Mirrors iOS `[DisplayMetadata].getName(_:)` extension method.
 */
public func getDisplayName(displays: ArrayList<DisplayMetadata>, uiCulture: ?String): ?String {
    var i: Int64 = 0
    while (i < displays.size) {
        let dm = displays[i]
        if (dm.matchesLocale(uiCulture)) {
            return dm.name
        }
        i++
    }
    if (displays.size > 0) {
        return displays[0].name
    }
    return None
}

/* ======================================================================
 * DocClaimMetadata
 * Mirrors iOS `DocClaimMetadata: Sendable, Codable`
 * ====================================================================== */

/**
 * Metadata describing a single claim field — its localised display name,
 * path, optionality, and declared value type.
 */
public class DocClaimMetadata {
    public let display: ?ArrayList<DisplayMetadata>
    public let isMandatory: ?Bool
    public let claimPath: ArrayList<String>
    public let valueType: ?String

    public init(display: ?ArrayList<DisplayMetadata>, isMandatory: ?Bool,
                claimPath: ArrayList<String>, valueType: ?String) {
        this.display = display
        this.isMandatory = isMandatory
        this.claimPath = claimPath
        this.valueType = valueType
    }

    /** Get localised display name. */
    public func getDisplayName(uiCulture: ?String): ?String {
        match (this.display) {
            case None    => return None
            case Some(ds) => return getDisplayName(ds, uiCulture)
        }
    }

    /** Serialise to JsonObject. */
    public func toJson(): JsonObject {
        let obj = JsonObject()
        match (this.display) {
            case Some(ds) =>
                var arr = JsonArray()
                var i: Int64 = 0
                while (i < ds.size) {
                    arr = arr.add(ds[i].toJson())
                    i++
                }
                obj.put("display", arr)
            case None => obj.put("display", JsonNull())
        }
        match (this.isMandatory) {
            case Some(b) => obj.put("isMandatory", JsonBool(b))
            case None    => obj.put("isMandatory", JsonNull())
        }
        var pathArr = JsonArray()
        var i: Int64 = 0
        while (i < this.claimPath.size) {
            pathArr = pathArr.add(JsonString(this.claimPath[i]))
            i++
        }
        obj.put("claimPath", pathArr)
        match (this.valueType) {
            case Some(s) => obj.put("valueType", JsonString(s))
            case None    => obj.put("valueType", JsonNull())
        }
        return obj
    }

    /** Deserialise from JsonObject. */
    public static func fromJson(obj: JsonObject): ?DocClaimMetadata {
        let isMandatory: ?Bool = match (obj.get("isMandatory")) {
            case Some(v) =>
                match (v as JsonBool) {
                    case Some(jb) => Some(jb.getValue())
                    case None     => None
                }
            case None => None
        }
        let claimPath = ArrayList<String>()
        match (obj.get("claimPath")) {
            case Some(v) =>
                match (v as JsonArray) {
                    case Some(arr) =>
                        var j: Int64 = 0
                        while (j < arr.size()) {
                            match (arr.get(j)) {
                                case Some(elem) =>
                                    match (elem as JsonString) {
                                        case Some(js) => claimPath.add(js.getValue())
                                        case None => ()
                                    }
                                case None => ()
                            }
                            j++
                        }
                    case None => ()
                }
            case None => ()
        }
        return Some(DocClaimMetadata(
            parseDisplayArray(obj, "display"),
            isMandatory,
            claimPath,
            jsonOptString(obj, "valueType")
        ))
    }
}

/* ======================================================================
 * DocMetadata
 * Mirrors iOS `DocMetadata: Sendable, Codable`
 * JSON-only (never CBOR-encoded; stored as opaque JSON in the wallet DB)
 * ====================================================================== */

/**
 * Metadata for a document — issuer info, display properties, claim schema.
 * Serialised and deserialised as JSON.
 */
public class DocMetadata {
    public let credentialIssuerIdentifier: String
    public let configurationIdentifier: String
    public let docType: String
    public let display: ?ArrayList<DisplayMetadata>
    public let issuerDisplay: ?ArrayList<DisplayMetadata>
    public let claims: ?ArrayList<DocClaimMetadata>
    public let dpopKeyId: ?String

    public init(credentialIssuerIdentifier: String,
                configurationIdentifier: String,
                docType: String,
                display: ?ArrayList<DisplayMetadata>,
                issuerDisplay: ?ArrayList<DisplayMetadata>,
                claims: ?ArrayList<DocClaimMetadata>,
                dpopKeyId: ?String) {
        this.credentialIssuerIdentifier = credentialIssuerIdentifier
        this.configurationIdentifier = configurationIdentifier
        this.docType = docType
        this.display = display
        this.issuerDisplay = issuerDisplay
        this.claims = claims
        this.dpopKeyId = dpopKeyId
    }

    /** Get display name for the given locale. */
    public func getDisplayName(uiCulture: ?String): ?String {
        match (this.display) {
            case None    => return None
            case Some(ds) => return getDisplayName(ds, uiCulture)
        }
    }

    /** Get issuer display name for the given locale. */
    public func getIssuerDisplayName(uiCulture: ?String): ?String {
        match (this.issuerDisplay) {
            case None    => return None
            case Some(ds) => return getDisplayName(ds, uiCulture)
        }
    }

    /** Serialise to JSON string (mirrors iOS JSONEncoder().encode). */
    public func toJsonString(): String {
        return this.toJson().toString()
    }

    /** Serialise to JsonObject. */
    public func toJson(): JsonObject {
        let obj = JsonObject()
        obj.put("credentialIssuerIdentifier", JsonString(this.credentialIssuerIdentifier))
        obj.put("configurationIdentifier", JsonString(this.configurationIdentifier))
        obj.put("docType", JsonString(this.docType))
        match (this.display) {
            case Some(ds) =>
                var arr = JsonArray()
                var i: Int64 = 0
                while (i < ds.size) {
                    arr = arr.add(ds[i].toJson())
                    i++
                }
                obj.put("display", arr)
            case None => obj.put("display", JsonNull())
        }
        match (this.issuerDisplay) {
            case Some(ds) =>
                var arr = JsonArray()
                var i: Int64 = 0
                while (i < ds.size) {
                    arr = arr.add(ds[i].toJson())
                    i++
                }
                obj.put("issuerDisplay", arr)
            case None => obj.put("issuerDisplay", JsonNull())
        }
        match (this.claims) {
            case Some(cs) =>
                var arr = JsonArray()
                var i: Int64 = 0
                while (i < cs.size) {
                    arr = arr.add(cs[i].toJson())
                    i++
                }
                obj.put("claims", arr)
            case None => obj.put("claims", JsonNull())
        }
        match (this.dpopKeyId) {
            case Some(s) => obj.put("dpopKeyId", JsonString(s))
            case None    => obj.put("dpopKeyId", JsonNull())
        }
        return obj
    }

    /** Deserialise from JSON string. Returns None on parse error. */
    public static func fromJsonString(jsonStr: String): ?DocMetadata {
        let parsed: JsonValue
        try {
            parsed = JsonValue.fromStr(jsonStr)
        } catch (e: Exception) {
            return None
        }
        match (parsed as JsonObject) {
            case Some(obj) => return DocMetadata.fromJson(obj)
            case None      => return None
        }
    }

    /** Deserialise from JsonObject. Returns None if required fields missing. */
    public static func fromJson(obj: JsonObject): ?DocMetadata {
        let issuerIdOpt  = jsonOptString(obj, "credentialIssuerIdentifier")
        let configIdOpt  = jsonOptString(obj, "configurationIdentifier")
        let docTypeOpt   = jsonOptString(obj, "docType")
        match ((issuerIdOpt, configIdOpt, docTypeOpt)) {
            case (Some(issuerId), Some(configId), Some(docType)) =>
                let claimsList: ?ArrayList<DocClaimMetadata> = match (obj.get("claims")) {
                    case Some(v) =>
                        match (v as JsonArray) {
                            case Some(arr) =>
                                let result = ArrayList<DocClaimMetadata>()
                                var i: Int64 = 0
                                while (i < arr.size()) {
                                    match (arr.get(i)) {
                                        case Some(elem) =>
                                            match (elem as JsonObject) {
                                                case Some(co) =>
                                                    match (DocClaimMetadata.fromJson(co)) {
                                                        case Some(cm) => result.add(cm)
                                                        case None     => ()
                                                    }
                                                case None => ()
                                            }
                                        case None => ()
                                    }
                                    i++
                                }
                                Some(result)
                            case None => None
                        }
                    case None => None
                }
                return Some(DocMetadata(
                    issuerId, configId, docType,
                    parseDisplayArray(obj, "display"),
                    parseDisplayArray(obj, "issuerDisplay"),
                    claimsList,
                    jsonOptString(obj, "dpopKeyId")
                ))
            case _ => return None
        }
    }
}

/* ======================================================================
 * Shared JSON helpers
 * ====================================================================== */

/** Extract an optional String field from a JsonObject. */
func jsonOptString(obj: JsonObject, key: String): ?String {
    match (obj.get(key)) {
        case Some(v) =>
            match (v as JsonString) {
                case Some(js) => return Some(js.getValue())
                case None     => return None
            }
        case None => return None
    }
}

/** Parse an ArrayList<DisplayMetadata> from an array field of a JsonObject. */
func parseDisplayArray(obj: JsonObject, key: String): ?ArrayList<DisplayMetadata> {
    match (obj.get(key)) {
        case Some(v) =>
            match (v as JsonArray) {
                case Some(arr) =>
                    let result = ArrayList<DisplayMetadata>()
                    var i: Int64 = 0
                    while (i < arr.size()) {
                        match (arr.get(i)) {
                            case Some(elem) =>
                                match (elem as JsonObject) {
                                    case Some(dobj) =>
                                        match (DisplayMetadata.fromJson(dobj)) {
                                            case Some(dm) => result.add(dm)
                                            case None     => ()
                                        }
                                    case None => ()
                                }
                            case None => ()
                        }
                        i++
                    }
                    return Some(result)
                case None => return None
            }
        case None => return None
    }
}

/* ======================================================================
 * DocDataValue
 * Typed claim value — CBOR-convertible.
 * Uses ArrayList<(String, DocDataValue)> for map type to avoid HashMap
 * iteration complexity; preserves insertion order for CBOR round-trips.
 * ====================================================================== */

/**
 * Typed leaf-or-container value for a document claim.
 * Mirrors iOS DocDataValue enum (associated values).
 *
 * NOTE: MapEntries uses ArrayList<(String, DocDataValue)> (not HashMap)
 * so that CBOR key ordering is deterministic and for-in destructuring
 * `for ((k, v) in entries)` works reliably (see cbor_value.cj pattern).
 */
public enum DocDataValue {
    | StringVal(String)
    | IntVal(Int64)
    | BoolVal(Bool)
    | DoubleVal(Float64)
    | BytesVal(Array<UInt8>)
    | MapEntries(ArrayList<(String, DocDataValue)>)
    | ArrayEntries(ArrayList<DocDataValue>)
    | DateVal(String)
    | NullVal

    /** Convert to CborValue for CBOR serialisation. */
    public func toCbor(): CborValue {
        match (this) {
            case StringVal(s) => return CborValue.TextStringVal(s)
            case IntVal(n) =>
                if (n >= 0) {
                    return CborValue.UInt64Val(UInt64(n))
                } else {
                    return CborValue.NInt64Val(UInt64(-1 - n))
                }
            case BoolVal(b) => return CborValue.BoolVal(b)
            case DoubleVal(d) => return CborValue.DoubleVal(d)
            case BytesVal(b) => return CborValue.ByteStringVal(b)
            case DateVal(s)  => return CborValue.TextStringVal(s)
            case NullVal     => return CborValue.NullVal
            case MapEntries(entries) =>
                let pairs = ArrayList<(CborValue, CborValue)>()
                for ((k, v) in entries) {
                    pairs.add((CborValue.TextStringVal(k), v.toCbor()))
                }
                return CborValue.MapVal(pairs)
            case ArrayEntries(a) =>
                let items = ArrayList<CborValue>()
                var i: Int64 = 0
                while (i < a.size) {
                    items.add(a[i].toCbor())
                    i++
                }
                return CborValue.ArrayVal(items)
        }
    }

    /**
     * Human-readable string representation.
     * S-018 compliant: no for-in + toString() on Rune.
     */
    public func stringRepr(): String {
        match (this) {
            case StringVal(s)     => return s
            case IntVal(n)        => return n.toString()
            case BoolVal(b)       => return if (b) { "true" } else { "false" }
            case DoubleVal(d)     => return d.toString()
            case BytesVal(b)      => return "<bytes:" + b.size.toString() + ">"
            case DateVal(s)       => return s
            case NullVal          => return ""
            case MapEntries(_)    => return "<map>"
            case ArrayEntries(_)  => return "<array>"
        }
    }

    /** Parse from CborValue (lossless round-trip for supported types). */
    public static func fromCbor(cbor: CborValue): DocDataValue {
        match (cbor) {
            case CborValue.TextStringVal(s) => return StringVal(s)
            case CborValue.UInt64Val(n)     => return IntVal(Int64(n))
            case CborValue.NInt64Val(n)     => return IntVal(-1 - Int64(n))
            case CborValue.BoolVal(b)       => return BoolVal(b)
            case CborValue.DoubleVal(d)     => return DoubleVal(d)
            case CborValue.FloatVal(f)      => return DoubleVal(Float64(f))
            case CborValue.HalfVal(f)       => return DoubleVal(Float64(f))
            case CborValue.ByteStringVal(b) => return BytesVal(b)
            case CborValue.NullVal          => return NullVal
            case CborValue.UndefinedVal     => return NullVal
            case CborValue.MapVal(pairs) =>
                let entries = ArrayList<(String, DocDataValue)>()
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.TextStringVal(ks) =>
                            entries.add((ks, DocDataValue.fromCbor(v)))
                        case _ => ()
                    }
                }
                return MapEntries(entries)
            case CborValue.ArrayVal(items) =>
                let a = ArrayList<DocDataValue>()
                var i: Int64 = 0
                while (i < items.size) {
                    a.add(DocDataValue.fromCbor(items[i]))
                    i++
                }
                return ArrayEntries(a)
            case _ => return NullVal
        }
    }
}

/* ======================================================================
 * DocClaim
 * Mirrors iOS `DocClaim: Equatable, Identifiable`
 * Implements CBOREncodable — toCbor() returns the dataValue's CborValue.
 * ====================================================================== */

/**
 * A single document claim with its typed value and optional child claims.
 * Models a node in the claim tree extracted from an ISO 18013-5 mso_mdoc.
 */
public class DocClaim <: CBOREncodable {
    /** Element identifier / claim name. */
    public let name: String
    /** Full path from document root to this claim. */
    public var path: ArrayList<String>
    /** Localised display name from VCI metadata. */
    public let displayName: ?String
    /** String representation for UI display. */
    public let stringValue: String
    /** Typed value. */
    public let dataValue: DocDataValue
    /** Whether the claim is optional. */
    public var isOptional: Bool
    /** Display order within the namespace. */
    public var order: Int64
    /** UI style hint. */
    public var style: ?String
    /** Namespace (mso_mdoc). */
    public let namespace: ?String
    /** Child claims (nested map/array). */
    public var children: ?ArrayList<DocClaim>

    public init(name: String, path: ArrayList<String>, displayName: ?String,
                dataValue: DocDataValue, stringValue: String,
                isOptional: Bool, order: Int64, namespace: ?String,
                children: ?ArrayList<DocClaim>) {
        this.name = name
        this.path = path
        this.displayName = displayName
        this.dataValue = dataValue
        this.stringValue = stringValue
        this.isOptional = isOptional
        this.order = order
        this.style = None
        this.namespace = namespace
        this.children = children
    }

    /**
     * Stable identifier (mirrors iOS DocClaim.id).
     * Joins non-empty path segments with "."; uses order index for empty ones.
     * S-018 compliant: uses while-index loop, not for-in toString() on Rune.
     */
    public func id(): String {
        let parts = ArrayList<String>()
        var i: Int64 = 0
        while (i < this.path.size) {
            let seg = this.path[i]
            if (seg.isEmpty()) {
                parts.add(this.order.toString())
            } else {
                parts.add(seg)
            }
            i++
        }
        return claimsJoinStrings(parts, ".")
    }

    /** Append a child claim. */
    public func addChild(child: DocClaim): Unit {
        match (this.children) {
            case None =>
                let list = ArrayList<DocClaim>()
                list.add(child)
                this.children = Some(list)
            case Some(list) => list.add(child)
        }
    }

    /**
     * Encode to CBOR (CBOREncodable implementation).
     * Produces the dataValue's CborValue representation for this node.
     */
    public func toCbor(): CborValue {
        return this.dataValue.toCbor()
    }

    /**
     * Build a DocClaim tree from a CBOR value.
     * Recursively decodes nested maps and arrays into child claims.
     *
     * @param name         element identifier (empty string for array elements)
     * @param path         path to this node (list of path components)
     * @param cbor         the CBOR value at this node
     * @param namespace    mso_mdoc namespace string
     * @param order        index within parent container
     * @param displayNames optional HashMap elementId -> localised name
     * @param mandatory    optional HashMap elementId -> is-mandatory flag
     */
    public static func fromCbor(
        name: String,
        path: ArrayList<String>,
        cbor: CborValue,
        namespace: String,
        order: Int64,
        displayNames: ?HashMap<String, String>,
        mandatory: ?HashMap<String, Bool>
    ): DocClaim {
        let dv = DocDataValue.fromCbor(cbor)
        let sv = dv.stringRepr()
        let displayName: ?String = match (displayNames) {
            case Some(m) => m.get(name)
            case None    => None
        }
        let isOptional: Bool = match (mandatory) {
            case Some(m) =>
                match (m.get(name)) {
                    case Some(b) => !b
                    case None    => false
                }
            case None => false
        }
        let node = DocClaim(name, path, displayName, dv, sv,
                            isOptional, order, Some(namespace), None)
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                var childOrder: Int64 = 0
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.TextStringVal(childName) =>
                            let childPath = claimsCopyPath(path)
                            childPath.add(childName)
                            let child = DocClaim.fromCbor(
                                childName, childPath, v, namespace, childOrder,
                                displayNames, mandatory)
                            node.addChild(child)
                            childOrder++
                        case _ => ()
                    }
                }
            case CborValue.ArrayVal(items) =>
                var childOrder: Int64 = 0
                while (childOrder < items.size) {
                    let childPath = claimsCopyPath(path)
                    childPath.add("")
                    let child = DocClaim.fromCbor(
                        "", childPath, items[childOrder], namespace, childOrder,
                        displayNames, mandatory)
                    node.addChild(child)
                    childOrder++
                }
            case _ => ()
        }
        return node
    }
}

/* ======================================================================
 * Package-private helpers (prefix "claims" to avoid name collision)
 * ====================================================================== */

/** Copy an ArrayList<String> into a new instance. */
func claimsCopyPath(src: ArrayList<String>): ArrayList<String> {
    let dst = ArrayList<String>()
    var i: Int64 = 0
    while (i < src.size) {
        dst.add(src[i])
        i++
    }
    return dst
}

/** Join ArrayList<String> with a separator. S-018: no for-in Rune toString. */
func claimsJoinStrings(parts: ArrayList<String>, sep: String): String {
    if (parts.isEmpty()) {
        return ""
    }
    var result = parts[0]
    var i: Int64 = 1
    while (i < parts.size) {
        result = result + sep + parts[i]
        i++
    }
    return result
}

/* ======================================================================
 * DocClaimsDecodable
 * Mirrors iOS `DocClaimsDecodable` protocol (subset for mDoc claims layer).
 * ====================================================================== */

/**
 * Interface for a decoded document that exposes its claims list.
 * Mirrors iOS DocClaimsDecodable protocol.
 * (AgeAttesting / CBOR extraction methods are out of scope for this layer.)
 */
public interface DocClaimsDecodable {
    /** Unique identifier of the document instance. */
    func getId(): String
    /** Document type string (e.g. "org.iso.18013.5.1.mDL"). */
    func getDocType(): String
    /** All claims decoded from the document. */
    func getDocClaims(): ArrayList<DocClaim>
    /** Format of the source credential data. */
    func getDocDataFormat(): DocDataFormat
    /** Display name derived from display metadata. */
    func getDisplayName(): ?String
    /** Display metadata for the document. */
    func getDisplay(): ?ArrayList<DisplayMetadata>
    /** Display metadata for the issuer. */
    func getIssuerDisplay(): ?ArrayList<DisplayMetadata>
}

/* ======================================================================
 * DocClaimsDecodableFactory + Registry
 * Mirrors iOS `DocClaimsDecodableFactory` protocol + registration pattern.
 * ====================================================================== */

/**
 * Factory interface: build a DocClaimsDecodable from CBOR claim data.
 * One implementation is registered per supported docType in the registry.
 */
public interface DocClaimsDecodableFactory {
    /**
     * Build a document from CBOR claim data, or return None if this factory
     * cannot handle the given docType.
     *
     * @param docType   document type string
     * @param claims    namespace -> element_id -> CborValue map
     * @param metadata  optional pre-parsed document metadata
     */
    func make(
        docType: String,
        claims: HashMap<String, HashMap<String, CborValue>>,
        metadata: ?DocMetadata
    ): ?DocClaimsDecodable
}

/**
 * In-process registry for DocClaimsDecodableFactory instances.
 * Dispatches to the correct factory by exact docType string match.
 *
 * Thread-safety: not guaranteed; callers must synchronise registrations
 * before concurrent make() calls.
 */
public class DocClaimsDecodableRegistry {
    private static var factories: HashMap<String, DocClaimsDecodableFactory> =
        HashMap<String, DocClaimsDecodableFactory>()

    /**
     * Register a factory for a docType.
     * Replaces any previously registered factory for the same docType.
     */
    public static func register(docType: String, factory: DocClaimsDecodableFactory): Unit {
        factories.add(docType, factory)
    }

    /** Remove a registered factory. No-op if docType not registered. */
    public static func unregister(docType: String): Unit {
        factories.remove(docType)
    }

    /**
     * Dispatch to the registered factory for docType.
     * Returns None if no factory is registered for that docType.
     */
    public static func make(
        docType: String,
        claims: HashMap<String, HashMap<String, CborValue>>,
        metadata: ?DocMetadata
    ): ?DocClaimsDecodable {
        match (factories.get(docType)) {
            case None         => return None
            case Some(factory) => return factory.make(docType, claims, metadata)
        }
    }

    /** Check whether a factory is registered for a docType. */
    public static func isRegistered(docType: String): Bool {
        return factories.contains(docType)
    }
}
