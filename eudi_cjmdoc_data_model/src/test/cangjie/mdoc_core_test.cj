/*
 * mdoc_core_test.cj
 *
 * Unit tests for mdoc_core feature:
 *   1. CBOREncodable / CBORDecodable round-trip (done_when 1)
 *   2. CoseSign1 CBOR round-trip, ISO 18013-5 structure (done_when 2)
 *   3. Base64UrlHelper and MdocValidationError (done_when 3)
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model_local_test

import std.unittest.*
import std.unittest.testmacro.*

import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.CborTag
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CBOREncodable
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.encodeToCbor
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.decodeFromCborBytes
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CoseSign1
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CoseHeader
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.CoseHeaderKey
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.VerifyAlgorithm
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MacAlgorithm
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MdocValidationError
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.MdocValidationErrorKind
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.Base64UrlHelper

import std.collection.ArrayList

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

func bytesEqual(a: Array<UInt8>, b: Array<UInt8>): Bool {
    if (a.size != b.size) {
        return false
    }
    var i = 0
    while (i < a.size) {
        if (a[i] != b[i]) {
            return false
        }
        i++
    }
    return true
}

/* A minimal CBOREncodable for testing: wraps a TextString. */
class SimpleText <: CBOREncodable {
    let value: String
    public init(v: String) {
        value = v
    }
    public func toCbor(): CborValue {
        return CborValue.TextStringVal(value)
    }
}

/* ------------------------------------------------------------------ */
/* Test 1 — CBOREncodable / CBORDecodable round-trip (done_when 1)    */
/* ------------------------------------------------------------------ */

@Test
public class CborCodableTest {

    @TestCase
    func textStringRoundTrip(): Unit {
        let original = SimpleText("hello mDoc")
        let bytes = encodeToCbor(original)
        let decoded = decodeFromCborBytes(bytes)
        match (decoded) {
            case CborValue.TextStringVal(s) =>
                @Assert(s, "hello mDoc")
            case _ =>
                @Assert(false)
        }
    }

    @TestCase
    func byteStringRoundTrip(): Unit {
        let payload: Array<UInt8> = [0x01, 0x02, 0x03, 0xFF]
        let cbor = CborValue.ByteStringVal(payload)
        let bytes = cbor.encode()
        let back = decodeFromCborBytes(bytes)
        match (back) {
            case CborValue.ByteStringVal(b) =>
                @Assert(bytesEqual(b, payload))
            case _ =>
                @Assert(false)
        }
    }

    @TestCase
    func mapRoundTrip(): Unit {
        let pairs = ArrayList<(CborValue, CborValue)>()
        pairs.add((CborValue.TextStringVal("key"), CborValue.UInt64Val(42)))
        let mapVal = CborValue.MapVal(pairs)
        let bytes = mapVal.encode()
        let back = decodeFromCborBytes(bytes)
        let fieldOpt = back.field(CborValue.TextStringVal("key"))
        match (fieldOpt) {
            case Some(CborValue.UInt64Val(n)) =>
                @Assert(n, UInt64(42))
            case _ =>
                @Assert(false)
        }
    }
}

/* ------------------------------------------------------------------ */
/* Test 2 — CoseSign1 round-trip, ISO 18013-5 structure (done_when 2) */
/* ------------------------------------------------------------------ */

@Test
public class CoseSign1Test {

    @TestCase
    func roundTripUntagged(): Unit {
        let payloadBytes: Array<UInt8> = [0xDE, 0xAD, 0xBE, 0xEF]
        let sigBytes: Array<UInt8> = [0x01, 0x02, 0x03]
        let cose = CoseSign1.create(
            VerifyAlgorithm.Es256.coseValue(),
            payloadBytes,
            None,
            sigBytes
        )
        let cbor = cose.toCbor()
        let decoded = CoseSign1.fromCborArray(cbor)
        match (decoded) {
            case Some(d) =>
                match (d.payload) {
                    case Some(b) => @Assert(bytesEqual(b, payloadBytes))
                    case None => @Assert(false)
                }
                @Assert(bytesEqual(d.signature, sigBytes))
            case None =>
                @Assert(false)
        }
    }

