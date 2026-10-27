/*
 * cose.cj
 *
 * COSE Sign1 container and associated header/algorithm types.
 *
 * ISO 18013-5 embeds IssuerAuth, DeviceAuth and ReaderAuth as *untagged*
 * COSE_Sign1 (a bare 4-element array); the RFC 8152 tag 18 wrapper is reserved
 * for standalone top-level COSE messages and is NOT present on these embedded
 * structures (confirmed by the Annex D test vectors). Use toCbor()/fromCborArray
 * for the embedded form; toTaggedCbor()/fromTaggedCbor exist only for the rare
 * standalone case. This file mirrors the iOS Cose.swift reference implementation
 * using CborValue from eudi_cjcbor as the interchange type.
 *
 * Structure (RFC 8152 §4.2 / COSE_Sign1, embedded = untagged):
 *   COSE_Sign1 =
 *     [ protected   : bstr .cbor header_map,
 *       unprotected : header_map,
 *       payload     : bstr / nil,
 *       signature   : bstr ]
 *
 * iOS references:
 *   Sources/MdocDataModel18013/Cose.swift
 *   Sources/MdocDataModel18013/Extensions.swift
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core

import std.collection.ArrayList
import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.CborTag
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor

/* ------------------------------------------------------------------ */
/* Algorithm identifiers (RFC 8152 Table 1 / Table 7)                 */
/* ------------------------------------------------------------------ */

/**
 * ECDSA verify algorithms as COSE integer values.
 *
 * Note: COSE encodes these as negative integers.
 *   ES256 = -7, ES384 = -35, ES512 = -36
 */
public enum VerifyAlgorithm {
    | Es256    // ECDSA w/ SHA-256, COSE alg value -7
    | Es384    // ECDSA w/ SHA-384, COSE alg value -35
    | Es512    // ECDSA w/ SHA-512, COSE alg value -36

    /** Returns the negative COSE integer value for this algorithm. */
    public func coseValue(): Int64 {
        match (this) {
            case Es256 => return -7
            case Es384 => return -35
            case Es512 => return -36
        }
    }

    /** Try to create from a COSE integer (may be negative). */
    public static func fromCoseValue(n: Int64): ?VerifyAlgorithm {
        match (n) {
            case -7 => return Es256
            case -35 => return Es384
            case -36 => return Es512
            case _ => return None
        }
    }
}

/**
 * HMAC algorithms for COSE_Mac0.
 *   Hmac256 = 5, Hmac384 = 6, Hmac512 = 7
 */
public enum MacAlgorithm {
    | Hmac256   // HMAC w/ SHA-256
    | Hmac384   // HMAC w/ SHA-384
    | Hmac512   // HMAC w/ SHA-512

    public func coseValue(): Int64 {
        match (this) {
            case Hmac256 => return 5
            case Hmac384 => return 6
            case Hmac512 => return 7
        }
    }

    public static func fromCoseValue(n: Int64): ?MacAlgorithm {
        match (n) {
            case 5 => return Hmac256
            case 6 => return Hmac384
            case 7 => return Hmac512
            case _ => return None
        }
    }
}

/* ------------------------------------------------------------------ */
/* CoseHeader                                                          */
/* ------------------------------------------------------------------ */

/**
 * Header field keys per RFC 8152 Table 2.
 *   algorithm = 1,  keyId = 4
 */
public class CoseHeaderKey {
    public static let ALGORITHM: Int64 = 1
    public static let KEY_ID: Int64 = 4
}

/**
 * Parsed representation of a COSE protected or unprotected header.
 *
 * rawHeaderBytes holds the encoded bytes (protected header must preserve these
 * because the signature covers the encoded form, not the decoded map).
 */
public class CoseHeader {
    /** Raw CBOR encoding of this header (needed for Sig_Structure). */
    public let rawHeaderBytes: ?Array<UInt8>
    /** Parsed algorithm identifier (COSE integer, may be negative). */
    public let algorithm: ?Int64
    /** Parsed key identifier bytes. */
    public let keyId: ?Array<UInt8>

