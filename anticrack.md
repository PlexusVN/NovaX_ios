# Kế hoạch Anti-Crack Astra cho ESign/KSign

> Baseline được rà soát lại từ source ngày 26/10/2026. Tài liệu này bao phủ app Astra, AUTH server và Assembly-CSharp patch hiện có; đây là kế hoạch triển khai, không phải xác nhận rằng anti-crack v2 đã được cài đặt.

## 1. Phạm vi và nguyên tắc

Tài liệu này mô tả đầy đủ baseline hiện tại của Astra, AUTH server và Assembly-CSharp patch, sau đó đưa ra kiến trúc anti-crack phù hợp với IPA được ký lại bằng ESign/KSign.

Đây là tài liệu thiết kế, không phải tuyên bố rằng mọi hạng mục đã được triển khai. Mỗi lớp bảo vệ phải được bật theo giai đoạn, có test, telemetry và rollback. Không thay đổi logic Direct/AirLift, pairing, codepatch, tên file hoặc feature state nếu chưa có regression test tương ứng.

Không có giải pháp client-side làm IPA “không thể sửa”. Mục tiêu thực tế là:

1. IPA bị sửa không dùng được API chính thức chỉ bằng license key thật.
2. Script có key thật không tải được patch hoặc gửi command nếu thiếu private key của installation đã đăng ký.
3. Session/request bị sao chép không thể phát lại trên máy khác.
4. Server giả không tạo được response, manifest hoặc command có chữ ký Astra hợp lệ.
5. Assembly chỉ nhận state/command của đúng session, variant và release.
6. File codepatch vẫn giữ nguyên tên admin upload, vẫn được mã hóa và kiểm tra trước khi ghi.
7. Anti-crack không được gây lỗi nhầm cho ESign/KSign, LocalDevVPN, AirLift hoặc direct/kernel.

### Giới hạn phải chấp nhận

- Plaintext vẫn có thể bị trích xuất khi đang nằm trong RAM hoặc đang được ghi xuống game.
- Kẻ tấn công có thể sao chép giao diện và vận hành một app/assembly đã sửa hoàn toàn trên server riêng; hệ thống của Astra chỉ có thể bảo vệ dịch vụ, dữ liệu, release và chữ ký chính thức.
- Obfuscation, anti-Frida và pinning chỉ tăng chi phí crack, không phải gốc tin cậy duy nhất.
- IP không phải danh tính thiết bị vì người dùng có thể đổi Wi-Fi/4G và app/assembly có thể đi qua đường mạng khác nhau.
- Trong mô hình ESign/KSign không có Apple App Attest hợp lệ và ổn định cho một App ID do chủ hệ thống kiểm soát, server không thể chứng minh tuyệt đối binary đang gọi API là IPA nguyên bản. Secure Enclave device proof chứng minh “installation đã đăng ký đang giữ private key”, không tự chứng minh code chưa bị sửa.
- Nếu kẻ tấn công sửa IPA rồi ký bằng cùng identity/access group đang dùng trên chính thiết bị của họ, bản sửa có thể vẫn truy cập device key cũ. Vì vậy device proof phải đi cùng server signature, release allowlist, integrity/risk telemetry và kiểm soát hành vi; không được quảng cáo như remote attestation tuyệt đối.
- Một assembly đã bị sửa hoàn toàn và trỏ sang server riêng vẫn có thể chạy chức năng do chính kẻ tấn công cung cấp. Gốc tin cậy bất đối xứng chỉ ngăn server giả mạo dữ liệu/chữ ký Astra và ngăn dùng dịch vụ chính thức trái phép; nó không thể xóa code đã bị sao chép khỏi máy của đối phương.

---

## 2. Mô hình đe dọa

### Đối tượng tấn công

- Người có IPA và công cụ phân tích tĩnh.
- Người sửa endpoint/auth logic rồi ký lại IPA.
- Người có key thật và viết script gọi API.
- Người hook TLS/certificate validation hoặc cài proxy CA.
- Người dùng Frida/debugger để đọc token, plaintext hoặc đổi nhánh kiểm tra.
- Người sửa assembly để bỏ AUTH hoặc trỏ sang server khác.
- Người lấy codepatch hợp lệ rồi phát tán.
- Người replay nonce, session hoặc command cũ.

### Tài sản cần bảo vệ

- License, HWID và liên kết thiết bị.
- App session, assembly session và refresh state.
- Codepatch mod/original, tên file thật và release hash.
- Command/state bật tắt chức năng.
- Private signing key phía server.
- Credential hạ tầng và origin/VPS.
- Pairing record AirLift.

### Ràng buộc ESign/KSign

Do IPA được ký bằng nhiều certificate khác nhau, hệ thống không được hard-block dựa trên:

- Team ID cố định.
- Provisioning profile hash cố định.
- CodeDirectory hoặc chữ ký cuối cùng của IPA.
- App Attest bắt buộc cho một App ID duy nhất.
- `get-task-allow` như một tín hiệu đơn lẻ.
- Bundle ID hoặc signing identity như gốc tin cậy duy nhất.

ESign/KSign có thể làm thay đổi Keychain access group. Nếu đổi certificate khiến khóa cũ không đọc được, app phải coi đó là installation mới có kiểm soát và cho phép liên kết lại theo giới hạn thiết bị, không crash hoặc loop login.

---

## 3. Bản đồ logic hiện tại

### 3.1 App Astra

- Entry/lifecycle: `ThreeOneOSFive/App.swift`.
- AUTH license: `ThreeOneOSFive/views/AuthManager.swift`.
- TLS pinning, proxy guard, Keychain, HWID: `ThreeOneOSFive/views/SecurityUtils.swift`.
- Anti-tamper: `ThreeOneOSFive/helpers/AntiTamper.swift`.
- NovaX session, menu, command, download/decrypt/write: `ThreeOneOSFive/helpers/FeaturePatchService.swift`.
- Chính sách iOS: `ThreeOneOSFive/helpers/KernelExploit.swift`.
- Điều phối ghi file: `ThreeOneOSFive/helpers/StorageEngineCoordinator.swift`.
- Pairing: `ThreeOneOSFive/helpers/AirLiftPairingManager.swift`.
- RSD/AFC/AirTraffic/canary: `ThreeOneOSFive/helpers/AirTrafficProtocolClient.swift`.
- LocalDevVPN probe: `ThreeOneOSFive/helpers/AirLiftTunnelManager.swift`.

### 3.2 Server

- Express app: `../AUTH/server/index.js`.
- NovaX/app/assembly/codepatch: `../AUTH/server/novax_control.js`.
- Cloudflare/origin guard: `../AUTH/server/security_network.js`.
- Public config policy: `../AUTH/server/security_policy.js`.

### 3.3 Assembly

- Template nguồn: `../FIX-CRASH-ESP/project-freefire_c#/project-freefire_c#/src/ESPLogic.template.cs`.
- Weave/build: `build.ps1`, `src/WeaveEsp.cs`, `tools/`.
- Artifact: `dist/`.

### 3.4 Ma trận Direct/AirLift hiện tại

| Phiên bản | Ghi file | Pairing |
|---|---|---|
| iOS 16.x | Direct/kernel | Không cần AirLift |
| iOS 17.0–17.7.x | Direct/kernel | Không cần AirLift |
| iOS 18.0–18.7.1 | Direct/kernel | Không cần AirLift |
| iOS 18.7.2–18.8.x | AirLift | File pairing từ máy tính |
| iOS 26.0–26.6.1 | Direct | Không cần AirLift |
| iOS 26.6.2+, gồm 26.7 | AirLift | File pairing từ máy tính |
| iOS 27.0–27.1 | AirLift | Pair trên máy hoặc nhập file |
| iOS 27.2 | AirLift nếu build nằm trong allowlist | Pair trên máy hoặc nhập file |

Anti-crack không được coi quyền direct/kernel hoặc khả năng truy cập container game là bằng chứng jailbreak, vì đó là chức năng hợp lệ của Astra.

