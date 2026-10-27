# eudi_lib_mdoc_data_model

EU Digital Identity Wallet **ISO/IEC 18013-5 mDoc 数据模型**库的**仓颉(Cangjie)/ HarmonyOS 移植**,移植自欧盟委员会官方参考实现 [eudi-lib-ios-iso18013-data-model](https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-data-model)。

## 功能

- **COSE 基础**:CoseSign1(tag-18)容器、RFC 8152 §4.2 wire-format 解析(unprotected map)、Sig_Structure 构造
- **设备引导(DeviceEngagement)**:QR(`mdoc:`+base64url)互逆、BLE/NFC/HTTP retrieval、COSE_Key
- **签发方认证(IssuerAuth/MSO)**:MobileSecurityObject、ValueDigests(多 namespace)、Tag24 双层解包、x5chain(label 33)
- **请求/响应(DeviceRequest/DeviceResponse)**:ItemsRequest/ReaderAuth、IssuerSignedItem **rawData 原字节保留**(ISO §9.1.2 digest 合规的关键)、DeviceAuth 互斥约束
- **已知文档类型**:IsoMdlModel(`org.iso.18013.5.1.mDL`)/ EuPidModel(`eu.europa.ec.eudi.pid.1`)/ DrivingPrivileges / 年龄断言(ISO 7.2.5 nearest-match)
- **SecureArea 协议层**(实现归上层 wallet-kit)与 **ZKP 规范模型**

## 仓库结构(团队统一 cbor 形态)

```
eudi_lib_mdoc_data_model/
├── eudi_cjmdoc_data_model/                   ← HAR 模块(交付单元,pkg ohos_app_cangjie_eudi_cjmdoc_data_model)
│   └── src/main/cangjie/mdoc/     ← core/engagement/claims/issuerauth/request/
│                                     response/doctypes/securearea/zkp 九个子包
├── entry/                         ← 测试面板 HAP(43 个设备 E2E + "Run mDoc Demo" 按钮)
│   └── libs/{stdx, arm64-v8a}/    ← stdx 1.1.3.1 + 运行时三件套(已带)
└── third_party/                   ← (gitignored)上游锁定 clone,见下
```

## 上游依赖(首次构建前 clone)

```bash
git clone https://github.com/CJPLUK/eudi-lib-hmos-cbor third_party/eudi_lib_cbor
cd third_party/eudi_lib_cbor && git checkout v0.1.0 && cd ../..
git clone https://github.com/CJPLUK/eudi-lib-hmos-core-crypto third_party/eudi_lib_core_crypto
cd third_party/eudi_lib_core_crypto && git checkout v0.1.0 && cd ../..
```

## 下游消费(cjpm path 依赖)

```toml
[dependencies]
  [dependencies.ohos_app_cangjie_eudi_cjmdoc_data_model]
    path = "../third_party/eudi_lib_mdoc_data_model/eudi_cjmdoc_data_model"
```

```cangjie
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.*
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.doctypes.*
```

## ISO digest 计算形态(重要,下游照此)

digest 输入 = `Tag24(bstr(.cbor IssuerSignedItem))` **单层** bstr(`D818 || bstrHdr || M`):

```cangjie
// 编码侧(参照 demo runMdocDemo / IssuerNameSpaces.toCbor)
let digest = Digest.sha256(encodeEmbedded(item.toCbor()).encode())
// 解码侧:rawData 已是 item map 字节,直接构造 TaggedVal,勿再 encodeEmbedded(会多包一层 bstr)
let recomputed = Digest.sha256(
    CborValue.TaggedVal(CborTag.ENCODED_CBOR, CborValue.ByteStringVal(item.rawData)).encode())
```

与 iOS 参考实现字节级对齐(设备 E2E 43/43 实证)。

## 构建与验证

构建命令、环境变量与运行时三件套要求同团队 lib-packaging-spec,参照 [eudi_lib_sdjwt](https://github.com/CJPLUK/eudi-lib-hmos-sdjwt) README 的"构建"一节(完全相同)。测试面板:app 内点 **Run mDoc Demo** → `OK: docs=1, digests=2, roundtrip=PASS, ageOver18=true`。

## License

[Apache License 2.0](LICENSE)。本项目为 eudi-lib-ios-iso18013-data-model(© European Commission)的衍生移植,归属与捆绑件声明见 [NOTICE](NOTICE)。
