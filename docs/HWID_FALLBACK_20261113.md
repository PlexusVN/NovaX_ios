# HWID dự phòng ổn định khi IDFV hoặc bản lưu gốc không dùng được

## Vấn đề

Ảnh HW05-DATA cho biết không còn UUID hợp lệ trong các bản public HWID mà app
đọc được. Nó không xác định bytes nào đã hỏng. iOS không trả IDFV trong bản cài
mới là một trường hợp khác: trước thay đổi này app báo HW04 và chờ đọc lại.

HWID gửi tới server là identifier của ứng dụng, không phải serial phần cứng.
Trường HWID của server nhận chuỗi opaque tối đa 255 byte; installation/device
IDs và hai khóa P-256 là các định danh riêng. Không thay private keys hoặc bỏ
kiểm tra license/session/proof để tạo HWID dự phòng.

## Hành vi mới

1. UUID đã lưu hợp lệ vẫn được dùng nguyên cách viết/case như trước; một bản
   hợp lệ đủ để tiếp tục khi bản kia hỏng. Không đoán hash/URN/braces là UUID.
2. Fallback riêng dùng Keychain tag `deviceHwidFallbackV1` và file public
   `Application Support/AstraDeviceIdentity/hwid-fallback-v1`.
3. Khi các kho đọc được trạng thái, không có định danh dùng được và fallback
   chưa tồn tại, app tạo `ASTRA-HWID-v1-<UUID>` một lần. Trường hợp này gồm IDFV
   chưa có ở bản cài mới hoặc bản HWID gốc đã hỏng.
4. Chỉ trả fallback sau khi lưu và đọc lại hợp lệ ít nhất một bản. Mọi lần mở
   lại/retry dùng lại đúng chuỗi đã lưu, kể cả IDFV có lại hoặc thay đổi.
5. Bản gốc `deviceHwid`/`hwid-v1` bị hỏng được giữ nguyên. Fallback không ghi đè
   các bản đó, không xóa backup và không thay khóa bảo mật.
6. Lỗi đọc Keychain/file không được hiểu thành trạng thái chưa có dữ liệu để
   tạo thêm identity. Bản đã xác minh còn dùng được vẫn được giữ.
7. Hai bản hợp lệ khác nhau, hoặc UUID gốc hợp lệ xuất hiện lại sau khi fallback
   đã được công bố, báo conflict thay vì tự chuyển thiết bị. Fallback hỏng
   không bị tạo lại liên tục.

File fallback dùng Data Protection và excluded-from-backup như public HWID mirror
hiện có. Đây là identifier bền vững theo các bản lưu còn truy cập được; không
bảo đảm bất biến khi gỡ app, xóa container hoặc đổi cấu hình ký khiến mất toàn
bộ kho lưu. `NSLock` tuần tự hóa app process, không phải cam kết CAS Keychain
giữa nhiều process.

## Giới hạn liên kết server

Nếu raw HWID đã đăng ký trên server mất hoàn toàn, fallback mới không thể tính
ngược lại giá trị đó. Server vẫn kiểm slot thiết bị, exact HWID và P-256 identity
như trước. Khách hàng có liên kết cũ có thể cần admin cấp lại quyền/liên kết
thiết bị theo quy trình hiện hành. Không tự xóa row, reset slot hoặc revive
identity đã bị thu hồi. Việc local HW05 hết không đồng nghĩa quyền tải bảo mật
trên server đã được thay đổi.

## Phạm vi source

- `views/SecurityUtils.swift`: policy HWID, kho mirror riêng và wiring fallback.
- `views/AuthManager.swift`: đúng một dòng fast path dùng `isUsable`, chấp nhận
  UUID gốc hoặc fallback do Astra tạo, giữ nguyên luồng login còn lại.
- `Tests/StableHWIDSelfCheck.swift`, `Tests/test_stable_hwid.py`: regression cases.
- WebPreview source metadata/error fixture được sinh lại từ source app.

Không thay engine, transaction/apply/restore, native library, identity
enrollment/recovery, server/SQL, license protocol, HMAC/crypto/TLS, UI layout,
Xcode/workflow hoặc version/build 2.4 (37).

## Kiểm chứng

- 110 assertions thực thi policy HWID và body retry/login production: pass.
  Bao phủ fallback lần đầu, không có IDFV, hai bản cũ hỏng, exact bytes/case,
  generation lazy, storage failure/read-back, một bản lưu thành công, khởi động
  lại với file tạm thực, IDFV xuất hiện lại, conflict và không đổi lỗi login khác.
- Unittest client: 74 bài, 68 pass và 6 skip yêu cầu macOS.
- Identity/signing/agreement/recovery/bootstrap regression: 219 assertions pass
  với real software P-256 và OS boundary cô lập trên Linux.
- Actual `LicenseVerification.request` giữ nguyên chuỗi fallback 50 byte trong
  JSON, không nhét HWID vào URL; phù hợp giới hạn field server. Không gửi request
  lên server hoặc ghi dữ liệu khách hàng để thử.
- Swift frontend parse hai file runtime và public production config: pass.

Linux fixtures không xác nhận Apple Keychain, Secure Enclave, iOS SDK linkage
hoặc runtime trên iPhone. Tại thời điểm kiểm thử local, chưa push hay build IPA mới cho thay đổi này.
Snapshot/diff/hash/log cục bộ ở `scratch/hwid-fallback-20261113/`.
