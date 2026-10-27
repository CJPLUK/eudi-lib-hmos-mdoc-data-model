/*
 * zk_system.cj
 *
 * Zero-Knowledge Proof system model for ISO 18013-5 mDoc.
 *
 * Covers: ZkParam enum, ZkParams ordered list, ZkSystemSpec class,
 *         ZkSystemProtocol interface, ZkSystemRepository class.
 *
 * iOS references:
 *   Sources/MdocDataModel18013/Zkp/ZkParams.swift
 *   Sources/MdocDataModel18013/Zkp/ZkSystemSpec.swift
 *   Sources/MdocDataModel18013/Zkp/ZkSystemProtocol.swift
 *   Sources/MdocDataModel18013/Zkp/ZkSystemRepository.swift
 *
 * Cangjie notes:
 *   - iOS OrderedDictionary<String, ZkParam> -> ArrayList<(String, ZkParam)>
 *     (preserves insertion order; no ordered-dict in std.collection)
 *   - iOS ZkSystemProtocol -> Cangjie interface ZkSystemProtocol
 *   - R-102: no static let inside enum body
 *   - R-101: init named params need ! prefix
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.zkp

import std.collection.ArrayList
import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CBOREncodable
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MdocValidationError
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MdocValidationErrorKind

// ---------------------------------------------------------------------------
// ZkSystem — tstr alias (mirrors iOS `public type ZkSystem = String`)
// ---------------------------------------------------------------------------
public type ZkSystem = String

// ---------------------------------------------------------------------------
// ZkParam — mirrors iOS enum ZkParam: CBORDecodable, CBOREncodable
// ---------------------------------------------------------------------------

/**
 * A single zero-knowledge parameter value.
 * Encodes / decodes as a primitive CBOR item (uint/double/bool/text).
 *
 * Note: Cangjie enums cannot extend Exception or classes (R-100).
 *       No static let inside enum body (R-102).
 */
public enum ZkParam {
    | IntParam(Int64)
    | DoubleParam(Float64)
    | BoolParam(Bool)
    | StringParam(String)

    /**
     * Decode from a CborValue.
     * Mirrors iOS ZkParam.init(cbor:).
     */
    public static func fromCbor(cbor: CborValue): ZkParam {
        match (cbor) {
            case CborValue.UInt64Val(v) =>
                return IntParam(Int64(v))
            case CborValue.NInt64Val(n) =>
                // CBOR negative: actual value = -1 - n
                return IntParam(-1 - Int64(n))
            case CborValue.DoubleVal(v) =>
                return DoubleParam(v)
            case CborValue.FloatVal(v) =>
                return DoubleParam(Float64(v))
            case CborValue.BoolVal(v) =>
                return BoolParam(v)
            case CborValue.TextStringVal(v) =>
                return StringParam(v)
            case _ =>
                throw MdocValidationError(MdocValidationErrorKind.InvalidCbor("ZkParam"))
        }
    }

    /**
     * Encode to a CborValue.
     * Mirrors iOS ZkParam.toCBOR(options:).
     */
    public func toCbor(): CborValue {
        match (this) {
            case IntParam(v) =>
                if (v >= 0) {
                    return CborValue.UInt64Val(UInt64(v))
                } else {
                    // negative: CBOR NInt64Val stores n where value = -1 - n
                    return CborValue.NInt64Val(UInt64(-1 - v))
                }
            case DoubleParam(v) =>
                return CborValue.DoubleVal(v)
            case BoolParam(v) =>
                return CborValue.BoolVal(v)
            case StringParam(v) =>
                return CborValue.TextStringVal(v)
        }
    }

    /** Convenience accessor. Returns Some(v) if IntParam, else None. */
    public func intValue(): ?Int64 {
        match (this) {
            case IntParam(v) => return Some(v)
            case _ => return None
        }
    }

    /** Convenience accessor. Returns Some(v) if DoubleParam, else None. */
    public func doubleValue(): ?Float64 {
        match (this) {
            case DoubleParam(v) => return Some(v)
            case _ => return None
        }
    }

    /** Convenience accessor. Returns Some(v) if BoolParam, else None. */
    public func boolValue(): ?Bool {
        match (this) {
            case BoolParam(v) => return Some(v)
            case _ => return None
        }
    }

    /** Convenience accessor. Returns Some(v) if StringParam, else None. */
    public func stringValue(): ?String {
        match (this) {
            case StringParam(v) => return Some(v)
            case _ => return None
        }
    }
}