    @TestCase
    func roundTripTagged(): Unit {
        let payloadBytes: Array<UInt8> = [0xCA, 0xFE]
        let sigBytes: Array<UInt8> = [0xBA, 0xBE, 0x00, 0x01]
        let cose = CoseSign1.create(
            VerifyAlgorithm.Es256.coseValue(),
            payloadBytes,
            None,
            sigBytes
        )
        let tagged = cose.toTaggedCbor()
        match (tagged) {
            case CborValue.TaggedVal(t, _) =>
                @Assert(t, CborTag.COSE_SIGN1)
            case _ =>
                @Assert(false)
        }
        let decoded = CoseSign1.fromTaggedCbor(tagged)
        match (decoded) {
            case Some(d) =>
                match (d.payload) {
                    case Some(b) => @Assert(bytesEqual(b, payloadBytes))
                    case None => @Assert(false)
                }
                @Assert(bytesEqual(d.signature, sigBytes))
            case None =>
                @Assert(false)
        }
    }

    @TestCase
    func sigStructureBytesIsSignature1(): Unit {
        let payloadBytes: Array<UInt8> = [0x01]
        let sigBytes: Array<UInt8> = []
        let cose = CoseSign1.create(
            VerifyAlgorithm.Es256.coseValue(),
            payloadBytes,
            None,
            sigBytes
        )
        let structOpt = cose.sigStructureBytes()
        match (structOpt) {
            case Some(bytes) =>
                let parsed = decodeFromCborBytes(bytes)
                match (parsed) {
                    case CborValue.ArrayVal(items) =>
                        @Assert(items.size, Int64(4))
                        match (items[0]) {
                            case CborValue.TextStringVal(ctx) =>
                                @Assert(ctx, "Signature1")
                            case _ =>
                                @Assert(false)
                        }
                    case _ =>
                        @Assert(false)
                }
            case None =>
                @Assert(false)
        }
    }

    @TestCase
    func protectedHeaderAlgorithmRoundTrip(): Unit {
        let algo = VerifyAlgorithm.Es256.coseValue()
        let ph = CoseHeader.build(algo, true, None)
        match (ph.rawHeaderBytes) {
            case Some(b) =>
                let cbor = CborValue.ByteStringVal(b)
                let parsed = CoseHeader.fromBytestring(cbor)
                match (parsed) {
                    case Some(h) =>
                        match (h.algorithm) {
                            case Some(a) => @Assert(a, algo)
                            case None => @Assert(false)
                        }
                    case None =>
                        @Assert(false)
                }
            case None =>
                @Assert(false)
        }
    }

    @TestCase
    func detachedPayloadIsNull(): Unit {
        let cose = CoseSign1.create(
            VerifyAlgorithm.Es384.coseValue(),
            None,
            None,
            [0xAA]
        )
        let cbor = cose.toCbor()
        match (cbor) {
            case CborValue.ArrayVal(items) =>
                match (items[2]) {
                    case CborValue.NullVal => @Assert(true)
                    case _ => @Assert(false)
                }
            case _ =>
                @Assert(false)
        }
    }

    @TestCase
    func fourElementArrayStructure(): Unit {
        let payloadBytes: Array<UInt8> = [0x42]
        let sigBytes: Array<UInt8> = [0x99]
        let cose = CoseSign1.create(
            VerifyAlgorithm.Es256.coseValue(),
            payloadBytes,
            None,
            sigBytes
        )
        let cbor = cose.toCbor()
        match (cbor) {
            case CborValue.ArrayVal(items) =>
                @Assert(items.size, Int64(4))
            case _ =>
                @Assert(false)
        }
    }
}

/* ------------------------------------------------------------------ */
/* Test 3 — Base64UrlHelper and MdocValidationError (done_when 3)     */
/* ------------------------------------------------------------------ */

@Test
public class Base64UrlTest {

    @TestCase
    func encodeDecodeRoundTrip(): Unit {
        let original: Array<UInt8> = [0x01, 0x02, 0x03, 0x04, 0xFF, 0xFE]
        let encoded = Base64UrlHelper.encode(original)
        let decoded = Base64UrlHelper.decode(encoded)
        @Assert(bytesEqual(decoded, original))
    }

    @TestCase
    func encodeEmptyBytes(): Unit {
        let result = Base64UrlHelper.encode(Array<UInt8>())
        @Assert(result, "")
    }

    @TestCase
    func noPaddingInOutput(): Unit {
        let bytes: Array<UInt8> = [0x61]
        let encoded = Base64UrlHelper.encode(bytes)
        @Assert(!encoded.contains("="))
    }