    public init(algOpt: ?Int64, kidOpt: ?Array<UInt8>, rawBytes: ?Array<UInt8>) {
        this.algorithm = algOpt
        this.keyId = kidOpt
        this.rawHeaderBytes = rawBytes
    }

    /**
     * Build a CoseHeader for a given algorithm, encoding the header map as CBOR.
     *
     * When isNegativeAlg is true (Sign1), the algorithm is encoded as a CBOR
     * negative integer; when false (Mac0), as an unsigned integer.
     */
    public static func build(algValue: Int64, isNegativeAlg: Bool, kidOpt: ?Array<UInt8>): CoseHeader {
        let pairs = ArrayList<(CborValue, CborValue)>()
        let algKey = CborValue.UInt64Val(UInt64(CoseHeaderKey.ALGORITHM))
        let algVal: CborValue = if (isNegativeAlg) {
            // Negative COSE integer: for algorithm value a (e.g. -7), NInt64Val stores n = -1 - a
            CborValue.NInt64Val(UInt64(-1 - algValue))
        } else {
            CborValue.UInt64Val(UInt64(algValue))
        }
        pairs.add((algKey, algVal))
        match (kidOpt) {
            case Some(kid) =>
                let kidKey = CborValue.UInt64Val(UInt64(CoseHeaderKey.KEY_ID))
                pairs.add((kidKey, CborValue.ByteStringVal(kid)))
            case None => ()
        }
        let headerMap = CborValue.MapVal(pairs)
        let encodedBytes = headerMap.encode()
        return CoseHeader(algValue, kidOpt, encodedBytes)
    }

    /**
     * Decode a CoseHeader from a ByteStringVal (the protected header is a bstr
     * containing an encoded map).
     * Returns None if the bytestring is empty or cannot be decoded.
     */
    public static func fromBytestring(cbor: CborValue): ?CoseHeader {
        match (cbor) {
            case CborValue.ByteStringVal(bytes) =>
                if (bytes.size == 0) {
                    return None
                }
                let rawBytes: Array<UInt8> = bytes
                let map: CborValue
                try {
                    map = decodeCbor(bytes)
                } catch (_: Exception) {
                    return None
                }
                match (map) {
                    case CborValue.MapVal(pairs) =>
                        var algOpt: ?Int64 = None
                        var kidOpt: ?Array<UInt8> = None
                        for ((k, v) in pairs) {
                            match (k) {
                                case CborValue.UInt64Val(kn) =>
                                    if (kn == UInt64(CoseHeaderKey.ALGORITHM)) {
                                        match (v) {
                                            case CborValue.UInt64Val(n) =>
                                                algOpt = Int64(n)
                                            case CborValue.NInt64Val(n) =>
                                                algOpt = -1 - Int64(n)
                                            case _ => ()
                                        }
                                    } else if (kn == UInt64(CoseHeaderKey.KEY_ID)) {
                                        match (v) {
                                            case CborValue.ByteStringVal(kid) =>
                                                kidOpt = kid
                                            case _ => ()
                                        }
                                    }
                                case _ => ()
                            }
                        }
                        return CoseHeader(algOpt, kidOpt, rawBytes)
                    case _ => return None
                }
            case _ => return None
        }
    }

