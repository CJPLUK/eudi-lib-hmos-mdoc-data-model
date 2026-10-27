/*
 * secure_area.cj
 *
 * SecureArea / SecureKeyStorage interfaces, SecureAreaRegistry singleton,
 * and supporting configuration types for ISO 18013-5 key management.
 *
 * Thread-safety contract:
 *   In iOS, SecureArea and SecureKeyStorage are declared as Swift Actors,
 *   giving implicit serial-executor isolation. In Cangjie (no Actor keyword),
 *   **implementors are responsible for managing their own thread safety**.
 *   This contract is documented here rather than enforced by the type system.
 *
 * Async → Sync mapping:
 *   All iOS `async throws` methods are mapped to synchronous `throws` methods.
 *   Callers that need non-blocking behaviour must dispatch to a worker thread.
 *
 * CoseEcCurve note:
 *   The mdoc.engagement package defines a minimal CoseEcCurve (P256/P384/P521)
 *   for device-engagement use.  This package defines the **full IANA COSE
 *   registry superset** (including brainpool, Ed25519, X25519, …).
 *   Type unification across packages is a supervisor-level decision;
 *   until then the two enums coexist in separate Cangjie packages.
 *
 * iOS references:
 *   Sources/MdocDataModel18013/SecureArea/SecureArea.swift
 *   Sources/MdocDataModel18013/SecureArea/SecureKeyStorage.swift
 *   Sources/MdocDataModel18013/SecureArea/SecureAreaRegistry.swift
 *   Sources/MdocDataModel18013/SecureArea/KeyOptions.swift
 *   Sources/MdocDataModel18013/SecureArea/CredentialOptions.swift
 *   Sources/MdocDataModel18013/SecureArea/CredentialPolicy.swift
 *   Sources/MdocDataModel18013/SecureArea/CredentialsUsageCounts.swift
 *   Sources/MdocDataModel18013/SecureArea/DocKeyInfo.swift
 *   Sources/MdocDataModel18013/SecureArea/KeyBatchInfo.swift
 *   Sources/MdocDataModel18013/SecureArea/SecureAreaError.swift
 *   Sources/MdocDataModel18013/SecureArea/CoseEcCurve.swift
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea

import std.collection.HashMap
import std.collection.ArrayList
import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor

/* ==================================================================== */
/* SecureAreaError                                                       */
/* ==================================================================== */

/**
 * Generic error thrown by SecureArea / SecureKeyStorage operations.
 * Mirrors iOS SecureAreaError (LocalizedError struct) as a Cangjie Exception.
 *
 * Note: `message` is already a property of the base Exception class;
 * the error description is accessible via Exception.message inherited field.
 */
public class SecureAreaError <: Exception {
    public init(msg: String) {
        super(msg)
    }
}

/* ==================================================================== */
/* CoseEcCurve — full IANA COSE registry set                            */
/* ==================================================================== */

/**
 * Elliptic curve identifiers from the IANA COSE registry
 * (https://www.iana.org/assignments/cose/cose.xhtml).
 *
 * This is the full superset used by SecureArea.  The minimal three-curve
 * variant in mdoc.engagement covers only ISO 18013-5 device-engagement.
 *
 * COSE raw values:
 *   P256=1, P384=2, P521=3, X25519=4, X448=5, ED25519=6, ED448=7,
 *   BRAINPOOLP256R1=256, BRAINPOOLP320R1=257, BRAINPOOLP384R1=258, BRAINPOOLP512R1=259
 */
public enum CoseEcCurve {
    | P256           // COSE 1
    | P384           // COSE 2
    | P521           // COSE 3
    | X25519         // COSE 4  (ECDH only)
    | X448           // COSE 5  (ECDH only)
    | ED25519        // COSE 6  (EdDSA only)
    | ED448          // COSE 7  (EdDSA only)
    | BRAINPOOLP256R1  // COSE 256
    | BRAINPOOLP320R1  // COSE 257
    | BRAINPOOLP384R1  // COSE 258
    | BRAINPOOLP512R1  // COSE 259

    /** COSE integer encoding of this curve. */
    public func rawValue(): UInt64 {
        match (this) {
            case P256 => return UInt64(1)
            case P384 => return UInt64(2)
            case P521 => return UInt64(3)
            case X25519 => return UInt64(4)
            case X448 => return UInt64(5)
            case ED25519 => return UInt64(6)
            case ED448 => return UInt64(7)
            case BRAINPOOLP256R1 => return UInt64(256)
            case BRAINPOOLP320R1 => return UInt64(257)
            case BRAINPOOLP384R1 => return UInt64(258)
            case BRAINPOOLP512R1 => return UInt64(259)
        }
    }

    /** Construct from a COSE integer. Throws SecureAreaError if unknown. */
    public static func fromRaw(raw: UInt64): CoseEcCurve {
        match (raw) {
            case 1 => return P256
            case 2 => return P384
            case 3 => return P521
            case 4 => return X25519
            case 5 => return X448
            case 6 => return ED25519
            case 7 => return ED448
            case 256 => return BRAINPOOLP256R1
            case 257 => return BRAINPOOLP320R1
            case 258 => return BRAINPOOLP384R1
            case 259 => return BRAINPOOLP512R1
            case _ => throw SecureAreaError("No curve with COSE identifier " + raw.toString())
        }
    }

    /** JWK curve name for this curve. */
    public func jwkName(): String {
        match (this) {
            case P256 => return "P-256"
            case P384 => return "P-384"
            case P521 => return "P-521"
            case ED25519 => return "Ed25519"
            case ED448 => return "Ed448"
            case X25519 => return "X25519"
            case X448 => return "X448"
            case BRAINPOOLP256R1 => return "brainpoolP256r1"
            case BRAINPOOLP320R1 => return "brainpoolP320r1"
            case BRAINPOOLP384R1 => return "brainpoolP384r1"
            case BRAINPOOLP512R1 => return "brainpoolP512r1"
        }
    }