### 3.5 AUTH app hiện tại

1. Người dùng nhập license.
2. HWID được tạo từ identifierForVendor, model và bundle ID rồi cache Keychain.
3. App gọi `/api/verify` qua `URLSession` có certificate pinning, nhưng request hiện không gửi nonce/timestamp có ý nghĩa để app đối chiếu response.
4. Server trả type, expiry, HMAC; server còn có khả năng tạo RSA signature/session token cho payload AUTH.
5. App hiện chỉ kiểm tra HMAC bằng product secret nhúng trong binary, chưa kiểm tra RSA signature, nonce, timestamp hoặc AUTH session token server trả về.
6. License đang lưu trong `UserDefaults`.
7. App re-verify định kỳ theo backoff 60/120/240/480 giây; sau ba lỗi mạng liên tiếp có thể chuyển khỏi trạng thái verified.

Điểm tốt: có pinning, re-verify, HWID/device limit và phân biệt lỗi AUTH với lỗi mạng.

Điểm yếu: shared secret có thể bị dump; HMAC không còn chứng minh server thật khi secret lộ; chữ ký RSA server tạo ra đang bị app bỏ qua; license nằm trong `UserDefaults`; HWID chưa phải proof-of-possession của private key phần cứng.

### 3.6 NovaX app session hiện tại

1. App gọi `/api/novax/login` bằng key, HWID và product secret.
2. Server xác minh key/HWID và tạo session ngắn hạn.
3. App giữ raw token, server chỉ lưu token hash.
4. Menu/state/command/download dùng Bearer token + key + HWID.
5. App tự tạo lại session khi gần hết hạn.

Điểm yếu: request chưa có chữ ký từ một private key riêng của installation. Token/HWID lấy từ runtime có thể được script sử dụng lại.

### 3.7 Codepatch hiện tại

1. Admin upload mod/original cho ffth/ffmax.
2. Tên file thật nằm trong database; object storage dùng internal key theo SHA-256.
3. App download bằng NovaX session.
4. Server mã hóa AES-256-GCM; khóa dẫn xuất bằng HKDF từ session token.
5. Response mang salt, nonce, tag, SHA-256, length, variant, kind và tên file URL-encoded.
6. App giải mã, kiểm tra length/hash và validate tên.
7. App ghi đúng tên xuống codepatch directory bằng Direct hoặc AirLift.
8. File tạm được xóa sau thao tác.

Luồng này phải được giữ nguyên về tên file và destination. Protocol v2 chỉ bổ sung device proof và signed manifest.

### 3.8 Ghi file hiện tại

Direct: resolve container, xác định directory, ưu tiên replacement service, fallback atomic write.

AirLift: kiểm tra LocalDevVPN, pairing, resolve RSD/AFC/AirTraffic, bắt buộc canary write/read-back rồi mới ghi file thật.

Không được chèn integrity scan, sleep, debugger polling hoặc network probe vào FFI queue/canary/write callback. Security checkpoint phải kết thúc trước download hoặc trước transaction ghi file.

### 3.9 Assembly hiện tại

1. Hiển thị menu nhập key.
2. Gọi `/api/assembly/connect` với product, key, variant, patch version và nonce.
3. Server yêu cầu key hợp lệ và có app session đang hoạt động.
4. Server tạo assembly session ngắn hạn.
5. Connect response hiện được HMAC bằng shared product secret.
6. Poll request gửi actual state được AES-CBC/HMAC bằng key dẫn xuất từ session token.
7. Poll response chứa desired state/command, nonce và revision.
8. Assembly chỉ mutate feature sau khi secure payload hợp lệ.

Phần poll có nền tảng tốt: nonce, encryption, MAC, revision và desired-state reconciliation. Điểm yếu chính nằm ở bootstrap/connect và shared secret.

### 3.10 Anti-tamper hiện tại

- Kiểm tra một số đường dẫn jailbreak.
- Probe Frida port mặc định.
- Chỉ ghi log.
- `checkBeforePatch()` luôn cho qua.
- `SecurityCheckResult.isCompromised` luôn false.

Không được chuyển ngay thành hard-block vì signal còn ít và dễ false positive trên sideload/direct.

### 3.11 Ba mặt phẳng patch đang tồn tại

Không được gộp ba luồng dưới đây thành một khi triển khai anti-crack:

| Luồng | API/định dạng | Kiểm tra hiện tại | Cách ghi/khôi phục |
|---|---|---|---|
| Legacy catalog | `/api/ff/sync`, `/api/ff/download/:slug`, file `.3105` | Metadata HMAC bằng chính license key; download chỉ cần key; package dùng AES-GCM nội bộ, password/PBKDF2 nếu private | Direct dùng `PatchTransaction` có journal/backup/restore; AirLift batch-write nhưng hiện không restore tùy ý |
| Native release | `/api/novax/patches/:id/download`, file `.3105` | NovaX bearer session + SHA-256/size; response file hiện chưa mã hóa riêng theo session và chưa có manifest bất đối xứng | Decode `PatchPackageCodec`, sau đó Direct transaction hoặc AirLift batch-write |
| Codepatch mod/original | `/api/novax/codepatch/:variant/:kind/download` | NovaX bearer session, AES-256-GCM, HKDF từ session token, AAD, length/SHA-256, filename validate | Ghi đúng filename admin upload bằng Direct replacement/atomic write hoặc AirLift |

Hệ quả bảo mật:

- Legacy catalog là đường tải yếu nhất: người có key thật có thể script tải `.3105`; HMAC dùng license key không chứng minh server với người đang giữ key.
- Native release có auth session nhưng ciphertext không bind từng session như codepatch; hash chỉ phát hiện sai dữ liệu, không chứng minh manifest do Astra ký.
- Codepatch là luồng tốt nhất hiện tại nhưng vẫn phụ thuộc shared secret/session có thể lấy từ runtime và app phải giải mã plaintext trước khi ghi.
- `PatchPackageCodec` bảo vệ tính toàn vẹn package bằng AES-GCM và digest từng replacement; package public chứa content key trong envelope nên không phải cơ chế giữ bí mật trước người đã có file.
- Direct transaction có journal, backup, kiểm tra digest, chống symlink/path traversal và atomic rename. Anti-crack không được bỏ qua các bước này.
- AirLift project apply gom file theo bundle/directory và bắt canary qua `AirTrafficProtocolClient`; trạng thái applied lưu `UserDefaults`, nhưng upstream hiện chưa hỗ trợ restore file gốc tùy ý.

### 3.12 Vòng đời app và dữ liệu local

1. `App.swift` chạy anti-tamper log-only, update check và iOS support detection.
2. Nếu có license đã lưu, app gọi lại AUTH; chỉ khi `authState == verified` mới hiện giao diện chính.
3. Khi active/verified, app sync metadata và menu/state.
4. NovaX app token chỉ nằm trong RAM của `FeaturePatchService`; codepatch filename, applied flags và metadata cache nằm trong `UserDefaults`/Application Support.
5. Pairing record nằm tại `Application Support/AirLift/novax_airlift_pairing.plist` với complete file protection; AltIRK host hiện nằm trong `UserDefaults`.
6. Content key của package `.3105` có thể được cache bằng Keychain `PatchKeyStore`.
7. Logout AUTH hiện xóa license `UserDefaults`, không thu hồi NovaX token phía server và không xóa token RAM ngay trong `FeaturePatchService` bằng một API logout thống nhất.

Anti-crack migration phải giữ nguyên pairing record, patch journal/backup, package keys và trạng thái Direct/AirLift. Không dùng thao tác “xóa sạch local state” khi phát hiện risk.

### 3.13 Remote config, hướng dẫn và DNS

