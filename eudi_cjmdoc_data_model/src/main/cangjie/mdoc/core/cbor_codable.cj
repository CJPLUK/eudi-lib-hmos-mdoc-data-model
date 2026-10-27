/*
 * cbor_codable.cj
 *
 * Defines CBOREncodable / CBORDecodable — the universal CBOR codec protocol
 * pair for the EUDI mDoc module. These mirror the Swift CBOREncodable /
 * CBORDecodable protocols from the iOS reference implementation, using
 * CborValue from eudi_cjcbor as the interchange type.
 *
 * Implementations should round-trip: decode(encode(value)) == value.
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core

import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor

/**
 * A type that can encode itself into a CborValue.
 *
 * Mirrors iOS CBOREncodable.toCBOR(options:) -> CBOR.
 * Implementors must produce a CborValue whose re-encode round-trips losslessly.
 */
public interface CBOREncodable {
    /**
     * Return the canonical CborValue representation of this instance.
     * Call toCbor().encode() to obtain the raw byte sequence.
     */
    func toCbor(): CborValue
}

/**
 * A type that can be decoded from a CborValue.
 *
 * Mirrors iOS CBORDecodable.init(cbor:) throws.
 * The designated initialiser throws MdocValidationError on malformed input.
 */
public interface CBORDecodable {
    /**
     * Initialise from a CborValue.
     * Throws MdocValidationError if the structure does not match expectations.
     */
    static func fromCbor(cbor: CborValue): CBORDecodable
}

/**
 * Encode an encodable value to raw CBOR bytes.
 *
 * Convenience wrapper: toCbor() then CborValue.encode().
 */
public func encodeToCbor(value: CBOREncodable): Array<UInt8> {
    return value.toCbor().encode()
}

/**
 * Decode raw CBOR bytes into a CborValue.
 *
 * Thin wrapper over decodeCbor() from eudi_cjcbor, exposed here so callers
 * in the mdoc.core package need only one import.
 */
public func decodeFromCborBytes(bytes: Array<UInt8>): CborValue {
    return decodeCbor(bytes)
}
