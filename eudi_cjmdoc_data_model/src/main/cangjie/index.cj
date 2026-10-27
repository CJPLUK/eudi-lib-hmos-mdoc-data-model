package ohos_app_cangjie_eudi_cjmdoc_data_model

import std.collection.ArrayList
import std.collection.HashMap

import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjcbor.cbor.CborTag
import ohos_app_cangjie_eudi_cjcbor.cbor.encodeEmbedded

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.core.VerifyAlgorithm

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.DigestAlgorithmKind
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.DigestIDs
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.ValueDigests
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.ValidityInfo
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.DeviceKeyInfo
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.MobileSecurityObject
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.IssuerAuth

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.IssuerSignedItem
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.IssuerNameSpaces
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.IssuerSigned
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.DeviceSignedItems
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.DeviceNameSpaces
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.DeviceAuth
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.DeviceSigned
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.Document
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.DeviceResponse

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.doctypes.ISO_MDL_DOC_TYPE
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.doctypes.ISO_MDL_NAMESPACE

import eudi_lib_core_crypto.Digest

/**
 * runMdocDemo — end-to-end mDoc pipeline demo.
 *
 * Constructs a minimal mDL Document (ISO 18013-5):
 *   1. Build IssuerSignedItem for family_name and age_over_18 claims.
 *   2. Compute SHA-256 digests over Tag24-wrapped item bytes (ISO §9.1.2).
 *   3. Build MobileSecurityObject → wrap as Tag24 payload → IssuerAuth (COSE_Sign1).
 *   4. Assemble IssuerSigned + DeviceSigned + Document + DeviceResponse.
 *   5. CBOR-encode the DeviceResponse → decode back.
 *   6. Verify digest round-trip: recompute SHA-256 over decoded item raw bytes,
 *      compare with stored ValueDigests.
 *   7. Verify age_over_18 claim value survives round-trip.
 *   Returns "OK: docs=1, digests=2, roundtrip=PASS, ageOver18=true"
 *   or "ERR <reason>" on any failure.
 */