- Update checker, NextDNS config và Guide service có các request dùng `URLSession.shared`, không đi qua certificate-pinned session của AUTH/NovaX.
- `/api/client/config` có thể điều khiển version bắt buộc và update URL. Đây là security-sensitive response dù endpoint là public; phải có chữ ký server và allowlist scheme/host trước khi mở URL.
- `nextdns_config_id` có thể tiếp tục là public config nhưng phải tách namespace/signature khỏi update policy. Không pin hoặc chặn lưu lượng `nextdns.io` theo cách làm hỏng tính năng DNS.
- Hướng dẫn, ảnh/video và lượt thích là dữ liệu public, không nên bắt device proof cho thao tác đọc; chỉ cần giới hạn abuse và xác thực nguồn khi nội dung có khả năng mở deep link.

### 3.14 Feature/assembly contract hiện tại

- App khai báo 41 feature mặc định: 12 ESP, 7 Aim, 14 Khác, 7 Màu sắc và `settings.restore`.
- Assembly còn nhận nhóm `mod.hair`, `mod.top`, `mod.bottom`, `mod.shoes`, `mod.face`, `mod.reset` từ catalog/control plane.
- Server giữ desired state theo key + variant; assembly gửi actual state và applied revision.
- `aim.silent` và `aim.system` loại trừ nhau ở server; assembly vẫn phải tự clamp/restore an toàn.
- Tất cả mutation phải tiếp tục đi qua gateway `ApplyRemoteControlCommand`; không cho lớp anti-crack ghi trực tiếp các biến gameplay.
- Bốn redirect artifact hiện tại là bootstrap, GUI ESP/menu, silent aim và native aim system. Build manifest hiện ghi SHA-256 artifact và binding/dump hashes, nhưng manifest chưa có chữ ký release.

Danh sách ID/type/range/default phải được xuất tự động thành fixture từ app, server và assembly rồi so sánh trong CI. Không duy trì ba danh sách thủ công mà không có contract test.

### 3.15 Bề mặt bảo mật đang thiếu theo mức ưu tiên

| Mức | Khoảng trống | Tác động |
|---|---|---|
| P0 | Shared `NovaX-auth-key` nằm trong app, assembly và server source | Có thể dump để giả login/connect/HMAC |
| P0 | App không verify RSA signature AUTH đã có ở server | Server giả sau khi patch pin/endpoint có thể tự tạo HMAC bằng secret bị dump |
| P0 | Assembly connect chỉ cần key + một app session còn sống, chưa có one-time app grant | App/script đã sửa có thể mở đường cho assembly giả |
| P0 | Sensitive request chưa có device private-key signature/anti-replay server-side | Token/HWID lấy từ runtime có thể bị tái sử dụng |
| P1 | Command server chỉ kiểm regex/Int32, chưa có allowlist type/range đầy đủ | State rác/giá trị ngoài UI có thể vào database và control plane |
| P1 | Legacy `.3105` download chỉ cần license key | Script có key tải được file |
| P1 | Native release raw download chỉ có hash/size | File không được bind theo device/session và chưa có signed manifest |
| P1 | Update config không pin và không có chữ ký | Có thể ép update URL nếu origin/config bị chiếm hoặc client bị sửa |
| P1 | Anti-tamper luôn fail-open và checksum assembly chỉ là checksum tự chế | Dễ patch/bypass, không tạo assurance cho server |
| P2 | Certificate pin là hash DER chain | Leaf/intermediate rotation dễ gây outage; cần SPKI primary + backup và runbook |
| P2 | License/AltIRK/trạng thái nằm trong `UserDefaults` | Dễ đọc/sửa; cần phân loại dữ liệu thay vì di chuyển mù quáng |
| P2 | `schemaError` có thể trả detail/stack cho admin | Tăng rò rỉ nội bộ nếu admin credential bị lộ |

---

## 4. Hợp đồng tương thích không được phá

1. Không thay `ExploitSupportPolicy` trong task anti-crack.
2. Không đổi FFI signature hoặc queue serialization của AirLift.
3. Không bỏ canary read-back.
4. Không chặn LocalDevVPN chỉ vì phát hiện VPN.
5. Không buộc Wi-Fi nếu loopback VPN/cellular vẫn chạy.
6. Không đổi bundle ID game ffth/ffmax.
7. Không đổi tên file admin upload.
8. Không ghi storage object key nội bộ xuống game.
9. Không đổi feature ID, state mapping, range/default hoặc revision semantics.
10. Không reset desired state khi assembly reconnect.
11. Không tắt chức năng ngay sau một timeout mạng ngắn.
12. Không xóa pairing record khi logout hoặc risk cao.
13. Không lưu raw token/private key vào log hoặc UserDefaults.
14. Không hardcode Team ID/certificate người dùng.
15. Không hash phần chữ ký/provisioning bị ESign/KSign thay đổi.
16. Không thay `PatchPackageCodec` schema, KDF, AAD, Keychain account hoặc package magic trong phase anti-crack.
17. Không bỏ journal/backup/digest/symlink/path validation của Direct transaction.
18. Không biến AirLift applied flag thành bằng chứng restore thành công; AirLift restore tùy ý hiện chưa có.
19. Không đổi API/UI của NextDNS hoặc coi DNS/VPN interface là proxy độc hại.
20. Không thay `AppReleaseDisplayVersion`, bundle game mapping hoặc artifact redirects trong cùng phase security.
21. Không để remote update URL mở scheme tùy ý; chỉ HTTPS và host allowlist đã ký.
22. Logout/revoke mới không được xóa pairing record, patch backup hoặc `.3105` content key.

---

## 5. Kiến trúc Anti-Crack v2

### 5.1 Gốc tin cậy phía server

Tạo cặp khóa ký production:

- Private key chỉ ở KMS/secret manager hoặc file ngoài repo với quyền tối thiểu.
- App/assembly chỉ giữ public key.
- Có key ID và public key dự phòng để rotation.
- Shared product secret không còn là authentication factor.

Server ký bất đối xứng các payload:

- App session response.
- Patch manifest.
- Remote security policy.
- Assembly connect response và lease.
- Command/desired-state envelope.
- Minimum supported protocol/build.

Thuật toán phải test trên Mono hiện tại. Ưu tiên RSA-PSS SHA-256; nếu runtime Mono không ổn định thì dùng RSA-3072 PKCS#1 v1.5 SHA-256. Canonical serialization phải cố định, không ký JSON phụ thuộc thứ tự key.

### 5.2 Device Identity không phụ thuộc signer

Thêm `DeviceIdentityService`:

