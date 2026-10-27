/*
 * core_util.cj
 *
 * MdocValidationError — typed error for EUDI mDoc validation failures.
 * Base64UrlHelper      — RFC 4648 §5 url-safe base64 delegated to eudi_lib_core_crypto.
 *
 * iOS references:
 *   MdocDataModel18013/MdocValidationError.swift
 *   MdocDataModel18013/Data+Base64URL.swift
 */
package ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core

import eudi_lib_core_crypto.Base64Url

/**
 * Error kind enum for MdocValidationError.
 * Cangjie enums cannot extend Exception, so we use a separate enum
 * for the kind and wrap it in an Exception subclass.
 */
public enum MdocValidationErrorKind {
    /** The raw bytes could not be parsed as valid CBOR. */
    | CborDecodingError
    /** The CBOR structure at the named component is malformed. */
    | InvalidCbor(String)
    /** A required field is absent from the named component. */
    | MissingField(String, String)
    /** A date-time field contains fractional seconds, which ISO 18013-5 forbids. */
    | InvalidDateTimeFormat(String, String)
}

/**
 * Exception carrying an MdocValidationErrorKind.
 * Mirrors iOS MdocValidationError enum (which is a LocalizedError).
 */
public class MdocValidationError <: Exception {
    public let kind: MdocValidationErrorKind

    public init(k: MdocValidationErrorKind) {
        super(MdocValidationError.describeKind(k))
        this.kind = k
    }

    public func errorMessage(): String {
        return MdocValidationError.describeKind(this.kind)
    }

    static func describeKind(k: MdocValidationErrorKind): String {
        match (k) {
            case MdocValidationErrorKind.CborDecodingError =>
                return "Failed to decode CBOR data"
            case MdocValidationErrorKind.InvalidCbor(component) =>
                return "Invalid CBOR format in " + component
            case MdocValidationErrorKind.MissingField(component, field) =>
                return "Missing field in " + component + ": " + field
            case MdocValidationErrorKind.InvalidDateTimeFormat(component, field) =>
                return "Invalid date-time format in " + component + ": " + field +
                    " must not contain fractional seconds"
        }
    }

    /* Convenience factory methods mirroring iOS enum cases */
    public static func cborDecodingError(): MdocValidationError {
        return MdocValidationError(MdocValidationErrorKind.CborDecodingError)
    }
    public static func invalidCbor(component: String): MdocValidationError {
        return MdocValidationError(MdocValidationErrorKind.InvalidCbor(component))
    }
    public static func missingField(component: String, field: String): MdocValidationError {
        return MdocValidationError(MdocValidationErrorKind.MissingField(component, field))
    }
    public static func invalidDateTimeFormat(component: String, field: String): MdocValidationError {
        return MdocValidationError(MdocValidationErrorKind.InvalidDateTimeFormat(component, field))
    }
}

/**
 * RFC 4648 §5 url-safe base64 utilities.
 *
 * Delegates entirely to eudi_lib_core_crypto.Base64Url so the mDoc layer
 * has a single consistent codec and no duplication.
 *
 * iOS source: Data+Base64URL.swift (base64URLEncodedString / Data(base64URLEncoded:))
 */
public class Base64UrlHelper {

    /**
     * Encode bytes as url-safe base64 without padding ('=' stripped).
     * Equivalent to iOS Data.base64URLEncodedString().
     */
    public static func encode(data: Array<UInt8>): String {
        return Base64Url.encode(data)
    }

    /**
     * Decode a url-safe base64 string (padding optional) to bytes.
     * Throws CoreCryptoException if the input is not valid base64url.
     * Equivalent to iOS Data(base64URLEncoded: string).
     */
    public static func decode(text: String): Array<UInt8> {
        return Base64Url.decode(text)
    }
}