    /** Construct from a JWK curve name string. Throws SecureAreaError if unknown. */
    public static func fromJwkName(name: String): CoseEcCurve {
        match (name) {
            case "P-256" => return P256
            case "P-384" => return P384
            case "P-521" => return P521
            case "Ed25519" => return ED25519
            case "Ed448" => return ED448
            case "X25519" => return X25519
            case "X448" => return X448
            case "brainpoolP256r1" => return BRAINPOOLP256R1
            case "brainpoolP320r1" => return BRAINPOOLP320R1
            case "brainpoolP384r1" => return BRAINPOOLP384R1
            case "brainpoolP512r1" => return BRAINPOOLP512R1
            case _ => throw SecureAreaError("No EcCurve value for " + name)
        }
    }

    /** Curve size in bits. */
    public func bitSize(): Int64 {
        match (this) {
            case P256 | BRAINPOOLP256R1 | X25519 | ED25519 => return 256
            case P384 | BRAINPOOLP384R1 => return 384
            case P521 => return 521
            case BRAINPOOLP320R1 => return 320
            case BRAINPOOLP512R1 => return 512
            case X448 | ED448 => return 448
        }
    }

    /** SECG name for this curve. */
    public func secgName(): String {
        match (this) {
            case P256 => return "secp256r1"
            case P384 => return "secp384r1"
            case P521 => return "secp521r1"
            case BRAINPOOLP256R1 => return "brainpoolP256r1"
            case BRAINPOOLP320R1 => return "brainpoolP320r1"
            case BRAINPOOLP384R1 => return "brainpoolP384r1"
            case BRAINPOOLP512R1 => return "brainpoolP512r1"
            case X25519 => return "x25519"
            case ED25519 => return "ed25519"
            case X448 => return "x448"
            case ED448 => return "ed448"
        }
    }

    /** Default signing algorithm for this curve. */
    public func defaultSigningAlgorithm(): SigningAlgorithm {
        match (this) {
            case P256 | BRAINPOOLP256R1 | BRAINPOOLP320R1 => return SigningAlgorithm.ES256
            case P384 | BRAINPOOLP384R1 => return SigningAlgorithm.ES384
            case P521 | BRAINPOOLP512R1 => return SigningAlgorithm.ES512
            case ED25519 | ED448 => return SigningAlgorithm.EDDSA
            case X25519 | X448 => return SigningAlgorithm.UNSET
        }
    }
}

/* ==================================================================== */
/* SigningAlgorithm                                                      */
/* ==================================================================== */

/**
 * Signing algorithms used with COSE key operations.
 * Mirrors iOS SigningAlgorithm enum.
 */
public enum SigningAlgorithm {
    | ES256
    | ES384
    | ES512
    | EDDSA
    | UNSET

    /** Relative ordering for algorithm strength comparison. */
    public func order(): Int64 {
        match (this) {
            case UNSET => return 0
            case ES256 => return 1
            case ES384 => return 2
            case ES512 => return 3
            case EDDSA => return 4
        }
    }
}

/* ==================================================================== */
/* KeyPurpose                                                            */
/* ==================================================================== */

/**
 * Tasks for which a key can be used.
 * Mirrors iOS KeyPurpose enum.
 */
public enum KeyPurpose {
    | Signing
    | KeyAgreement

    /** String encoding for serialization. */
    public func rawValue(): String {
        match (this) {
            case Signing => return "Signing"
            case KeyAgreement => return "Key Agreement"
        }
    }

    /** Decode from string. Throws SecureAreaError if unrecognized. */
    public static func fromRaw(raw: String): KeyPurpose {
        match (raw) {
            case "Signing" => return Signing
            case "Key Agreement" => return KeyAgreement
            case _ => throw SecureAreaError("Unknown KeyPurpose: " + raw)
        }
    }

    /** All cases — mirrors Swift CaseIterable. */
    public static func allCases(): Array<KeyPurpose> {
        return [Signing, KeyAgreement]
    }
}

/* ==================================================================== */
/* KeyAccessProtection                                                   */
/* ==================================================================== */

/**
 * Key access protection options controlling when a key is accessible.
 * Mirrors iOS KeyAccessProtection enum (kSecAttrAccessible variants).
 * On non-Apple platforms the raw integer is used for serialization only.
 */
public enum KeyAccessProtection {
    | WhenUnlocked                  // 0
    | AfterFirstUnlock              // 1
    | WhenUnlockedThisDeviceOnly    // 2
    | AfterFirstUnlockThisDeviceOnly // 3
    | WhenPasscodeSetThisDeviceOnly // 4

    /** Integer encoding for serialization. */
    public func rawValue(): Int64 {
        match (this) {
            case WhenUnlocked => return 0
            case AfterFirstUnlock => return 1
            case WhenUnlockedThisDeviceOnly => return 2
            case AfterFirstUnlockThisDeviceOnly => return 3
            case WhenPasscodeSetThisDeviceOnly => return 4
        }
    }

    /** Decode from integer. Throws SecureAreaError if unrecognized. */
    public static func fromRaw(raw: Int64): KeyAccessProtection {
        match (raw) {
            case 0 => return WhenUnlocked
            case 1 => return AfterFirstUnlock
            case 2 => return WhenUnlockedThisDeviceOnly
            case 3 => return AfterFirstUnlockThisDeviceOnly
            case 4 => return WhenPasscodeSetThisDeviceOnly
            case _ => throw SecureAreaError("Unknown KeyAccessProtection: " + raw.toString())
        }
    }
}

/* ==================================================================== */
/* KeyAccessControl                                                      */
/* ==================================================================== */

/**
 * Bitfield of access control requirements.
 * Mirrors iOS KeyAccessControl OptionSet.
 *
 * BIT 0 (1): requireUserPresence   — biometry or passcode
 * BIT 1 (2): requireApplicationPassword — app-provided password
 */