- Ưu tiên sinh P-256 key trong Secure Enclave và kiểm tra capability thực tế sau khi IPA được ESign/KSign ký.
- Private key Secure Enclave không xuất ra ngoài.
- Dùng `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Không yêu cầu access group tùy chỉnh.
- Public key/fingerprint được bind với license, HWID và install ID.
- Private key chỉ dùng ký challenge/request.

Nếu Secure Enclave/Keychain operation không khả dụng với một signer được hỗ trợ, dùng P-256 software key được Keychain bảo vệ làm compatibility tier có `assurance_level` thấp hơn; không silently hạ cấp. Server policy có thể cho phép login/menu nhưng yêu cầu re-enroll hoặc giới hạn download theo rollout. Release gate phải ghi rõ signer nào đạt hardware-backed và signer nào chỉ đạt software-backed.

Enrollment:

1. App AUTH license theo flow hiện tại.
2. Server cấp challenge ngẫu nhiên có TTL.
3. App tạo/đọc Secure Enclave key và ký canonical enrollment payload.
4. Server verify signature, bind public key và trả enrollment receipt có chữ ký server.
5. Nếu đổi certificate làm mất key, app enrollment lại theo device limit thay vì crash.

Secure Enclave proof chứng minh request đến từ installation đã đăng ký, không chứng minh binary chưa bị sửa; vì vậy vẫn cần integrity/risk và server policy.

Server không nhận “integrity=true” do client tự khai là attestation. Measurement chỉ là telemetry/risk input. Với ESign/KSign, quyết định bảo vệ mạnh nhất vẫn là không phát hành asset/command nếu session, device proof, release protocol, grant và hành vi không đồng nhất.

### 5.3 Request Proof v2

Sensitive request thêm các trường:

```text
X-Astra-Protocol: 2
X-Astra-Device-Key: <device_key_id>
X-Astra-Session: <session_id>
X-Astra-Nonce: <128-bit random>
X-Astra-Timestamp: <unix-ms>
X-Astra-Counter: <monotonic counter>
X-Astra-Body-SHA256: <hex>
X-Astra-Signature: <base64>
```

Canonical message:

```text
ASTRA-REQ-V2
METHOD
NORMALIZED_PATH_AND_QUERY
BODY_SHA256
SESSION_ID
DEVICE_KEY_ID
NONCE
TIMESTAMP
COUNTER
```

Server phải xác minh device ownership, signature, nonce dùng một lần, timestamp window, counter tăng, method/path/body hash, session và variant.

Áp dụng cho login v2, menu, state, commands, cả ba loại patch download, assembly grant, refresh và logout. Nonce phải được consume atomically bằng unique constraint hoặc Redis `SET NX`.

Không dùng counter trong `UserDefaults` như nguồn duy nhất. Server giữ counter cao nhất; client lưu counter bền vững trong Keychain và có flow resync challenge khi Keychain mất do đổi signer. Hai request song song phải dùng counter được cấp phát tuần tự trong actor/serial queue, tránh tự tạo replay false-positive.

### 5.4 App session v2

Session bind với license, HWID, device key, install ID, protocol version, app release và risk level.

- Raw token trả một lần; server lưu hash.
- Access session ngắn hạn.
- Refresh cần device signature mới.
- Copy token sang máy khác không đủ vì thiếu private key.
- Logout/revoke hủy app session, pending grant và assembly session liên quan.
- `AuthManager.logout()` phải gọi revoke best-effort và luôn phát sự kiện local để `FeaturePatchService` xóa raw NovaX token/expiry trong RAM; không xóa pairing hoặc patch backup.

### 5.5 Signed response envelope

Response nhạy cảm dùng envelope gồm protocol, server key ID, request nonce, issued/expiry, payload hash, payload và signature.

Client phải verify signature, key ID, request nonce, payload hash, expiry, session, variant và revision. Khi route v2 đã enforce thì không được fallback sang response unsigned.

AUTH RSA hiện có không được tái sử dụng nguyên trạng nếu canonical payload chưa bind method/path/request nonce/device key. Có thể giữ key pair nếu quản trị khóa đạt chuẩn, nhưng phải version hóa payload và thêm `kid`; app phải thực sự chứa public key và verify.

### 5.6 Build integrity tương thích re-sign

Release manifest chỉ hash phần đã được thử nghiệm là không bị ESign/KSign thay đổi:

- Mach-O `__TEXT.__text` và executable sections đã kiểm chứng ổn định.
- Critical resources/framework hashes.
- Airlift FFI build identifier.
- App/SecurityCore version.

Không hash CodeDirectory, `LC_CODE_SIGNATURE`, provisioning profile, entitlements hoặc certificate chain người dùng.

Manifest được release key ký. Kết quả integrity là risk signal mạnh nhưng vẫn có thể bị patch; không dùng nó làm lý do crash tại launch.

Quy trình bắt buộc trước khi chọn section hash:

1. Build một IPA chuẩn.
2. Re-sign cùng IPA bằng từng profile ESign/KSign trong support matrix.
3. So sánh Mach-O load commands/segments và resource bytes sau re-sign.
4. Chỉ đưa vùng ổn định vào manifest; mọi khác biệt hợp lệ trở thành exclusion có lý do.
5. Chạy lại phép đo trên artifact đã cài, không chỉ file trước khi đóng IPA.

Nếu không chứng minh được `__TEXT.__text` giữ nguyên qua một tool/sign mode, phase đó chỉ chạy report-only cho tool/sign mode ấy.

### 5.7 Runtime Risk Engine

Thay boolean duy nhất bằng tín hiệu phân tán.

Tín hiệu thấp: jailbreak paths, instrumentation port, debug entitlement, signer khác test matrix.

Tín hiệu trung bình: debugger active, injected dylib/image, suspicious hook symbol, TLS trust mismatch, local state HMAC sai, resource phụ sai hash.

Tín hiệu cao: executable section mismatch, nhiều signal debugger/hook đồng thời, replay/counter rollback, device key hoạt động bất thường trên nhiều nơi.

Checkpoint:

- Launch: thu thập nhẹ, không block UI.
- Sau login: gửi signed risk summary.
- Trước NovaX session: có thể yêu cầu enrollment lại.
- Trước download/decrypt: chặn nếu risk cao.
- Trước command: yêu cầu session/device proof đúng.
- Foreground: refresh signal nhẹ.

Không polling nặng trên main thread, AirLift queue hoặc assembly render loop. Không hiển thị chi tiết signal cho client.

Policy:

| Risk | Hành động |
|---|---|
| Low | Cho chạy, log server-side |
| Medium | Session ngắn/rate limit chặt, có thể login lại |
| High | Từ chối download/command, revoke session tạm |
| Confirmed replay/abuse | Revoke device key, yêu cầu reset |

### 5.8 Network security

- Duy trì ATS và pinning cho mọi endpoint Astra.
- Chuyển dần sang SPKI primary + backup pin.
- Không có URLSession phụ bỏ qua pinning.
- Phát hiện explicit HTTP/HTTPS proxy và TLS interception.
- Không chặn generic VPN interface hoặc `10.7.x.x` LocalDevVPN.
- Offline/DNS timeout không được báo nhầm proxy.
- Assembly giữ HTTPS hiện tại; nếu Unity `WWW` không pin ổn định thì dựa thêm vào server signature ở payload, không đổi network stack cùng lúc.

Phân loại transport:

| Nhóm | Ví dụ | Chính sách |
|---|---|---|
| Sensitive Astra | AUTH, NovaX session/menu/state/command/download/grant | Pinned session + request proof + signed response |
| Public nhưng điều khiển app | minimum version, update URL, security policy, NextDNS ID | Signed response; update URL allowlist; pin host Astra |
| Public content | guides, images/video, likes | ATS/rate limit; không bắt device proof đọc nội dung |
| AirLift local | `10.7.0.1`, RSD/AFC/AirTraffic | Không đi qua proxy/TLS guard internet; giữ timeout/queue/canary riêng |
| Third party DNS | NextDNS test/DoH | Không dùng pin zynox.click và không bị anti-proxy chặn nhầm |

### 5.9 Codepatch protection v2

Giữ AES-256-GCM/HKDF hiện tại và bổ sung:

1. Download request cần device signature.
2. Server kiểm tra session/device/release/risk.
3. Signed manifest chứa release, variant, kind, original filename, SHA-256, length, format, session, device, issued/expiry và download ID.
4. Protocol mới bind AAD với variant, kind, hash, session và download ID.
5. Tên file lấy từ signed manifest/header đã validate.
6. File tạm dùng complete protection và luôn xóa.
7. Không cache plaintext lâu dài.
8. Audit download theo license/device/release/result.

Không tự đổi tên file, không dùng storage key làm tên game, không giải mã trước khi verify tag/signature và không thay destination logic.

### 5.9.1 Native release `.3105` v2

- Download phải cần request proof như codepatch.
- Server trả signed manifest chứa release ID/version, variant, package SHA-256/size, package schema, target app set và build compatibility.
- Mã hóa response theo session/device bằng AES-GCM hoặc đóng gói qua cùng download envelope v2; không dựa vào việc `.3105` “trông đã mã hóa”, vì package public hiện có thể mang content key.
- Sau giải mã vẫn bắt buộc chạy `PatchPackageCodec.inspect/decode/validate`; không bypass package checks.
- Direct vẫn dùng `DevicePatchService.apply`; AirLift vẫn dùng `StorageEngineCoordinator.applyPatchProject`.

### 5.9.2 Legacy catalog migration

- Đóng băng tạo patch legacy mới; inventory xem UI/route nào còn dùng thật.
- Bọc `/api/ff/sync` và `/api/ff/download/:slug` bằng session/device proof v2 trước khi tắt.
- Không dùng license key làm HMAC signing key cho server authenticity.
- Metadata cache chỉ được dùng offline sau khi verify signed manifest và còn TTL; cache cũ không có chữ ký chỉ dùng trong compatibility phase.
- Khi usage về 0 qua telemetry và release đã migrate, tắt route download legacy. Không xóa package/journal đã tải trên máy người dùng.

### 5.9.3 Update/config signing

- Tách `latest_ios_version`, `update_url`, `nextdns_config_id` thành payload có schema/version/issued/expiry.
- Server ký payload; app verify bằng release public key.
- `update_url` chỉ chấp nhận `https`, host allowlist và không chứa credential/userinfo.
- Nếu signature/config lỗi, giữ phiên bản app hiện tại và hiển thị lỗi kiểm tra cập nhật khi người dùng yêu cầu; không khóa app bằng config unsigned.

### 5.10 App-to-Assembly Grant

Đây là lớp chặn script chỉ có key.

1. App tạo device-signed NovaX session.
2. Khi login/inject, app xin assembly grant theo variant.
3. Grant bind license, device key, app session, variant, patch release/hash và TTL.
4. Assembly connect bằng key/variant như hiện tại.
5. Server chỉ connect khi có pending grant hợp lệ và consume grant trong transaction.

Giai đoạn đầu server tự tìm pending grant để không đổi UI assembly. Giai đoạn sau assembly v2 có thể gửi `grant_id` hoặc đọc sidecar ticket, nhưng chỉ sau khi chứng minh sidecar không ảnh hưởng game/AirLift. Không patch byte tùy ý vào artifact nếu chưa có metadata region được thiết kế trước.

### 5.11 Assembly protocol v2

Giữ nguyên feature/state mapping; chỉ thay bootstrap và verification.

- Route mới `/api/v2/assembly/connect`.
- Kiểm tra pending grant, variant và patch version allowlist.
- Response có server signature và signed lease.
- Lease bind assembly session, license, variant, patch release, revision và `not_after`.
- Checksum local hiện tại chỉ còn là anti-corruption phụ.
- Poll giữ nonce, AES-CBC/HMAC actual/desired state và revision.
- Outer envelope có server signature, bind request nonce/session/variant/revision.
- Reject revision rollback và feature ngoài allowlist.
- Value tiếp tục clamp cả server lẫn assembly.

Mất mạng: giữ state trong grace period cấu hình, không tắt sau timeout đơn lẻ; sau khi lease hết hạn hoàn toàn mới chuyển trạng thái an toàn. Signed logout mới được reset session; response unsigned không được mutate hoặc ép logout.

### 5.12 Local secure storage

- Đọc license từ Keychain trước.
- Nếu chưa có thì migrate một lần từ `UserDefaults`.
- Chỉ xóa bản cũ sau khi Keychain save thành công.
- Keychain lưu license, device key reference, device key ID, enrollment receipt, install ID.
- Không lưu raw app/assembly token, AES key hoặc decrypted patch lâu dài.
- Pairing file giữ nguyên path/format/protection và không gắn với AUTH logout.

### 5.13 Obfuscation có kiểm soát

Tạo `SecurityCore` chứa device signing, canonical request, server signature verify, integrity measurement và risk state machine.

App chỉ obfuscate SecurityCore:

- Strip local symbols, không đóng gói dSYM trong IPA.
- Per-build string seed cho route/header/security labels.
- Constant splitting, indirect calls và control-flow transform có giới hạn.
- Không đổi symbol dùng reflection/@objc.

Không obfuscate toàn bộ SwiftUI, model, AirLift manager hoặc patch transaction trong lần đầu.

Assembly chỉ obfuscate endpoint decoder, signature verifier, session/lease state và connect/poll builder. Không đổi Unity lifecycle/hook, InjectFix binding, reflected members, template placeholders, feature dispatch hoặc serialization keys.

### 5.14 Server hardening

- Private key/credential chỉ qua secret manager/environment.
- Không commit `.env`, private key hoặc database backup.
- Duy trì Cloudflare origin guard và firewall origin.
- Rate limit theo IP, license, device key, route, session và risk.
- Giới hạn connect/download đồng thời.
- Audit enroll, refresh, grant, download, command, assembly connect/poll và revoke.
- Không trả stack trace, storage path hoặc lỗi database thô.
- Có revocation theo license, device, session, release và signing key ID.
- Có rotation runbook cho signing key, TLS pin và hạ tầng credential.
- Di chuyển `PRODUCT_SECRET` literal ra environment/secret manager trong compatibility phase, rồi loại bỏ vai trò authentication sau v2; không chỉ đổi sang một chuỗi nhúng mới.
- Feature manifest phía server là nguồn validate command: ID, type, min/max/default, variant, release và luật mutual exclusion. Regex chỉ là lớp syntax đầu tiên.
- `client_command_id` có unique/idempotency scope theo app session để retry không tạo revision/queue trùng.

---

## 6. Luồng hoàn chỉnh đề xuất

### Login lần đầu

```text
Nhập license
→ AUTH license
→ server challenge
→ app tạo Secure Enclave key và ký
→ server bind public key
→ app gửi login v2 có nonce/counter/signature
→ server cấp session bind device key
→ app verify server signature
```

### Mở app lại

```text
Đọc license/device key từ Keychain
→ thu thập risk nhẹ
→ signed refresh request
→ server verify counter/nonce/device
→ khôi phục session
```

Nếu khóa mất do đổi signer, app enrollment lại thay vì dùng session cũ.

### Inject

```text
Kiểm tra iOS policy
→ nếu AirLift: VPN + pairing + health
→ security checkpoint trước download
→ chọn đúng flow: codepatch / native .3105 / legacy compatibility
→ device-signed download + verify signed manifest
→ giải mã envelope tương ứng + length/hash/package verify
→ resolve Direct/AirLift destination
→ codepatch: ghi đúng original filename
→ .3105: giữ nguyên transaction hoặc AirLift batching
→ chỉ sau write/apply thành công mới tạo/refresh pending assembly grant
```

Không tạo grant nếu download/decrypt/write thất bại. Với patch đã inject từ trước, app có thể tạo lại grant khi người dùng mở Astra và session v2 vừa được chứng minh; grant phải bind release hash đang active, variant và TTL ngắn, không dựa vào cờ `UserDefaults` đơn lẻ.

### Assembly control

```text
Assembly nhập key
→ connect bằng key + variant + patch version + nonce
→ server consume pending grant
→ trả signed lease + encrypted desired state
→ assembly verify signature/lease
→ poll encrypted actual state
→ server trả signed + encrypted command/state
→ assembly verify nonce/MAC/signature/revision
→ single mutation gateway áp dụng feature
```

---

## 7. Database/API schema đề xuất

### `novax_device_keys`

```text
id, key_id, hwid, install_id
public_key, public_key_fingerprint, assurance_level
last_counter, created_at, last_seen_at, revoked_at
```

### `novax_request_nonces`

```text
nonce_hash, device_key_id, expires_at, used_at
```

### `novax_app_sessions_v2`

```text
id, key_id, device_key_id, token_hash
protocol_version, app_release_id, risk_level
created_at, last_seen_at, expires_at, revoked_at
```

### `novax_assembly_grants`

```text
id, key_id, device_key_id, app_session_id
variant, patch_release_id, patch_sha256
created_at, expires_at, consumed_at, assembly_session_id
```

### `novax_security_events`

```text
id, key_id, device_key_id, session_id
event_type, risk_score, release_id, ip_address
metadata, created_at
```

Metadata không được chứa raw token, private key, full license hoặc plaintext patch.

### `novax_release_manifests`

```text
id, release_type, release_id, variant, protocol_version
sha256, size, schema_version, original_filename
minimum_app_build, minimum_assembly_build
server_key_id, signature, issued_at, expires_at, revoked_at
```

### Ràng buộc database bắt buộc

- Unique `(device_key_id, nonce_hash)` và consume nonce trong transaction.
- Counter update dùng compare-and-swap hoặc stored procedure có lock; không read-then-write rời rạc.
- Chỉ một app session active theo policy; revoke session cũ và grant/assembly child trong cùng transaction hoặc job bù có idempotency.
- Grant consume một lần bằng `UPDATE ... WHERE consumed_at IS NULL AND expires_at > now()` và kiểm tra đúng một row.
- Audit/download counter không nằm trên critical path nếu lỗi logging; authorization và consume nonce/grant phải nằm trên critical path.
- Desired state có foreign key/constraint tới feature manifest theo protocol/release; không chỉ regex feature ID.

---

## 8. Kế hoạch triển khai theo giai đoạn

### Giai đoạn 0 — Đóng băng baseline

Mục tiêu: có bằng chứng chức năng trước khi sửa security.

- Tag app, server và assembly artifact đang chạy ổn định.
- Ghi SHA-256 artifact và API schema v1.
- Lưu danh sách feature ID, type, default và range.
- Tạo ba fixture riêng cho legacy `.3105`, native `.3105` và codepatch mod/original.
- Xuất feature contract từ app và assembly; bổ sung server allowlist/range ở chế độ report-only trước.
- Sửa regression test assembly đã lỗi thời.
- Thêm golden fixtures cho login/connect/poll/menu/state/command/codepatch headers.
- Không thay behavior production.

Gate:

- AirLift static verifier pass.
- Assembly project tests pass.
- Control-channel test pass.
- Server security tests pass.
- Có test thiết bị Direct và AirLift.

### Giai đoạn 1 — Server signature v2 ở shadow mode

- Kiểm kê RSA key AUTH hiện có; tạo/rotate release signing key ngoài repo và thêm `kid`.
- Trả signed envelope cùng field v1/HMAC cũ.
- App verify chữ ký AUTH/update/config ở shadow mode nhưng production chưa block.
- Assembly production chưa bắt buộc v2.
- Test client ghi nhận tỷ lệ verify thành công.
- Không tắt route v1.

Rollback: tắt shadow v2 bằng server feature flag.

### Giai đoạn 2 — Device Identity và Keychain migration

- Thêm `DeviceIdentityService`.
- Thêm enrollment challenge/verify APIs.
- Migrate license sang Keychain theo kiểu copy-verify-delete.
- Request v2 chạy song song, server chỉ quan sát.
- Integrity/risk chạy report-only.
- Không sửa AirLift/write logic.

Rollback: app dùng AUTH/session v1; license trong Keychain vẫn dùng được.

### Giai đoạn 3 — Enforce request proof

Bật lần lượt:

1. Commands.
2. Codepatch download.
3. Native `.3105` download.
4. Legacy `.3105` download còn active.
5. Menu/state.
6. Session refresh/logout.

Không bật tất cả trong một lần. Theo dõi false positive theo iOS, ESign/KSign, certificate và network transition.

Rollback: cho protocol v1 theo allowlist build và thời hạn cụ thể.

### Giai đoạn 4 — Assembly grant

- App tạo pending grant chỉ sau write/apply thành công; patch đã inject có flow refresh grant bằng session proof và release manifest.
- Connect server yêu cầu grant hợp lệ.
- Chưa đổi state schema/poll crypto.
- Theo dõi connect failure, retry và CPU.
- Không dùng strict IP match.

Rollback: cho assembly build v1 qua compatibility policy có thời hạn.

### Giai đoạn 5 — Assembly signature và lease v2

- Build assembly v2 có public key server.
- Verify signed connect/lease/poll envelope.
- Duy trì AES/HMAC payload hiện tại.
- Bật grace period mất mạng.
- Phát hành patch release mới.

Rollback: chuyển active release về artifact v1 và mở compatibility route có thời hạn.

### Giai đoạn 6 — Integrity enforcement

- Chạy report-only ít nhất một chu kỳ release.
- Đo false positive ESign/KSign/direct/AirLift.
- Chỉ hard-block download/command khi risk cao.
- Không crash app, không xóa pairing.

### Giai đoạn 7 — Obfuscation

- Obfuscate SecurityCore trước.
- Build/test sau từng pass.
- Obfuscate assembly transport riêng, không gộp với thay protocol.
- Dùng string/constant seed khác cho mỗi release.

### Giai đoạn 8 — Tắt v1 và rotate secret cũ

- Đặt minimum app/assembly protocol.
- Revoke session v1.
- Tắt route connect/NovaX v1 sau migration.
- Shared product secret cũ không còn vai trò auth.
- Giữ runbook rollback đã kiểm thử.
- Tắt legacy download chỉ sau khi telemetry chứng minh không còn client hợp lệ sử dụng.

---

## 9. Danh sách file/module dự kiến thay đổi

| Thành phần | File/module | Phạm vi |
|---|---|---|
| App | `views/SecurityUtils.swift` | Keychain migration, SPKI/public-key utilities |
| App | `helpers/AntiTamper.swift` | Risk facade, không chứa một điểm bypass duy nhất |
| App | `helpers/DeviceIdentityService.swift` mới | Secure Enclave enrollment/signing |
| App | `helpers/RequestProofService.swift` mới | Canonical request và headers v2 |
| App | `helpers/ServerSignatureVerifier.swift` mới | Verify envelope/manifest |
| App | `helpers/SignedConfigService.swift` mới | Update/security/NextDNS config có chữ ký và URL allowlist |
| App | `helpers/IntegrityMonitor.swift` mới | Mach-O/resource measurements |
| App | `views/AuthManager.swift` | Enrollment/session v2, license migration |
| App | `helpers/FeaturePatchService.swift` | Bọc cả ba download flow bằng request v2/manifest; giữ write/restore logic |
| App | `helpers/StorageEngineCoordinator.swift` | Không đổi routing; chỉ thêm hook test/telemetry ngoài FFI queue nếu cần |
| App | `helpers/PatchPackageCodec.swift` | Không đổi schema/crypto trong rollout; chỉ bổ sung fixture và contract test |
| App | `helpers/PatchTransaction.swift` | Không đổi transaction; bổ sung regression test journal/restore |
| App | `helpers/Utils.swift` | Update checker chuyển sang signed config transport |
| App | `helpers/NextDNSManager.swift` | Chỉ đọc signed public config; không đổi NetworkExtension/DNS behavior |
| App | `App.swift` | Checkpoint nhẹ; không hard-block launch |
| Server | Module route v2 mới | Session, request proof, grant, signed response |
| Server | SQL migration mới | Device keys, nonce/counter, grant, risk/audit |
| Server | Secret/KMS config | Private signing key |
| Server | Feature contract module mới | Allowlist ID/type/range/default theo release/variant |
| Assembly | `src/ESPLogic.template.cs` | Verify server signature/lease, v2 connect/poll |
| Assembly | Build scripts/tests | Public key injection và regression verification |

Khuyến nghị tách route v2 sang module mới thay vì tiếp tục làm lớn `novax_control.js`. Module v1 chỉ nhận critical fix trong thời gian migration.

---

## 10. Ma trận kiểm thử bắt buộc

### 10.1 App/AUTH

- Login key mới, restore session, logout/login lại.
- Key expired, banned, invalid hoặc sai device.
- Offline, timeout, DNS lỗi và quay lại mạng.
- Chuyển Wi-Fi/4G giữa phiên.
- Cài đè cùng certificate.
- Cài đè bằng certificate khác.
- Xóa app/cài lại.
- ESign và KSign với ít nhất hai loại certificate.
- Keychain migration thành công/thất bại giữa chừng.
- Secure Enclave key mất hoặc không khả dụng.
- Hardware-backed và software-backed fallback được báo đúng assurance, không silently downgrade.
- AUTH RSA/signed envelope: đúng, sai key ID, sai nonce, sai timestamp, payload bị sửa.
- Logout xóa session token RAM và revoke server nhưng giữ pairing/package key/backup.
- Update config signature/expiry/host/scheme allowlist.

### 10.2 iOS storage matrix

- iOS 16.x direct inject/uninject.
- iOS 17.x direct inject/uninject.
- iOS 18.7.1 direct.
- iOS 18.7.2–18.8.x imported pairing AirLift.
- iOS 26.6.1 direct.
- iOS 26.6.2/26.7 imported pairing AirLift.
- iOS 27.0/27.1 on-device và imported pairing.
- iOS 27.2 allowlisted build.
- Unsupported build báo đúng và không khởi động pairing/patch.

### 10.3 AirLift

- LocalDevVPN bật/tắt và tunnel IP hợp lệ.
- Pairing file hợp lệ, sai hoặc revoked.
- Pair trực tiếp trên build hỗ trợ.
- RSD timeout, AFC/container resolve.
- Canary write/read-back bắt buộc.
- Write timeout và retry.
- Security checks không chạy trong FFI queue.
- Proxy guard không chặn LocalDevVPN.

### 10.4 Codepatch

- Upload tên ASCII và Unicode/Vietnamese.
- Tên có `~`, `+`, `=` hợp lệ.
- Reject slash, backslash, control character, traversal.
- App nhận đúng tên admin upload.
- SHA-256, length và GCM tag đúng.
- GCM tag sai bị reject trước write.
- Server manifest signature sai bị reject.
- Ciphertext của session A không dùng được ở session B.
- File tạm xóa cả khi thành công và thất bại.
- MOD/ORIGINAL cho ffth và ffmax.
- Direct và AirLift cùng ghi đúng filename.

### 10.4.1 Native và legacy `.3105`

- Native release đúng/sai signed manifest, hash, size, schema và variant.
- Ciphertext native session A không dùng được với session/device B.
- `PatchPackageCodec` v1/v2/v3 compatibility, public/password/private package.
- Password đúng/sai, Keychain cached content key và signer-change recovery.
- Path traversal, duplicate target, symlink, target occupied và invalid bundle bị reject.
- Direct apply tạo journal/backup; rollback khi write giữa chừng; restore file đã thay đổi theo policy hiện tại.
- Atomic write giữ permissions/file protection cần thiết.
- AirLift batch theo bundle/directory, canary bắt buộc và không báo restore giả.
- Legacy key-only script bị chặn khi v2 enforcement bật; compatibility allowlist có expiry.

### 10.5 Assembly chức năng

- Menu nhập key luôn hiển thị khi chưa auth.
- Connect thành công khi app/grant hợp lệ.
- Script chỉ có key bị từ chối.
- Desired state khôi phục sau reconnect.
- Revision không rollback.
- Toggle/range toàn bộ feature.
- Aim silent/system mutual exclusion.
- Aim target/head/body mapping giữ nguyên.
- Mod reset/settings restore.
- Actual state gửi lại server đúng.
- Mạng gián đoạn ngắn không reset ngay.
- Lease hết hạn chuyển trạng thái an toàn.
- MAC/signature sai không mutate state.
- Reconnect không gây retry loop/CPU cao.
- Đủ 41 app feature và 6 mod command; unknown ID/range ngoài manifest bị server reject.
- Bốn redirect, bindings, dump hash, artifact hash và release signature khớp manifest.

### 10.6 Security/adversarial

- Sửa endpoint trong IPA.
- Thay public key embedded.
- Bỏ certificate pinning.
- Patch anti-tamper return value.
- Patch executable section.
- Load dylib/instrumentation.
- Debugger attach.
- Replay nguyên request.
- Replay session token trên máy khác.
- Counter rollback.
- Hai request cùng nonce chạy đồng thời.
- Script có key nhưng không có private key.
- Fake server trả manifest/command tự ký.
- Sửa assembly bỏ menu AUTH.
- Assembly version không allowlist.
- Copy pending grant hoặc dùng grant lần hai.
- Dùng modified IPA có cùng Keychain access nhưng executable hash khác.
- Giả `integrity=true` trong request; server không coi boolean client là attestation.
- Dùng AUTH RSA signature cũ cho path/body/nonce khác.
- Gọi legacy sync/download chỉ bằng key sau ngày enforcement.
- Sửa public config để trỏ update sang `http`, custom scheme hoặc host ngoài allowlist.

### 10.7 Performance/ổn định

- Startup không tăng bất thường.
- Không anti-tamper loop trên main thread.
- Không tăng CPU assembly do retry.
- Không tăng poll rate khi server lỗi.
- Không deadlock AirLift queue.
- Không giữ plaintext/file lớn lâu hơn hiện tại.
- Không treo UI khi Keychain/Secure Enclave lỗi.

---

## 11. Release gates

Một phase chỉ được production khi:

1. Release build thành công.
2. Static verifier pass.
3. Server unit/security tests pass.
4. Assembly project/control tests pass.
5. Test thiết bị Direct pass.
6. Test thiết bị AirLift pass.
7. ESign install/update pass.
8. KSign install/update pass.
9. Certificate-change recovery pass.
10. Codepatch giữ đúng filename.
11. Feature IDs/state mapping không đổi.
12. Rollback flag tồn tại và đã test.

Không kết luận “100% an toàn” chỉ từ grep, static test hoặc build pass. Xác nhận cuối phải có device test và adversarial test trên IPA release thật.

---

## 12. Rollback và feature flags

Các flag tối thiểu:

```text
security_v2_shadow
device_proof_required_commands
device_proof_required_download
assembly_grant_required
assembly_signature_v2_required
integrity_enforcement_level
minimum_app_protocol
minimum_assembly_protocol
offline_lease_grace_seconds
```

Yêu cầu:

- Flag policy được server ký.
- Client không tự hạ minimum protocol bằng local storage.
- Dashboard xem được reject reason server-side.
- Rollback một lớp không vô hiệu hóa toàn AUTH.
- Không rollback bằng cách chấp nhận response unsigned.
- Route v1 chỉ mở theo build allowlist/thời hạn.

---

## 13. Những cách không được sử dụng

1. Chỉ obfuscate URL rồi coi endpoint là bí mật.
2. Nhúng một shared secret mới trong app/assembly.
3. Hard-block chỉ vì một file jailbreak.
4. Chặn mọi VPN và làm LocalDevVPN hỏng.
5. Buộc Team ID cố định với ESign/KSign.
6. Hash toàn IPA sau ký rồi mong re-sign giữ nguyên.
7. Dùng strict IP match app–assembly.
8. Crash/`exit()` ngay tại launch khi nghi ngờ.
9. Anti-debug polling tần suất cao.
10. Obfuscate toàn SwiftUI/AirLift/Unity binding trong một lần.
11. Dùng checksum local đơn giản làm bằng chứng AUTH.
12. Trả private key/signing secret xuống client.
13. Ghi raw token/license/private data vào log.
14. Đổi tên codepatch admin upload.
15. Enforce trước khi có report-only telemetry và rollback.

---

## 14. Tiêu chí hoàn thành

- ESign/KSign cài và update bình thường.
- Direct/AirLift đúng bảng iOS.
- Pairing và LocalDevVPN không bị chặn nhầm.
- License ở Keychain.
- Mỗi installation có private key không xuất được.
- Sensitive API v2 yêu cầu signed request và chống replay.
- Server response/manifest/command dùng asymmetric signature.
- Script chỉ có key không download được patch.
- Assembly connect cần pending app grant.
- Assembly verify signed lease/command envelope.
- AES-GCM codepatch và tên file thật giữ nguyên.
- Feature IDs/state/revision không đổi.
- Risk engine có false-positive policy và kill switch.
- Obfuscation chỉ áp dụng vùng có regression test.
- Private signing key không nằm trong repo.
- Protocol v1 bị tắt sau migration.
- Có device/adversarial report cho release IPA.

---

## 15. Baseline tại thời điểm lập kế hoạch

- NovaX tracked files không có thay đổi trước khi tạo tài liệu; có một số script scratch untracked tồn tại từ trước.
- Static verifier AirLift hiện tại pass toàn bộ tiêu chí mà script kiểm tra.
- `tools/test_project.py` của assembly chạy 15 test và pass.
- `tools/test_control_channel.py` đang lỗi thời vì còn tìm chuỗi cũ `return "auth-menu"`; phải sửa trước khi dùng làm release gate.
- Windows hiện tại không build được Xcode/iOS và không thay thế device test.
- Node/npm không có trong PATH lúc khảo sát; server test phải chạy lại trong CI/VPS hoặc máy có Node.

---

## 16. Thứ tự triển khai khuyến nghị

```text
Baseline tests
→ Server asymmetric signing shadow mode
→ Secure Enclave device identity
→ Request proof v2 report-only
→ Enforce command/download proof
→ App-to-assembly pending grant
→ Assembly signed lease v2
→ Integrity enforcement theo risk
→ Obfuscate SecurityCore/assembly transport
→ Tắt protocol v1 và rotate secret cũ
```

Thứ tự này bảo vệ server/giao thức trước rồi mới tăng anti-tamper local và obfuscation. Mỗi phase độc lập, có flag, rollback và bằng chứng Direct/AirLift/assembly trước khi chuyển phase tiếp theo.

---

## 17. Phụ lục hợp đồng baseline đã đối chiếu

### 17.1 Endpoint theo mức tin cậy

| Endpoint hiện tại | Caller | Trạng thái bảo vệ hiện tại | Đích v2 |
|---|---|---|---|
| `/api/verify` | App AUTH | TLS pin + shared-secret HMAC; RSA server tạo nhưng app chưa verify | Device enrollment/proof + signed response bind nonce/path/body |
| `/api/novax/login` | App | Key + HWID + product secret, HMAC response | Device-signed login/refresh, token bind device key |
| `/api/novax/menu/:variant` | App | Bearer + key + HWID | Signed request/response, release/feature manifest |
| `/api/novax/state/:variant` | App | Bearer + key + HWID | Signed request/response, monotonic revision |
| `/api/novax/commands` | App | Bearer + key + HWID; feature validation chưa có strict manifest/range | Device proof + strict feature contract + idempotency |
| `/api/novax/patches/:id/download` | App | Bearer + SHA-256/size | Device proof + per-session encryption + signed native manifest |
| `/api/novax/codepatch/:variant/:kind/download` | App | Bearer + AES-GCM/HKDF/session + hash/length/name | Giữ crypto; thêm device proof + signed manifest/download ID |
| `/api/ff/sync` và `/api/ff/download/:slug` | App legacy | Key-only; metadata HMAC bằng license | Bọc v2 rồi deprecate có telemetry |
| `/api/assembly/connect` | Assembly | Key + shared secret + nonce + active app session; HMAC shared secret | One-time app grant + signed lease + release allowlist |
| `/api/assembly/poll` | Assembly | Session-derived AES-CBC/HMAC, nonce, revision | Giữ inner crypto + signed outer envelope/lease |
| `/api/client/config` | App update/NextDNS | Public, một số caller dùng `URLSession.shared` | Signed config, pin host Astra, tách policy/update/DNS |
| `/api/client/guides` | App | Public ATS | Public content; sanitize/deep-link policy, không cần device proof đọc |

Admin endpoints không được dùng public request-proof của app. Chúng tiếp tục có admin auth riêng, CSRF/origin/rate-limit/audit và không trả stack/storage path ra client.

### 17.2 Feature contract 41 mục của app

| Nhóm | ID | Type/range/default |
|---|---|---|
| ESP | `esp.master`, `esp.box`, `esp.tracer`, `esp.health`, `esp.name`, `esp.distance`, `esp.fov`, `esp.skeleton`, `esp.enemy`, `esp.arrows` | toggle |
| ESP | `esp.fovRadius` | range 0–31, default 0 |
| ESP | `esp.lineOrigin` | select 0–2, default 0 |
| Aim | `aim.silent`, `aim.system`, `aim.legit`, `aim.sniper` | toggle |
| Aim | `aim.systemHead` | select 0–1, default 0 |
| Aim | `aim.target` | select 0–2, default 0 |
| Aim | `aim.headRate` | select 0–4, default 0 |
| Khác | `misc.backJump`, `misc.fastSwitch`, `misc.speed`, `misc.vision`, `misc.spin`, `misc.buff`, `misc.sensitivity`, `misc.fps`, `misc.skill`, `misc.ammo`, `misc.damage` | toggle |
| Khác | `misc.speedLevel` | range 0–19, default 5 |
| Khác | `misc.visionLevel` | range 1–20, default 10 |
| Khác | `misc.spinLevel` | range 1–15, default 5 |
| Màu | `damage.criticalColor` | color 0–10, default 2 |
| Màu | `damage.normalColor` | color 0–10, default 10 |
| Màu | `damage.iconColor` | color 0–10, default 6 |
| Màu | `colors.fov`, `colors.line`, `colors.box`, `colors.skeleton` | color 0–10, default 1 |
| Hệ thống | `settings.restore` | toggle/action |

Assembly có thêm `mod.hair`, `mod.top`, `mod.bottom`, `mod.shoes`, `mod.face`, `mod.reset`. Server v2 phải reject mọi ID không thuộc manifest release, clamp đúng range và giữ luật mutual exclusion `aim.silent`/`aim.system`.

### 17.3 Artifact assembly baseline

- Artifact hiện có: `dist/Assembly-CSharp-patch.bytes`.
- Kích thước tại lần rà soát: 236376 byte.
- SHA-256 trong manifest: `77BB033F0545B3A05A80CF954FE6228D26C19198407F179BA65D44124B281C4B`.
- Target game manifest: FFTH, game `1.132.1`, assembly `0.86.0.518`.
- Redirect count: 4; VM instructions: 25174; exception handlers: 154.
- Manifest hiện là JSON không ký. Khi build lại hoặc đổi variant/release, không dùng các số trên như allowlist vĩnh viễn; CI phải sinh manifest mới, ký và publish theo release.

### 17.4 Dữ liệu không được nhầm là bí mật

- Endpoint, bundle ID, codepatch destination và feature ID cuối cùng đều có thể xuất hiện trong runtime; obfuscation chỉ giảm khả năng grep tĩnh.
- HWID hiện tại là hash của IDFV + model + bundle ID và được cache; nó là identifier, không phải cryptographic proof.
- SHA-256 artifact/file xác nhận nội dung, không xác nhận người phát hành nếu hash/manifest không có chữ ký bất đối xứng.
- AES/HMAC bằng key suy ra từ token bảo vệ trên đường truyền, nhưng người chiếm runtime client vẫn có thể lấy plaintext/token.
- Filename codepatch không phải secret; mục tiêu là giữ đúng tên và không lộ storage path nội bộ.

## 18. Tài liệu chuẩn tham chiếu

- OWASP MASVS Resilience: <https://mas.owasp.org/MASVS/11-MASVS-RESILIENCE/>
- OWASP iOS source-code integrity: <https://mas.owasp.org/MASTG/best-practices/MASTG-BEST-0067/>
- OWASP iOS storage integrity: <https://mas.owasp.org/MASTG/best-practices/MASTG-BEST-0065/>
- OWASP iOS anti-debugging: <https://mas.owasp.org/MASTG/best-practices/MASTG-BEST-0074/>
- OWASP iOS device binding: <https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0090/>
- OWASP iOS server trust/pinning: <https://mas.owasp.org/MASTG-KNOW-0072/>
- Apple Secure Enclave key protection: <https://developer.apple.com/documentation/Security/protecting-keys-with-the-secure-enclave>

Các tài liệu này được dùng làm chuẩn định hướng. Thiết kế Astra vẫn phải ưu tiên ràng buộc ESign/KSign, compatibility với Mono assembly và kiểm thử thực tế của Direct/AirLift.