// ---------------------------------------------------------------------------
// ZkParams — ordered list of (key, ZkParam) pairs
// Mirrors iOS `public typealias ZkParams = OrderedDictionary<String, ZkParam>`
// Cangjie has no OrderedDictionary in std; ArrayList<(String, ZkParam)> preserves insertion order.
// ---------------------------------------------------------------------------
public type ZkParams = ArrayList<(String, ZkParam)>

// ---------------------------------------------------------------------------
// ZkSystemSpec — mirrors iOS struct ZkSystemSpec: CBORDecodable, CBOREncodable
// ---------------------------------------------------------------------------

/**
 * Specification of a zero-knowledge system.
 *
 * CBOR map structure:
 *   "system"     : text   — ZKP system identifier
 *   "zkSystemId" : text   — optional explicit ID (falls back to system value)
 *   "params"     : map    — per-system parameters
 *   (other keys are stored as extensions)
 */
public class ZkSystemSpec <: CBOREncodable {
    /** Unique ZKP system identifier (key "zkSystemId" or falls back to "system" value). */
    public let zkSystemId: String
    /** ZKP system name (key "system"). */
    public let system: ZkSystem
    /** System parameters (key "params"). */
    public let params: ZkParams
    /** Extension entries: keys not in {system, zkSystemId, params}. */
    public let extensions: ArrayList<(String, CborValue)>

    public init(
        zkSystemId_: String,
        system_: ZkSystem,
        params_: ZkParams,
        extensions_: ArrayList<(String, CborValue)>
    ) {
        this.zkSystemId = zkSystemId_
        this.system = system_
        this.params = params_
        this.extensions = extensions_
    }

    /**
     * Decode from a CborValue (CBOR map).
     * Mirrors iOS ZkSystemSpec.init(cbor:) throws.
     */
    public static func fromCbor(cbor: CborValue): ZkSystemSpec {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                var systemVal: ?String = None
                var zkSystemIdVal: ?String = None
                let paramsResult: ZkParams = ArrayList<(String, ZkParam)>()
                let exts: ArrayList<(String, CborValue)> = ArrayList<(String, CborValue)>()

                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.TextStringVal(keyStr) =>
                            if (keyStr == "system") {
                                match (v) {
                                    case CborValue.TextStringVal(s) => systemVal = Some(s)
                                    case _ =>
                                        throw MdocValidationError(MdocValidationErrorKind.InvalidCbor("ZkSystemSpec system"))
                                }
                            } else if (keyStr == "zkSystemId") {
                                match (v) {
                                    case CborValue.TextStringVal(s) => zkSystemIdVal = Some(s)
                                    case _ =>
                                        throw MdocValidationError(MdocValidationErrorKind.InvalidCbor("ZkSystemSpec zkSystemId"))
                                }
                            } else if (keyStr == "params") {
                                match (v) {
                                    case CborValue.MapVal(paramPairs) =>
                                        for ((pk, pv) in paramPairs) {
                                            match (pk) {
                                                case CborValue.TextStringVal(pKey) =>
                                                    paramsResult.add((pKey, ZkParam.fromCbor(pv)))
                                                case _ =>
                                                    throw MdocValidationError(MdocValidationErrorKind.InvalidCbor("ZkSystemSpec params key"))
                                            }
                                        }
                                    case _ =>
                                        throw MdocValidationError(MdocValidationErrorKind.InvalidCbor("ZkSystemSpec params"))
                                }
                            } else {
                                exts.add((keyStr, v))
                            }
                        case _ =>
                            throw MdocValidationError(MdocValidationErrorKind.InvalidCbor("ZkSystemSpec key type"))
                    }
                }

                let sys: String = match (systemVal) {
                    case Some(s) => s
                    case None =>
                        throw MdocValidationError(MdocValidationErrorKind.MissingField("ZkSystemSpec", "system"))
                }
                let zkId: String = match (zkSystemIdVal) {
                    case Some(s) => s
                    case None => sys
                }

                return ZkSystemSpec(zkId, sys, paramsResult, exts)
            case _ =>
                throw MdocValidationError(MdocValidationErrorKind.InvalidCbor("ZkSystemSpec"))
        }
    }

    /**
     * Encode to a CborValue (CBOR map).
     * Mirrors iOS ZkSystemSpec.toCBOR(options:).
     * Key order: system, zkSystemId (when distinct from system), params, then extensions.
     *
     * HI-MDOC-003 fix: zkSystemId was previously omitted when zkSystemId != system,
     * causing the field to be lost on round-trip. It is now serialized whenever it
     * differs from system, matching fromCbor's "zkSystemId" key read path.
     */
    public func toCbor(): CborValue {
        let pairs: ArrayList<(CborValue, CborValue)> = ArrayList<(CborValue, CborValue)>()

        // "system" key
        pairs.add((CborValue.TextStringVal("system"), CborValue.TextStringVal(this.system)))

        // "zkSystemId" key — only emit when it carries distinct information
        if (this.zkSystemId != this.system) {
            pairs.add((CborValue.TextStringVal("zkSystemId"), CborValue.TextStringVal(this.zkSystemId)))
        }

        // "params" key — encode as CBOR map
        let paramPairs: ArrayList<(CborValue, CborValue)> = ArrayList<(CborValue, CborValue)>()
        for ((pKey, pVal) in this.params) {
            paramPairs.add((CborValue.TextStringVal(pKey), pVal.toCbor()))
        }
        pairs.add((CborValue.TextStringVal("params"), CborValue.MapVal(paramPairs)))

        // extensions
        for ((extKey, extVal) in this.extensions) {
            pairs.add((CborValue.TextStringVal(extKey), extVal))
        }

        return CborValue.MapVal(pairs)
    }

    /**
     * Convenience: encode to raw CBOR bytes.
     */
    public func encode(): Array<UInt8> {
        return this.toCbor().encode()
    }

    /**
     * Decode from raw CBOR bytes.
     */
    public static func decode(bytes: Array<UInt8>): ZkSystemSpec {
        return ZkSystemSpec.fromCbor(decodeCbor(bytes))
    }
}