public class KeyAccessControl {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        this.rawValue = rawValue
    }

    public static let requireUserPresence: KeyAccessControl = KeyAccessControl(1)
    public static let requireApplicationPassword: KeyAccessControl = KeyAccessControl(2)

    /** Test if a flag is set. */
    public func contains(flag: KeyAccessControl): Bool {
        return (this.rawValue & flag.rawValue) != 0
    }

    /** Combine two access controls. */
    public func union(other: KeyAccessControl): KeyAccessControl {
        return KeyAccessControl(this.rawValue | other.rawValue)
    }
}

/* ==================================================================== */
/* KeyOptions                                                            */
/* ==================================================================== */

/**
 * Options for creating a key pair.
 * Mirrors iOS KeyOptions struct (Codable).
 */
public class KeyOptions {
    /** Elliptic curve to use. Default: P256. */
    public var curve: CoseEcCurve
    /** Name of the SecureArea to use (None = default). */
    public var secureAreaName: ?String
    /** Access protection (None = platform default). */
    public var accessProtection: ?KeyAccessProtection
    /** Access control bitfield (None = no extra control). */
    public var accessControl: ?KeyAccessControl
    /** Key purposes (None = all purposes). */
    public var keyPurposes: ?Array<KeyPurpose>
    /** Additional opaque options bytes. */
    public var additionalOptions: ?Array<UInt8>

    public init(
        curve: CoseEcCurve,
        secureAreaName: ?String,
        accessProtection: ?KeyAccessProtection,
        accessControl: ?KeyAccessControl,
        keyPurposes: ?Array<KeyPurpose>,
        additionalOptions: ?Array<UInt8>
    ) {
        this.curve = curve
        this.secureAreaName = secureAreaName
        this.accessProtection = accessProtection
        this.accessControl = accessControl
        this.keyPurposes = keyPurposes
        this.additionalOptions = additionalOptions
    }

    /** Convenience constructor with defaults (curve=P256, all other fields=None). */
    public static func defaults(): KeyOptions {
        return KeyOptions(
            CoseEcCurve.P256,
            None,
            None,
            None,
            Some(KeyPurpose.allCases()),
            None
        )
    }

    /**
     * Encode to CborValue for lossless serialization.
     *
     * CBOR map layout:
     *   0 -> UInt64 (curve rawValue)
     *   1 -> TextString (secureAreaName) or absent
     *   2 -> Int64 (accessProtection rawValue) or absent
     *   3 -> Int64 (accessControl rawValue) or absent
     *   4 -> Array of TextString (keyPurposes) or absent
     *   5 -> ByteString (additionalOptions) or absent
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.UInt64Val(UInt64(0)), CborValue.UInt64Val(this.curve.rawValue())))
        match (this.secureAreaName) {
            case Some(n) =>
                pairs.add((CborValue.UInt64Val(UInt64(1)), CborValue.TextStringVal(n)))
            case None => ()
        }
        match (this.accessProtection) {
            case Some(ap) =>
                pairs.add((CborValue.UInt64Val(UInt64(2)), CborValue.UInt64Val(UInt64(ap.rawValue()))))
            case None => ()
        }
        match (this.accessControl) {
            case Some(ac) =>
                pairs.add((CborValue.UInt64Val(UInt64(3)), CborValue.UInt64Val(UInt64(ac.rawValue))))
            case None => ()
        }
        match (this.keyPurposes) {
            case Some(purposes) =>
                let arr = ArrayList<CborValue>()
                for (p in purposes) {
                    arr.add(CborValue.TextStringVal(p.rawValue()))
                }
                pairs.add((CborValue.UInt64Val(UInt64(4)), CborValue.ArrayVal(arr)))
            case None => ()
        }
        match (this.additionalOptions) {
            case Some(bytes) =>
                pairs.add((CborValue.UInt64Val(UInt64(5)), CborValue.ByteStringVal(bytes)))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    /** Decode from CborValue. Throws SecureAreaError on malformed input. */
    public static func fromCbor(cbor: CborValue): KeyOptions {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                var curve: CoseEcCurve = CoseEcCurve.P256
                var secureAreaName: ?String = None
                var accessProtection: ?KeyAccessProtection = None
                var accessControl: ?KeyAccessControl = None
                var keyPurposes: ?Array<KeyPurpose> = None
                var additionalOptions: ?Array<UInt8> = None
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.UInt64Val(kn) =>
                            match (kn) {
                                case 0 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) => curve = CoseEcCurve.fromRaw(n)
                                        case _ => ()
                                    }
                                case 1 =>
                                    match (v) {
                                        case CborValue.TextStringVal(s) => secureAreaName = Some(s)
                                        case _ => ()
                                    }
                                case 2 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) =>
                                            accessProtection = Some(KeyAccessProtection.fromRaw(Int64(n)))
                                        case _ => ()
                                    }
                                case 3 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) =>
                                            accessControl = Some(KeyAccessControl(Int64(n)))
                                        case _ => ()
                                    }
                                case 4 =>
                                    match (v) {
                                        case CborValue.ArrayVal(items) =>
                                            let arr = ArrayList<KeyPurpose>()
                                            for (item in items) {
                                                match (item) {
                                                    case CborValue.TextStringVal(s) =>
                                                        arr.add(KeyPurpose.fromRaw(s))
                                                    case _ => ()
                                                }
                                            }
                                            keyPurposes = Some(arr.toArray())
                                        case _ => ()
                                    }
                                case 5 =>
                                    match (v) {
                                        case CborValue.ByteStringVal(bytes) =>
                                            additionalOptions = Some(bytes)
                                        case _ => ()
                                    }
                                case _ => ()
                            }
                        case _ => ()
                    }
                }
                return KeyOptions(curve, secureAreaName, accessProtection, accessControl, keyPurposes, additionalOptions)
            case _ => throw SecureAreaError("KeyOptions.fromCbor: expected MapVal")
        }
    }

    /** Encode to bytes. */
    public func toBytes(): Array<UInt8> {
        return this.toCbor().encode()
    }

    /** Decode from bytes. Throws SecureAreaError on malformed input. */
    public static func fromBytes(bytes: Array<UInt8>): KeyOptions {
        let cbor = decodeCbor(bytes)
        return KeyOptions.fromCbor(cbor)
    }
}