public func runMdocDemo(): String {
    try {
        let ns = ISO_MDL_NAMESPACE
        let docType = ISO_MDL_DOC_TYPE

        /* ---- Step 1: build IssuerSignedItem objects ---- */
        let familyNameItem = IssuerSignedItem(
            0,
            [0x01u8, 0x02u8, 0x03u8, 0x04u8],
            "family_name",
            CborValue.TextStringVal("Doe"),
            None
        )
        let ageOver18Item = IssuerSignedItem(
            1,
            [0x05u8, 0x06u8, 0x07u8, 0x08u8],
            "age_over_18",
            CborValue.BoolVal(true),
            None
        )

        /* ---- Step 2: compute Tag24 digests ---- */
        // ISO 18013-5 §9.1.2: digest = SHA-256(#6.24(bstr .cbor IssuerSignedItem))
        // encodeEmbedded(v) = Tag24(bstr(v.encode())); passing toCbor() directly gives
        // Tag24(bstr(M)) — single layer matching the verify-side recomputation.
        let familyNameTag24 = encodeEmbedded(familyNameItem.toCbor())
        let familyNameTag24Bytes = familyNameTag24.encode()
        let digest0 = Digest.sha256(familyNameTag24Bytes)

        let ageOver18Tag24 = encodeEmbedded(ageOver18Item.toCbor())
        let ageOver18Tag24Bytes = ageOver18Tag24.encode()
        let digest1 = Digest.sha256(ageOver18Tag24Bytes)

        /* ---- Step 3: build MSO ---- */
        let digestMap = HashMap<UInt64, Array<UInt8>>()
        digestMap.add(0, digest0)
        digestMap.add(1, digest1)
        let digestIDs = DigestIDs(digestMap)

        let vdOuter = HashMap<String, DigestIDs>()
        vdOuter.add(ns, digestIDs)
        let valueDigests = ValueDigests(vdOuter)

        let deviceKeyPairs = ArrayList<(CborValue, CborValue)>()
        deviceKeyPairs.add((CborValue.UInt64Val(1), CborValue.UInt64Val(2)))
        let deviceKeyCbor = CborValue.MapVal(deviceKeyPairs)
        let deviceKeyInfo = DeviceKeyInfo(deviceKeyCbor, None, None)

        let validityInfo = ValidityInfo(
            "2025-01-01T00:00:00Z",
            "2025-01-01T00:00:00Z",
            "2030-01-01T00:00:00Z",
            None
        )

        let mso = MobileSecurityObject(
            MobileSecurityObject.DEFAULT_VERSION,
            DigestAlgorithmKind.Sha256.stringValue(),
            valueDigests,
            deviceKeyInfo,
            docType,
            validityInfo
        )

        /* ---- Step 4: build IssuerAuth (COSE_Sign1 with demo signature) ---- */
        let msoTag24Bytes = mso.toTag24Bytes()

        let certBytes: Array<UInt8> = [0xAAu8, 0xBBu8]
        let demoSig: Array<UInt8> = [0x00u8, 0x00u8, 0x00u8, 0x00u8]

        let issuerAuth = IssuerAuth(
            mso,
            msoTag24Bytes,
            VerifyAlgorithm.Es256.coseValue(),
            demoSig,
            ArrayList<Array<UInt8>>(),
            None
        )
        issuerAuth.x5chain.add(certBytes)

        /* ---- Step 5: assemble IssuerNameSpaces ---- */
        let nsItems = ArrayList<IssuerSignedItem>()
        nsItems.add(familyNameItem)
        nsItems.add(ageOver18Item)
        let nsMap = HashMap<String, ArrayList<IssuerSignedItem>>()
        nsMap.add(ns, nsItems)
        let issuerNameSpaces = IssuerNameSpaces(nsMap)

        let issuerSigned = IssuerSigned(Some(issuerNameSpaces), issuerAuth)

        /* ---- Step 6: build DeviceSigned (empty namespaces) ---- */
        let emptyNsPairs = ArrayList<(String, DeviceSignedItems)>()
        let deviceNameSpaces = DeviceNameSpaces(emptyNsPairs)

        let deviceAuth = DeviceAuth(false, CborValue.UInt64Val(0))

        let deviceSigned = DeviceSigned(deviceNameSpaces, deviceAuth)

        /* ---- Step 7: assemble Document + DeviceResponse ---- */
        let document = Document(docType, issuerSigned, deviceSigned, None)

        let docList = ArrayList<Document>()
        docList.add(document)

        let deviceResponse = DeviceResponse(
            DeviceResponse.DEFAULT_VERSION,
            Some(docList),
            None,
            0
        )

        /* ---- Step 8: CBOR encode + decode round-trip ---- */
        let encoded = deviceResponse.toCbor().encode()
        let decodedResponse = DeviceResponse.fromCborBytes(encoded)

        /* ---- Step 9: verify docs count ---- */
        let docsOpt = decodedResponse.documents
        let docs: ArrayList<Document>
        match (docsOpt) {
            case Some(d) => docs = d
            case None => return "ERR decoded DeviceResponse has no documents"
        }
        if (docs.size != 1) {
            return "ERR expected 1 document, got " + docs.size.toString()
        }

        /* ---- Step 10: verify digest round-trip ---- */
        let decodedDoc = docs[0]
        let decodedIssuerSigned = decodedDoc.issuerSigned
        let decodedNsOpt = decodedIssuerSigned.issuerNameSpaces
        let decodedNs: IssuerNameSpaces
        match (decodedNsOpt) {
            case Some(n) => decodedNs = n
            case None => return "ERR decoded IssuerSigned has no nameSpaces"
        }

        let decodedItemsOpt = decodedNs.get(ns)
        let decodedItems: ArrayList<IssuerSignedItem>
        match (decodedItemsOpt) {
            case Some(items) => decodedItems = items
            case None => return "ERR decoded IssuerNameSpaces missing namespace"
        }

        if (decodedItems.size != 2) {
            return "ERR expected 2 items in namespace, got " + decodedItems.size.toString()
        }

        let decodedMsoOpt = decodedDoc.issuerSigned.issuerAuth.mso
        let storedVdOpt = decodedMsoOpt.valueDigests.get(ns)
        let storedVd: DigestIDs
        match (storedVdOpt) {
            case Some(vd) => storedVd = vd
            case None => return "ERR decoded MSO missing ValueDigests for namespace"
        }

        var digestsVerified: Int64 = 0
        var i: Int64 = 0
        while (i < decodedItems.size) {
            let decodedItem = decodedItems[i]
            let itemRawBytes: Array<UInt8>
            match (decodedItem.rawData) {
                case Some(raw) => itemRawBytes = raw
                case None => return "ERR decoded IssuerSignedItem missing rawData at index " + i.toString()
            }
            let recomputedDigest = Digest.sha256(
                CborValue.TaggedVal(CborTag.ENCODED_CBOR, CborValue.ByteStringVal(itemRawBytes)).encode()
            )
            let storedDigestOpt = storedVd.get(decodedItem.digestID)
            let storedDigest: Array<UInt8>
            match (storedDigestOpt) {
                case Some(d) => storedDigest = d
                case None => return "ERR no stored digest for digestID " + decodedItem.digestID.toString()
            }
            if (!digestBytesEqual(recomputedDigest, storedDigest)) {
                return "ERR digest mismatch for item " + decodedItem.elementIdentifier
            }
            digestsVerified++
            i++
        }

        /* ---- Step 11: verify age_over_18 claim value ---- */
        var ageOver18Value: Bool = false
        var j: Int64 = 0
        while (j < decodedItems.size) {
            let item = decodedItems[j]
            if (item.elementIdentifier == "age_over_18") {
                match (item.elementValue) {
                    case CborValue.BoolVal(b) => ageOver18Value = b
                    case _ => return "ERR age_over_18 elementValue is not Bool"
                }
            }
            j++
        }

        return "OK: docs=1, digests=" + digestsVerified.toString() +
               ", roundtrip=PASS, ageOver18=" + ageOver18Value.toString()
    } catch (e: Exception) {
        return "ERR " + e.message
    }
}

func digestBytesEqual(a: Array<UInt8>, b: Array<UInt8>): Bool {
    if (a.size != b.size) {
        return false
    }
    var i: Int64 = 0
    while (i < a.size) {
        if (a[i] != b[i]) {
            return false
        }
        i++
    }
    return true
}