    @TestCase
    func urlSafeAlphabet(): Unit {
        let bytes: Array<UInt8> = [0xFB, 0xFF]
        let encoded = Base64UrlHelper.encode(bytes)
        @Assert(!encoded.contains("+"))
        @Assert(!encoded.contains("/"))
    }
}

@Test
public class MdocValidationErrorTest {

    @TestCase
    func cborDecodingErrorMessage(): Unit {
        let err = MdocValidationError.cborDecodingError()
        let msg = err.errorMessage()
        @Assert(msg, "Failed to decode CBOR data")
    }

    @TestCase
    func invalidCborMessage(): Unit {
        let err = MdocValidationError.invalidCbor("IssuerAuth")
        let msg = err.errorMessage()
        @Assert(msg.contains("IssuerAuth"))
    }

    @TestCase
    func missingFieldMessage(): Unit {
        let err = MdocValidationError.missingField("MSO", "validityInfo")
        let msg = err.errorMessage()
        @Assert(msg.contains("MSO"))
        @Assert(msg.contains("validityInfo"))
    }
}

/* ------------------------------------------------------------------ */
/* Test 4 — HI-MDOC-001 regression: unprotected header map parsing    */
/*                                                                     */
/* RFC 8152 §4.2: COSE_Sign1 wire-format is                           */
/*   [bstr (protected), map (unprotected), bstr/nil, bstr]            */
/* The unprotected header is a direct CBOR map, NOT a bstr-wrapped    */
/* map. This test constructs a wire-format COSE_Sign1 with the        */
/* unprotected header carrying label-33 (x5chain) and verifies that   */
/* fromCborArray correctly populates unprotectedHeader.               */
/* ------------------------------------------------------------------ */

@Test
public class UnprotectedHeaderMapTest {

    // COSE label 33 = x5chain (UInt64(33))
    static let X5CHAIN_LABEL: UInt64 = 33

    // Build a fake x5chain bstr (DER-ish certificate bytes, just for structure test)
    static let FAKE_CERT: Array<UInt8> = [0x30, 0x82, 0x01, 0x00, 0xAB, 0xCD]

    /**
     * Build a wire-format COSE_Sign1 array with an unprotected header map
     * containing label 33 (x5chain) pointing to FAKE_CERT.
     */
    func buildWireFormatCoseSign1WithX5chain(): CborValue {
        // protected header: bstr .cbor {1: -7}
        let ph = CoseHeader.build(VerifyAlgorithm.Es256.coseValue(), true, None)
        let protectedCbor = ph.toProtectedCbor()

        // unprotected header: direct map {33: bstr(FAKE_CERT)}
        let uphPairs = ArrayList<(CborValue, CborValue)>()
        uphPairs.add((CborValue.UInt64Val(X5CHAIN_LABEL), CborValue.ByteStringVal(FAKE_CERT)))
        let unprotectedCbor = CborValue.MapVal(uphPairs)

        // payload: bstr([0x01, 0x02])
        let payloadCbor = CborValue.ByteStringVal([0x01, 0x02])

        // signature: bstr([0xAA, 0xBB])
        let sigCbor = CborValue.ByteStringVal([0xAA, 0xBB])

        let items = ArrayList<CborValue>()
        items.add(protectedCbor)
        items.add(unprotectedCbor)
        items.add(payloadCbor)
        items.add(sigCbor)
        return CborValue.ArrayVal(items)
    }

    /**
     * fromCborArray must parse the unprotected map and return Some(uph).
     * Before the fix: items[1] was fed to fromBytestring → None (MapVal rejected).
     * After the fix: items[1] is fed to fromMap → Some(uph) with rawHeaderBytes set.
     */
    @TestCase
    func unprotectedHeaderIsNotNoneOnWireFormat(): Unit {
        let wireArr = buildWireFormatCoseSign1WithX5chain()
        let coseOpt = CoseSign1.fromCborArray(wireArr)
        match (coseOpt) {
            case None => @Assert(false)
            case Some(cose) =>
                match (cose.unprotectedHeader) {
                    case None => @Assert(false)
                    case Some(_) => @Assert(true)
                }
        }
    }