/* ==================================================================== */
/* CredentialPolicy                                                      */
/* ==================================================================== */

/**
 * Policy governing how credentials can be used across presentations.
 * Mirrors iOS CredentialPolicy enum.
 */
public enum CredentialPolicy {
    /** Delete credential after a single use. */
    | OneTimeUse
    /** Rotate by tracking usage count across the batch. */
    | RotateUse

    /** String encoding for serialization. */
    public func rawValue(): String {
        match (this) {
            case OneTimeUse => return "oneTimeUse"
            case RotateUse => return "rotateUse"
        }
    }

    /** Decode from string. Throws SecureAreaError if unrecognized. */
    public static func fromRaw(raw: String): CredentialPolicy {
        match (raw) {
            case "oneTimeUse" => return OneTimeUse
            case "rotateUse" => return RotateUse
            case _ => throw SecureAreaError("Unknown CredentialPolicy: " + raw)
        }
    }
}

/* ==================================================================== */
/* CredentialOptions                                                     */
/* ==================================================================== */

/**
 * Options for creating a credential batch.
 * Mirrors iOS CredentialOptions struct (Codable).
 */
public class CredentialOptions {
    /** Policy for how credentials in the batch may be used. */
    public var credentialPolicy: CredentialPolicy
    /** Number of keys in the batch. */
    public var batchSize: Int64

    public init(credentialPolicy: CredentialPolicy, batchSize: Int64) {
        this.credentialPolicy = credentialPolicy
        this.batchSize = batchSize
    }

    /**
     * Encode to CborValue.
     *
     * CBOR map:
     *   0 -> TextString (credentialPolicy rawValue)
     *   1 -> UInt64 (batchSize)
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.UInt64Val(UInt64(0)), CborValue.TextStringVal(this.credentialPolicy.rawValue())))
        pairs.add((CborValue.UInt64Val(UInt64(1)), CborValue.UInt64Val(UInt64(this.batchSize))))
        return CborValue.MapVal(pairs)
    }

    /** Decode from CborValue. Throws SecureAreaError on malformed input. */
    public static func fromCbor(cbor: CborValue): CredentialOptions {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                var policy: CredentialPolicy = CredentialPolicy.OneTimeUse
                var batchSize: Int64 = 0
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.UInt64Val(kn) =>
                            match (kn) {
                                case 0 =>
                                    match (v) {
                                        case CborValue.TextStringVal(s) =>
                                            policy = CredentialPolicy.fromRaw(s)
                                        case _ => ()
                                    }
                                case 1 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) =>
                                            batchSize = Int64(n)
                                        case _ => ()
                                    }
                                case _ => ()
                            }
                        case _ => ()
                    }
                }
                return CredentialOptions(policy, batchSize)
            case _ => throw SecureAreaError("CredentialOptions.fromCbor: expected MapVal")
        }
    }

    /** Encode to bytes. */
    public func toBytes(): Array<UInt8> {
        return this.toCbor().encode()
    }

    /** Decode from bytes. */
    public static func fromBytes(bytes: Array<UInt8>): CredentialOptions {
        let cbor = decodeCbor(bytes)
        return CredentialOptions.fromCbor(cbor)
    }
}

/* ==================================================================== */
/* CredentialsUsageCounts                                               */
/* ==================================================================== */

/**
 * Counters for total and remaining credentials.
 * Mirrors iOS CredentialsUsageCounts struct (Codable, Hashable).
 */
public class CredentialsUsageCounts {
    public let total: Int64
    public let remaining: Int64

    /** Derived: number of credentials already used. */
    public func used(): Int64 {
        return this.total - this.remaining
    }

    public init(total: Int64, remaining: Int64) {
        if (total < remaining) {
            throw SecureAreaError("Total count cannot be less than remaining count")
        }
        this.total = total
        this.remaining = remaining
    }

    /**
     * Encode to CborValue.
     *
     * CBOR map:
     *   0 -> UInt64 (total)
     *   1 -> UInt64 (remaining)
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.UInt64Val(UInt64(0)), CborValue.UInt64Val(UInt64(this.total))))
        pairs.add((CborValue.UInt64Val(UInt64(1)), CborValue.UInt64Val(UInt64(this.remaining))))
        return CborValue.MapVal(pairs)
    }

    /** Decode from CborValue. */
    public static func fromCbor(cbor: CborValue): CredentialsUsageCounts {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                var total: Int64 = 0
                var remaining: Int64 = 0
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.UInt64Val(kn) =>
                            match (kn) {
                                case 0 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) => total = Int64(n)
                                        case _ => ()
                                    }
                                case 1 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) => remaining = Int64(n)
                                        case _ => ()
                                    }
                                case _ => ()
                            }
                        case _ => ()
                    }
                }
                return CredentialsUsageCounts(total, remaining)
            case _ => throw SecureAreaError("CredentialsUsageCounts.fromCbor: expected MapVal")
        }
    }

    /** Encode to bytes. */
    public func toBytes(): Array<UInt8> {
        return this.toCbor().encode()
    }

    /** Decode from bytes. */
    public static func fromBytes(bytes: Array<UInt8>): CredentialsUsageCounts {
        let cbor = decodeCbor(bytes)
        return CredentialsUsageCounts.fromCbor(cbor)
    }
}

/* ==================================================================== */
/* KeyAttestation                                                        */
/* ==================================================================== */