    /**
     * Decode a CoseHeader from a MapVal (the unprotected header is a direct
     * CBOR map, not a bstr-wrapped map).
     *
     * RFC 8152 §4.2: unprotected header is `header_map` (not bstr).
     * We encode the map back to bytes and store them in rawHeaderBytes so that
     * downstream callers using `uph.rawHeaderBytes` then `decodeCbor(rawBytes)`
     * can recover the original map.
     *
     * Returns None if cbor is not a MapVal.
     */
    public static func fromMap(cbor: CborValue): ?CoseHeader {
        match (cbor) {
            case CborValue.MapVal(pairs) =>
                let rawBytes = cbor.encode()
                var algOpt: ?Int64 = None
                var kidOpt: ?Array<UInt8> = None
                for ((k, v) in pairs) {
                    match (k) {
                        case CborValue.UInt64Val(kn) =>
                            if (kn == UInt64(CoseHeaderKey.ALGORITHM)) {
                                match (v) {
                                    case CborValue.UInt64Val(n) =>
                                        algOpt = Int64(n)
                                    case CborValue.NInt64Val(n) =>
                                        algOpt = -1 - Int64(n)
                                    case _ => ()
                                }
                            } else if (kn == UInt64(CoseHeaderKey.KEY_ID)) {
                                match (v) {
                                    case CborValue.ByteStringVal(kid) =>
                                        kidOpt = kid
                                    case _ => ()
                                }
                            }
                        case _ => ()
                    }
                }
                return CoseHeader(algOpt, kidOpt, rawBytes)
            case _ => return None
        }
    }

    /**
     * Return this header wrapped as a ByteStringVal for use in the protected
     * position of a COSE array.
     */
    public func toProtectedCbor(): CborValue {
        match (rawHeaderBytes) {
            case Some(b) => return CborValue.ByteStringVal(b)
            case None =>
                let emptyPairs = ArrayList<(CborValue, CborValue)>()
                return CborValue.ByteStringVal(CborValue.MapVal(emptyPairs).encode())
        }
    }

    /**
     * Return this header as a MapVal for use in the unprotected position.
     */
    public func toUnprotectedCbor(): CborValue {
        match (rawHeaderBytes) {
            case Some(bytes) =>
                try {
                    return decodeCbor(bytes)
                } catch (_: Exception) {
                    let emptyPairs = ArrayList<(CborValue, CborValue)>()
                    return CborValue.MapVal(emptyPairs)
                }
            case None =>
                let emptyPairs = ArrayList<(CborValue, CborValue)>()
                return CborValue.MapVal(emptyPairs)
        }
    }
}

/* ------------------------------------------------------------------ */
/* CoseSign1 — COSE_Sign1 container                                   */
/* ------------------------------------------------------------------ */

/**
 * COSE_Sign1 container as used throughout ISO 18013-5.
 *
 * Wire encoding (RFC 8152 §4.2):
 *   COSE_Sign1 = [
 *     protected   : bstr .cbor header_map,
 *     unprotected : header_map,
 *     payload     : bstr / nil,
 *     signature   : bstr
 *   ]
 *
 * The whole structure is tagged with CborTag.COSE_SIGN1 (18) when serialised.
 */
public class CoseSign1 <: CBOREncodable {
    public let protectedHeader: CoseHeader
    public let unprotectedHeader: ?CoseHeader
    /** Payload bytes (None = detached payload). */
    public let payload: ?Array<UInt8>
    public let signature: Array<UInt8>

    public init(ph: CoseHeader, uph: ?CoseHeader, pld: ?Array<UInt8>, sig: Array<UInt8>) {
        this.protectedHeader = ph
        this.unprotectedHeader = uph
        this.payload = pld
        this.signature = sig
    }

    /**
     * Convenience constructor: build a CoseSign1 with a given algorithm and optional payload.
     * Mirrors iOS init(type:algorithm:payloadData:unprotectedHeaderCbor:signature:).
     */
    public static func create(
        algValue: Int64,
        payloadBytes: ?Array<UInt8>,
        unprotectedHeaderCbor: ?CborValue,
        signature: Array<UInt8>
    ): CoseSign1 {
        let ph = CoseHeader.build(algValue, true, None)
        let uph: ?CoseHeader = match (unprotectedHeaderCbor) {
            case Some(cbor) =>
                let encoded = cbor.encode()
                Some(CoseHeader(None, None, encoded))
            case None => None
        }
        return CoseSign1(ph, uph, payloadBytes, signature)
    }