    /**
     * rawHeaderBytes in the parsed unprotected header must decode back to a
     * map that contains key 33 with the original x5chain bytes.
     * This mirrors exactly what IssuerAuth.fromCbor and ReaderAuth.fromCbor do.
     */
    @TestCase
    func x5chainReachableThroughRawHeaderBytes(): Unit {
        let wireArr = buildWireFormatCoseSign1WithX5chain()
        let coseOpt = CoseSign1.fromCborArray(wireArr)
        match (coseOpt) {
            case None => @Assert(false)
            case Some(cose) =>
                match (cose.unprotectedHeader) {
                    case None => @Assert(false)
                    case Some(uph) =>
                        match (uph.rawHeaderBytes) {
                            case None => @Assert(false)
                            case Some(rawBytes) =>
                                let uphCbor = decodeCbor(rawBytes)
                                let x5chainOpt = uphCbor.field(CborValue.UInt64Val(X5CHAIN_LABEL))
                                match (x5chainOpt) {
                                    case None => @Assert(false)
                                    case Some(CborValue.ByteStringVal(certBytes)) =>
                                        @Assert(bytesEqual(certBytes, FAKE_CERT))
                                    case Some(_) => @Assert(false)
                                }
                        }
                }
        }
    }

    /**
     * Encode→decode round-trip preserving the unprotected header with multiple labels.
     * Verifies that toCbor() and fromCborArray() are inverse for the unprotected map.
     */
    @TestCase
    func encodeDecodeRoundTripWithUnprotectedMap(): Unit {
        // Build a CoseSign1 with unprotected map containing two labels: 33 (x5chain) + 4 (keyId)
        let uphPairs = ArrayList<(CborValue, CborValue)>()
        uphPairs.add((CborValue.UInt64Val(X5CHAIN_LABEL), CborValue.ByteStringVal(FAKE_CERT)))
        let kidBytes: Array<UInt8> = [0xDE, 0xAD]
        uphPairs.add((CborValue.UInt64Val(UInt64(CoseHeaderKey.KEY_ID)), CborValue.ByteStringVal(kidBytes)))
        let uphMap = CborValue.MapVal(uphPairs)
        let uphBytes = uphMap.encode()
        let uphHeader = CoseHeader(None, kidBytes, uphBytes)

        let ph = CoseHeader.build(VerifyAlgorithm.Es256.coseValue(), true, None)
        let payloadBytes: Array<UInt8> = [0x01]
        let sigBytes: Array<UInt8> = [0xFF]
        let original = CoseSign1(ph, Some(uphHeader), Some(payloadBytes), sigBytes)

        // Encode to CBOR array then decode back
        let encoded = original.toCbor()
        let decodedOpt = CoseSign1.fromCborArray(encoded)
        match (decodedOpt) {
            case None => @Assert(false)
            case Some(decoded) =>
                match (decoded.unprotectedHeader) {
                    case None => @Assert(false)
                    case Some(uph2) =>
                        match (uph2.rawHeaderBytes) {
                            case None => @Assert(false)
                            case Some(rawBytes2) =>
                                let map2 = decodeCbor(rawBytes2)
                                let x5Opt = map2.field(CborValue.UInt64Val(X5CHAIN_LABEL))
                                match (x5Opt) {
                                    case Some(CborValue.ByteStringVal(certBytes)) =>
                                        @Assert(bytesEqual(certBytes, FAKE_CERT))
                                    case _ => @Assert(false)
                                }
                        }
                }
        }
    }

    /**
     * An empty unprotected map {} must still produce Some(uph) — not None.
     * RFC 8152 §4.2 allows empty unprotected headers.
     */
    @TestCase
    func emptyUnprotectedMapIsNotNone(): Unit {
        let emptyPairs = ArrayList<(CborValue, CborValue)>()
        let emptyMap = CborValue.MapVal(emptyPairs)
        let uphOpt = CoseHeader.fromMap(emptyMap)
        match (uphOpt) {
            case None => @Assert(false)
            case Some(uph) =>
                match (uph.rawHeaderBytes) {
                    case None => @Assert(false)
                    case Some(b) => @Assert(b.size > 0)
                }
        }
    }
}

/* ================================================================== */
/* Added coverage: MacAlgorithm, MdocValidationError(Kind),           */
/* CoseHeader.toUnprotectedCbor                                        */
/* ================================================================== */

@Test
public class MacAlgorithmTest {