/**
 * Attestation for a single key, carrying the public key and X.509 chain.
 * Mirrors iOS KeyAttestation struct (Codable).
 *
 * Note: publicKeyX / publicKeyY carry the raw EC point bytes (not a CoseKey
 * reference), to avoid a cross-package dependency on mdoc.engagement.CoseKey.
 */
public class KeyAttestation {
    /** Raw X-coordinate bytes of the public key. */
    public let publicKeyX: Array<UInt8>
    /** Raw Y-coordinate bytes of the public key. */
    public let publicKeyY: Array<UInt8>
    /** Curve of the attested key. */
    public let curve: CoseEcCurve
    /** Optional chain of base64-encoded DER X.509 certificates. */
    public let attestationChain: ?Array<String>

    public init(publicKeyX: Array<UInt8>, publicKeyY: Array<UInt8>, curve: CoseEcCurve, attestationChain: ?Array<String>) {
        this.publicKeyX = publicKeyX
        this.publicKeyY = publicKeyY
        this.curve = curve
        this.attestationChain = attestationChain
    }

    /**
     * Encode to CborValue.
     *
     * CBOR map:
     *   0 -> ByteString (publicKeyX)
     *   1 -> ByteString (publicKeyY)
     *   2 -> UInt64 (curve rawValue)
     *   3 -> Array<TextString> (attestationChain) or absent
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.UInt64Val(UInt64(0)), CborValue.ByteStringVal(this.publicKeyX)))
        pairs.add((CborValue.UInt64Val(UInt64(1)), CborValue.ByteStringVal(this.publicKeyY)))
        pairs.add((CborValue.UInt64Val(UInt64(2)), CborValue.UInt64Val(this.curve.rawValue())))
        match (this.attestationChain) {
            case Some(chain) =>
                let arr = ArrayList<CborValue>()
                for (cert in chain) {
                    arr.add(CborValue.TextStringVal(cert))
                }
                pairs.add((CborValue.UInt64Val(UInt64(3)), CborValue.ArrayVal(arr)))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    /** Decode from CborValue. Throws SecureAreaError on malformed input. */
    public static func fromCbor(cbor: CborValue): KeyAttestation {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                var keyX: Array<UInt8> = []
                var keyY: Array<UInt8> = []
                var curve: CoseEcCurve = CoseEcCurve.P256
                var chain: ?Array<String> = None
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.UInt64Val(kn) =>
                            match (kn) {
                                case 0 =>
                                    match (v) {
                                        case CborValue.ByteStringVal(b) => keyX = b
                                        case _ => ()
                                    }
                                case 1 =>
                                    match (v) {
                                        case CborValue.ByteStringVal(b) => keyY = b
                                        case _ => ()
                                    }
                                case 2 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) => curve = CoseEcCurve.fromRaw(n)
                                        case _ => ()
                                    }
                                case 3 =>
                                    match (v) {
                                        case CborValue.ArrayVal(items) =>
                                            let arr = ArrayList<String>()
                                            for (item in items) {
                                                match (item) {
                                                    case CborValue.TextStringVal(s) => arr.add(s)
                                                    case _ => ()
                                                }
                                            }
                                            chain = Some(arr.toArray())
                                        case _ => ()
                                    }
                                case _ => ()
                            }
                        case _ => ()
                    }
                }
                return KeyAttestation(keyX, keyY, curve, chain)
            case _ => throw SecureAreaError("KeyAttestation.fromCbor: expected MapVal")
        }
    }
}

/* ==================================================================== */
/* KeyBatchInfo                                                          */
/* ==================================================================== */

/**
 * Metadata about a batch of keys created by SecureArea.createKeyBatch.
 * Mirrors iOS KeyBatchInfo struct (Codable).
 */
public class KeyBatchInfo {
    /** Secure area that owns these keys (None = default). */
    public let secureAreaName: ?String
    /** Elliptic curve of all keys in the batch. */
    public var crv: CoseEcCurve
    /** Per-key usage counters (length == batchSize). */
    public var usedCounts: Array<Int64>
    /** Credential lifecycle policy for this batch. */
    public let credentialPolicy: CredentialPolicy
    /** Purposes this key batch serves. */
    public var keyPurpose: ?Array<KeyPurpose>
    /** Optional attestation for the batch. */
    public var attestation: ?KeyAttestation

    public init(
        secureAreaName: ?String,
        crv: CoseEcCurve,
        usedCounts: Array<Int64>,
        credentialPolicy: CredentialPolicy,
        keyPurpose: ?Array<KeyPurpose>,
        attestation: ?KeyAttestation
    ) {
        this.secureAreaName = secureAreaName
        this.crv = crv
        this.usedCounts = usedCounts
        this.credentialPolicy = credentialPolicy
        this.keyPurpose = keyPurpose
        this.attestation = attestation
    }

    /** Derived: number of keys in this batch. */
    public func batchSize(): Int64 {
        return Int64(this.usedCounts.size)
    }

    /**
     * Build an updated KeyBatchInfo after using key at keyIndex.
     * Mirrors iOS KeyBatchInfo.init(previous:keyIndex:).
     */
    public static func afterUse(previous: KeyBatchInfo, keyIndex: Int64): KeyBatchInfo {
        let newCounts = Array<Int64>(previous.usedCounts.size, {i => previous.usedCounts[i]})
        newCounts[keyIndex] = previous.usedCounts[keyIndex] + 1
        return KeyBatchInfo(
            previous.secureAreaName,
            previous.crv,
            newCounts,
            previous.credentialPolicy,
            previous.keyPurpose,
            previous.attestation
        )
    }