    /**
     * Decode from a CBOR array (4 elements) as read from the wire.
     * Returns None if the array has fewer than 4 elements or the protected
     * header cannot be parsed.
     */
    public static func fromCborArray(arr: CborValue): ?CoseSign1 {
        match (arr) {
            case CborValue.ArrayVal(items) =>
                if (items.size < 4) {
                    return None
                }
                let phOpt = CoseHeader.fromBytestring(items[0])
                match (phOpt) {
                    case None => return None
                    case Some(ph) =>
                        // RFC 8152 §4.2: unprotected header is a direct CBOR map (not bstr).
                        let uphOpt = CoseHeader.fromMap(items[1])
                        let payloadOpt: ?Array<UInt8> = match (items[2]) {
                            case CborValue.ByteStringVal(b) => Some(b)
                            case _ => None
                        }
                        let sigBytes: Array<UInt8> = match (items[3]) {
                            case CborValue.ByteStringVal(b) => b
                            case _ => Array<UInt8>()
                        }
                        return Some(CoseSign1(ph, uphOpt, payloadOpt, sigBytes))
                }
            case _ => return None
        }
    }

    /**
     * Decode from a tag-18 wrapped CborValue.
     * Returns None if the tag is wrong or the inner structure is invalid.
     */
    public static func fromTaggedCbor(tagged: CborValue): ?CoseSign1 {
        match (tagged) {
            case CborValue.TaggedVal(t, inner) =>
                if (t != CborTag.COSE_SIGN1) {
                    return None
                }
                return CoseSign1.fromCborArray(inner)
            case _ => return None
        }
    }

    /**
     * Encode to a 4-element CBOR array (without outer tag 18).
     * Implements CBOREncodable.toCbor().
     */
    public func toCbor(): CborValue {
        let items = ArrayList<CborValue>()
        items.add(protectedHeader.toProtectedCbor())
        match (unprotectedHeader) {
            case Some(uph) => items.add(uph.toUnprotectedCbor())
            case None =>
                let emptyPairs = ArrayList<(CborValue, CborValue)>()
                items.add(CborValue.MapVal(emptyPairs))
        }
        match (payload) {
            case Some(bytes) => items.add(CborValue.ByteStringVal(bytes))
            case None => items.add(CborValue.NullVal)
        }
        items.add(CborValue.ByteStringVal(signature))
        return CborValue.ArrayVal(items)
    }

    /**
     * Encode to CBOR bytes with tag 18 (COSE_SIGN1) wrapper.
     * This is the canonical wire form used in ISO 18013-5.
     */
    public func toTaggedCbor(): CborValue {
        return CborValue.TaggedVal(CborTag.COSE_SIGN1, this.toCbor())
    }

    /**
     * Build the Sig_Structure bytes used as input to ECDSA sign/verify.
     *
     * Sig_Structure = [
     *   context        : "Signature1",
     *   body_protected : bstr .cbor header_map,
     *   external_aad   : bstr (empty),
     *   payload        : bstr
     * ]
     *
     * Returns None if the protected header bytes are missing or the payload
     * is detached.
     */
    public func sigStructureBytes(): ?Array<UInt8> {
        let phBytes: Array<UInt8> = match (protectedHeader.rawHeaderBytes) {
            case Some(b) => b
            case None => return None
        }
        let payloadBytes: Array<UInt8> = match (payload) {
            case Some(b) => b
            case None => return None
        }
        let parts = ArrayList<CborValue>()
        parts.add(CborValue.TextStringVal("Signature1"))
        parts.add(CborValue.ByteStringVal(phBytes))
        parts.add(CborValue.ByteStringVal(Array<UInt8>()))  // empty external AAD
        parts.add(CborValue.ByteStringVal(payloadBytes))
        return CborValue.ArrayVal(parts).encode()
    }
}