    /* coseValue/fromCoseValue round-trip for all three MAC algorithms. */
    @TestCase
    func macAlgorithmRoundTrip(): Unit {
        @Expect(MacAlgorithm.Hmac256.coseValue(), Int64(5))
        @Expect(MacAlgorithm.Hmac384.coseValue(), Int64(6))
        @Expect(MacAlgorithm.Hmac512.coseValue(), Int64(7))

        let algs: Array<MacAlgorithm> = [MacAlgorithm.Hmac256, MacAlgorithm.Hmac384, MacAlgorithm.Hmac512]
        for (alg in algs) {
            let back = MacAlgorithm.fromCoseValue(alg.coseValue())
            match (back) {
                case Some(a) => @Expect(a.coseValue(), alg.coseValue())
                case None => @Assert(false)
            }
        }
    }

    /* fromCoseValue returns None for an unrecognised COSE integer. */
    @TestCase
    func macAlgorithmUnknownIsNone(): Unit {
        @Assert(MacAlgorithm.fromCoseValue(99).isNone())
        @Assert(MacAlgorithm.fromCoseValue(-7).isNone())
    }
}

@Test
public class MdocValidationErrorDescribeTest {

    /* errorMessage()/describe for each MdocValidationErrorKind variant. */
    @TestCase
    func cborDecodingErrorMessage(): Unit {
        let e = MdocValidationError(MdocValidationErrorKind.CborDecodingError)
        @Expect(e.errorMessage(), "Failed to decode CBOR data")
    }

    @TestCase
    func invalidCborMessage(): Unit {
        let e = MdocValidationError(MdocValidationErrorKind.InvalidCbor("COSE key"))
        @Expect(e.errorMessage(), "Invalid CBOR format in COSE key")
    }

    @TestCase
    func missingFieldMessage(): Unit {
        let e = MdocValidationError(MdocValidationErrorKind.MissingField("CoseKey", "x"))
        @Expect(e.errorMessage(), "Missing field in CoseKey: x")
    }

    /* invalidDateTimeFormat factory builds the InvalidDateTimeFormat kind. */
    @TestCase
    func invalidDateTimeFormatFactory(): Unit {
        let e = MdocValidationError.invalidDateTimeFormat("ValidityInfo", "signed")
        @Expect(
            e.errorMessage(),
            "Invalid date-time format in ValidityInfo: signed must not contain fractional seconds"
        )
        match (e.kind) {
            case MdocValidationErrorKind.InvalidDateTimeFormat(component, field) =>
                @Expect(component, "ValidityInfo")
                @Expect(field, "signed")
            case _ => @Assert(false)
        }
    }
}

@Test
public class CoseHeaderUnprotectedCborTest {

    /* toUnprotectedCbor decodes the raw header bytes back into a CBOR map
       whose algorithm/keyId entries match what was built. */
    @TestCase
    func toUnprotectedCborDecodesMap(): Unit {
        let kid: Array<UInt8> = [0x01u8, 0x02u8, 0x03u8]
        // Mac0-style: non-negative algorithm encoding (Hmac256 = 5)
        let header = CoseHeader.build(5, false, Some(kid))
        let unprotected = header.toUnprotectedCbor()

        // algorithm key (1) must be present and equal to 5
        let algVal = unprotected.field(CborValue.UInt64Val(UInt64(CoseHeaderKey.ALGORITHM)))
        match (algVal) {
            case Some(CborValue.UInt64Val(n)) => @Expect(n, UInt64(5))
            case _ => @Assert(false)
        }
        // keyId key (4) must be present and equal to kid bytes
        let kidVal = unprotected.field(CborValue.UInt64Val(UInt64(CoseHeaderKey.KEY_ID)))
        match (kidVal) {
            case Some(CborValue.ByteStringVal(b)) =>
                @Expect(b.size, Int64(3))
                @Expect(b[0], 0x01u8)
            case _ => @Assert(false)
        }
    }

    /* A header with no raw bytes yields an empty unprotected map (not None). */
    @TestCase
    func toUnprotectedCborEmptyWhenNoRawBytes(): Unit {
        let header = CoseHeader(None, None, None)
        let unprotected = header.toUnprotectedCbor()
        match (unprotected) {
            case CborValue.MapVal(pairs) => @Expect(pairs.size, Int64(0))
            case _ => @Assert(false)
        }
    }
}