    /**
     * Find the index of the key to use next.
     * Returns None if no usable key (one-time-use policy and all counts > 0).
     * Mirrors iOS KeyBatchInfo.findIndexToUse().
     */
    public func findIndexToUse(): ?Int64 {
        if (this.usedCounts.size == 0) {
            return None
        }
        var minVal: Int64 = this.usedCounts[0]
        var minIdx: Int64 = 0
        var i: Int64 = 1
        while (i < this.usedCounts.size) {
            if (this.usedCounts[i] < minVal) {
                minVal = this.usedCounts[i]
                minIdx = i
            }
            i++
        }
        match (this.credentialPolicy) {
            case CredentialPolicy.OneTimeUse =>
                if (minVal > 0) {
                    return None
                }
            case CredentialPolicy.RotateUse => ()
        }
        return Some(minIdx)
    }

    /**
     * Encode to CborValue.
     *
     * CBOR map:
     *   0 -> TextString (secureAreaName) or absent
     *   1 -> UInt64 (crv rawValue)
     *   2 -> Array<UInt64> (usedCounts)
     *   3 -> TextString (credentialPolicy rawValue)
     *   4 -> Array<TextString> (keyPurpose rawValues) or absent
     *   5 -> ByteString (encoded attestation) or absent
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        match (this.secureAreaName) {
            case Some(n) =>
                pairs.add((CborValue.UInt64Val(UInt64(0)), CborValue.TextStringVal(n)))
            case None => ()
        }
        pairs.add((CborValue.UInt64Val(UInt64(1)), CborValue.UInt64Val(this.crv.rawValue())))
        let countsArr = ArrayList<CborValue>()
        for (c in this.usedCounts) {
            countsArr.add(CborValue.UInt64Val(UInt64(c)))
        }
        pairs.add((CborValue.UInt64Val(UInt64(2)), CborValue.ArrayVal(countsArr)))
        pairs.add((CborValue.UInt64Val(UInt64(3)), CborValue.TextStringVal(this.credentialPolicy.rawValue())))
        match (this.keyPurpose) {
            case Some(purposes) =>
                let arr = ArrayList<CborValue>()
                for (p in purposes) {
                    arr.add(CborValue.TextStringVal(p.rawValue()))
                }
                pairs.add((CborValue.UInt64Val(UInt64(4)), CborValue.ArrayVal(arr)))
            case None => ()
        }
        match (this.attestation) {
            case Some(att) =>
                pairs.add((CborValue.UInt64Val(UInt64(5)), CborValue.ByteStringVal(att.toCbor().encode())))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    /** Decode from CborValue. Throws SecureAreaError on malformed input. */
    public static func fromCbor(cbor: CborValue): KeyBatchInfo {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                var secureAreaName: ?String = None
                var crv: CoseEcCurve = CoseEcCurve.P256
                var usedCounts: Array<Int64> = []
                var credentialPolicy: CredentialPolicy = CredentialPolicy.OneTimeUse
                var keyPurpose: ?Array<KeyPurpose> = None
                var attestation: ?KeyAttestation = None
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.UInt64Val(kn) =>
                            match (kn) {
                                case 0 =>
                                    match (v) {
                                        case CborValue.TextStringVal(s) => secureAreaName = Some(s)
                                        case _ => ()
                                    }
                                case 1 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) => crv = CoseEcCurve.fromRaw(n)
                                        case _ => ()
                                    }
                                case 2 =>
                                    match (v) {
                                        case CborValue.ArrayVal(items) =>
                                            let arr = ArrayList<Int64>()
                                            for (item in items) {
                                                match (item) {
                                                    case CborValue.UInt64Val(n) => arr.add(Int64(n))
                                                    case _ => ()
                                                }
                                            }
                                            usedCounts = arr.toArray()
                                        case _ => ()
                                    }
                                case 3 =>
                                    match (v) {
                                        case CborValue.TextStringVal(s) =>
                                            credentialPolicy = CredentialPolicy.fromRaw(s)
                                        case _ => ()
                                    }
                                case 4 =>
                                    match (v) {
                                        case CborValue.ArrayVal(items) =>
                                            let arr = ArrayList<KeyPurpose>()
                                            for (item in items) {
                                                match (item) {
                                                    case CborValue.TextStringVal(s) =>
                                                        arr.add(KeyPurpose.fromRaw(s))
                                                    case _ => ()
                                                }
                                            }
                                            keyPurpose = Some(arr.toArray())
                                        case _ => ()
                                    }
                                case 5 =>
                                    match (v) {
                                        case CborValue.ByteStringVal(bytes) =>
                                            let attCbor = decodeCbor(bytes)
                                            attestation = Some(KeyAttestation.fromCbor(attCbor))
                                        case _ => ()
                                    }
                                case _ => ()
                            }
                        case _ => ()
                    }
                }
                return KeyBatchInfo(secureAreaName, crv, usedCounts, credentialPolicy, keyPurpose, attestation)
            case _ => throw SecureAreaError("KeyBatchInfo.fromCbor: expected MapVal")
        }
    }

    /** Encode to bytes. */
    public func toBytes(): Array<UInt8> {
        return this.toCbor().encode()
    }

    /** Decode from bytes. Throws SecureAreaError on malformed input. */
    public static func fromBytes(bytes: Array<UInt8>): KeyBatchInfo {
        let cbor = decodeCbor(bytes)
        return KeyBatchInfo.fromCbor(cbor)
    }
}

/* ==================================================================== */
/* DocKeyInfo                                                            */
/* ==================================================================== */

/**
 * Compact descriptor for a document's key configuration.
 * Mirrors iOS DocKeyInfo struct (Codable).
 */
public class DocKeyInfo {
    public let secureAreaName: ?String
    public var batchSize: Int64
    public let credentialPolicy: CredentialPolicy
    /** DER-encoded holder proof private keys (one per batch credential) for
     *  credentials bound to in-memory issuance proof keys rather than a
     *  SecureArea batch — required to sign DeviceAuth / KB-JWT at
     *  presentation time. Absent for legacy / SecureArea-bound documents. */
    public var proofKeyDers: ?Array<Array<UInt8>>