// ---------------------------------------------------------------------------
// ZkSystemProtocol — mirrors iOS protocol ZkSystemProtocol
// ---------------------------------------------------------------------------

/**
 * Interface representing a Zero-Knowledge Proof system.
 * Mirrors iOS ZkSystemProtocol (Swift protocol → Cangjie interface).
 */
public interface ZkSystemProtocol {
    /** The unique name identifying this ZK system implementation. */
    prop name: String

    /** All ZkSystemSpecs supported by this ZK system. */
    prop systemSpecs: ArrayList<ZkSystemSpec>
}

// ---------------------------------------------------------------------------
// ZkSystemRepository — mirrors iOS struct ZkSystemRepository
// ---------------------------------------------------------------------------

/**
 * A mutable repository of ZkSystemProtocol implementations.
 * Mirrors iOS ZkSystemRepository.
 *
 * Usage:
 *   var repo = ZkSystemRepository()
 *   repo.add(myZkSystem)
 *   let found = repo.lookup("my-system")
 */
public class ZkSystemRepository {
    private var systems: ArrayList<ZkSystemProtocol>

    /** Construct an empty repository. */
    public init() {
        this.systems = ArrayList<ZkSystemProtocol>()
    }

    /** Construct a repository pre-populated with given systems. */
    public static func ofSystems(initialSystems: ArrayList<ZkSystemProtocol>): ZkSystemRepository {
        let repo = ZkSystemRepository()
        for (s in initialSystems) {
            repo.add(s)
        }
        return repo
    }

    /**
     * Register a new ZkSystemProtocol implementation.
     * Mirrors iOS ZkSystemRepository.add(_:).
     */
    public func add(system: ZkSystemProtocol): Unit {
        this.systems.add(system)
    }

    /**
     * Look up a registered ZkSystemProtocol by name.
     * Returns None if not found.
     * Mirrors iOS ZkSystemRepository.lookup(_:).
     */
    public func lookup(zkSystemName: String): ?ZkSystemProtocol {
        var i = 0
        while (i < this.systems.size) {
            if (this.systems[i].name == zkSystemName) {
                return Some(this.systems[i])
            }
            i++
        }
        return None
    }

    /**
     * Returns all ZkSystemSpecs from every registered ZkSystem.
     * Mirrors iOS ZkSystemRepository.getAllZkSystemSpecs().
     */
    public func getAllZkSystemSpecs(): ArrayList<ZkSystemSpec> {
        let result: ArrayList<ZkSystemSpec> = ArrayList<ZkSystemSpec>()
        for (sys in this.systems) {
            for (spec in sys.systemSpecs) {
                result.add(spec)
            }
        }
        return result
    }

    /** Number of registered systems. */
    public func size(): Int64 {
        return this.systems.size
    }
}