    public init(secureAreaName: ?String, batchSize: Int64, credentialPolicy: CredentialPolicy) {
        this.secureAreaName = secureAreaName
        this.batchSize = batchSize
        this.credentialPolicy = credentialPolicy
        this.proofKeyDers = None
    }

    /**
     * Encode to CborValue.
     *
     * CBOR map:
     *   0 -> TextString (secureAreaName) or absent
     *   1 -> UInt64 (batchSize)
     *   2 -> TextString (credentialPolicy rawValue)
     */
    public func toCbor(): CborValue {
        let pairs = ArrayList<(CborValue, CborValue)>()
        match (this.secureAreaName) {
            case Some(n) =>
                pairs.add((CborValue.UInt64Val(UInt64(0)), CborValue.TextStringVal(n)))
            case None => ()
        }
        pairs.add((CborValue.UInt64Val(UInt64(1)), CborValue.UInt64Val(UInt64(this.batchSize))))
        pairs.add((CborValue.UInt64Val(UInt64(2)), CborValue.TextStringVal(this.credentialPolicy.rawValue())))
        match (this.proofKeyDers) {
            case Some(ders) =>
                let items = ArrayList<CborValue>()
                for (d in ders) { items.add(CborValue.ByteStringVal(d)) }
                pairs.add((CborValue.UInt64Val(UInt64(3)), CborValue.ArrayVal(items)))
            case None => ()
        }
        return CborValue.MapVal(pairs)
    }

    /** Decode from CborValue. Throws SecureAreaError on malformed input. */
    public static func fromCbor(cbor: CborValue): DocKeyInfo {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                var secureAreaName: ?String = None
                var batchSize: Int64 = 0
                var credentialPolicy: CredentialPolicy = CredentialPolicy.OneTimeUse
                var proofKeyDers: ?Array<Array<UInt8>> = None
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.UInt64Val(kn) =>
                            match (kn) {
                                case 0 =>
                                    match (v) {
                                        case CborValue.TextStringVal(s) => secureAreaName = Some(s)
                                        case _ => ()
                                    }
                                case 1 =>
                                    match (v) {
                                        case CborValue.UInt64Val(n) => batchSize = Int64(n)
                                        case _ => ()
                                    }
                                case 2 =>
                                    match (v) {
                                        case CborValue.TextStringVal(s) =>
                                            credentialPolicy = CredentialPolicy.fromRaw(s)
                                        case _ => ()
                                    }
                                case 3 =>
                                    match (v) {
                                        case CborValue.ArrayVal(items) =>
                                            let ders = ArrayList<Array<UInt8>>()
                                            for (item in items) {
                                                match (item) {
                                                    case CborValue.ByteStringVal(b) => ders.add(b)
                                                    case _ => ()
                                                }
                                            }
                                            proofKeyDers = Some(ders.toArray())
                                        case _ => ()
                                    }
                                case _ => ()
                            }
                        case _ => ()
                    }
                }
                let info = DocKeyInfo(secureAreaName, batchSize, credentialPolicy)
                info.proofKeyDers = proofKeyDers
                return info
            case _ => throw SecureAreaError("DocKeyInfo.fromCbor: expected MapVal")
        }
    }

    /** Encode to bytes. */
    public func toBytes(): Array<UInt8> {
        return this.toCbor().encode()
    }

    /** Decode from bytes. */
    public static func fromBytes(bytes: Array<UInt8>): DocKeyInfo {
        let cbor = decodeCbor(bytes)
        return DocKeyInfo.fromCbor(cbor)
    }
}

/* ==================================================================== */
/* SecureKeyStorage interface                                            */
/* ==================================================================== */

/**
 * Protocol for secure key storage backends.
 *
 * Thread-safety contract:
 *   iOS declares this as an Actor. In Cangjie, **implementors must manage
 *   their own thread safety** (e.g. via mutex / monitor).
 *   Callers must not assume any particular executor.
 *
 * Mirrors iOS SecureKeyStorage protocol (Actor).
 */
public interface SecureKeyStorage {
    /** Read public key metadata for the given id. */
    func readKeyInfo(id: String): HashMap<String, Array<UInt8>>

    /** Read sensitive key material at the given index (may require biometric). */
    func readKeyData(id: String, index: Int64): HashMap<String, Array<UInt8>>

    /** Persist public key metadata. */
    func writeKeyInfo(id: String, dict: HashMap<String, Array<UInt8>>): Unit

    /** Persist a batch of key data entries starting at startIndex. */
    func writeKeyDataBatch(id: String, startIndex: Int64, dicts: Array<HashMap<String, Array<UInt8>>>, keyOptions: ?KeyOptions): Unit

    /** Delete key data for the given batch slice. */
    func deleteKeyBatch(id: String, startIndex: Int64, batchSize: Int64): Unit

    /** Delete key metadata. */
    func deleteKeyInfo(id: String): Unit
}

/* ==================================================================== */
/* SecureArea interface                                                  */
/* ==================================================================== */

/**
 * Abstraction of a secure area for performing cryptographic key operations.
 *
 * Thread-safety contract:
 *   iOS declares this as an Actor. In Cangjie, **implementors must manage
 *   their own thread safety**. Callers on multiple threads must synchronize
 *   externally if needed, or the implementation must serialize internally.
 *
 * Note: This feature provides **protocol and configuration types only**.
 * No concrete key implementation is provided here; hardware-backed
 * implementations (e.g. HUKS) are delivered in the wallet-kit phase.
 *
 * Async → Sync mapping:
 *   All iOS `async throws` methods map to synchronous `throws`.
 *
 * Mirrors iOS SecureArea protocol (Actor).
 */
public interface SecureArea {
    /** Human-readable name used for registry lookup. */
    func getName(): String

    /** Default EC curve for this secure area. */
    func getDefaultEcCurve(): CoseEcCurve

    /** EC curves supported by this secure area. */
    func getSupportedEcCurves(): Array<CoseEcCurve>

    /** Return the underlying key storage instance. */
    func getStorage(): SecureKeyStorage

    /**
     * Create a batch of key pairs and return batch metadata.
     * Mirrors iOS createKeyBatch(id:credentialOptions:keyOptions:) -> [CoseKey].
     */
    func createKeyBatch(id: String, credentialOptions: CredentialOptions, keyOptions: ?KeyOptions): KeyBatchInfo

    /**
     * Retrieve public key material at a specific batch index.
     * Returns a CBOR-encoded CoseKey (raw bytes).
     */
    func getPublicKeyBytes(id: String, index: Int64, curve: CoseEcCurve): Array<UInt8>

    /**
     * Unlock the key and return unlock data (may be None for hardware keys).
     * Mirrors iOS unlockKey(id:) -> Data?.
     */
    func unlockKey(id: String): ?Array<UInt8>

    /** Delete a slice of a key batch. */
    func deleteKeyBatch(id: String, startIndex: Int64, batchSize: Int64): Unit

    /** Delete key metadata. */
    func deleteKeyInfo(id: String): Unit

    /**
     * Compute a signature over dataToSign.
     * Returns raw signature bytes.
     * Mirrors iOS signature(id:index:algorithm:dataToSign:unlockData:) -> Data.
     */
    func signature(id: String, index: Int64, algorithm: SigningAlgorithm, dataToSign: Array<UInt8>, unlockData: ?Array<UInt8>): Array<UInt8>

    /**
     * Compute ECDH shared secret with the given remote public key bytes.
     * Returns raw shared secret bytes.
     * Mirrors iOS keyAgreement(id:index:publicKey:unlockData:) -> SharedSecret.
     */
    func keyAgreement(id: String, index: Int64, publicKeyBytes: Array<UInt8>, unlockData: ?Array<UInt8>): Array<UInt8>

    /** Retrieve key batch metadata. */
    func getKeyBatchInfo(id: String): KeyBatchInfo

    /** Default signing algorithm for the given curve. */
    func defaultSigningAlgorithm(ecCurve: CoseEcCurve): SigningAlgorithm
}

/* ==================================================================== */
/* SecureAreaRegistry — singleton registry                              */
/* ==================================================================== */

/**
 * Singleton registry for SecureArea implementations.
 *
 * Thread-safety:
 *   The registry holds a mutable HashMap protected by a simple flag-based
 *   approach.  Production callers should register all SecureArea instances
 *   during app startup (before concurrent access begins).
 *   In Cangjie there is no NSLock; implementors needing strict concurrency
 *   must wrap calls in their own synchronization.
 *
 * Mirrors iOS SecureAreaRegistry class (@unchecked Sendable).
 */
public class SecureAreaRegistry {

    /** Well-known device secure area names (mirrors iOS DeviceSecureArea enum). */
    public static let DEVICE_NAME_SECURE_ENCLAVE: String = "SecureEnclave"
    public static let DEVICE_NAME_SOFTWARE: String = "Software"

    /** The application-wide singleton. */
    public static let shared: SecureAreaRegistry = SecureAreaRegistry()

    private var secureAreas: HashMap<String, SecureArea>

    private init() {
        this.secureAreas = HashMap<String, SecureArea>()
    }

    /**
     * Register a SecureArea implementation.
     * The registry key is the value returned by secureArea.getName().
     */
    public func register(secureArea: SecureArea): Unit {
        this.secureAreas[secureArea.getName()] = secureArea
    }

    /**
     * Retrieve a SecureArea by name.
     * Returns the default (SecureEnclave > Software > first registered) if
     * name is None or the named area is not found.
     * Throws SecureAreaError if the registry is empty.
     */
    public func get(name: ?String): SecureArea {
        match (name) {
            case Some(n) =>
                if (this.secureAreas.contains(n)) {
                    return this.secureAreas[n]
                } else {
                    return this.defaultSecurityArea()
                }
            case None => return this.defaultSecurityArea()
        }
    }

    /**
     * Retrieve a well-known device secure area by its constant name.
     * Returns None if no such area has been registered.
     */
    public func getByDeviceName(deviceName: String): ?SecureArea {
        if (this.secureAreas.contains(deviceName)) {
            return Some(this.secureAreas[deviceName])
        } else {
            return None
        }
    }

    /** Names of all registered secure areas. */
    public func names(): Array<String> {
        let result = ArrayList<String>()
        for ((k, _) in this.secureAreas) {
            result.add(k)
        }
        return result.toArray()
    }

    /** All registered SecureArea instances. */
    public func values(): Array<SecureArea> {
        let result = ArrayList<SecureArea>()
        for ((_, v) in this.secureAreas) {
            result.add(v)
        }
        return result.toArray()
    }

    /**
     * Unregister the SecureArea with the given name.
     * No-op if the name is not registered.
     */
    public func unregister(name: String): Unit {
        this.secureAreas.remove(name)
    }

    /**
     * The preferred default: SecureEnclave > Software > first registered.
     * Throws SecureAreaError if no area is registered.
     */
    public func defaultSecurityArea(): SecureArea {
        if (this.secureAreas.contains(SecureAreaRegistry.DEVICE_NAME_SECURE_ENCLAVE)) {
            return this.secureAreas[SecureAreaRegistry.DEVICE_NAME_SECURE_ENCLAVE]
        }
        if (this.secureAreas.contains(SecureAreaRegistry.DEVICE_NAME_SOFTWARE)) {
            return this.secureAreas[SecureAreaRegistry.DEVICE_NAME_SOFTWARE]
        }
        for ((_, v) in this.secureAreas) {
            return v
        }
        throw SecureAreaError("SecureAreaRegistry: no SecureArea registered")
    }
}
