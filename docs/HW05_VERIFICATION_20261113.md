# HW05 và kiểm chứng lại engine — 13/11/2026

## Chẩn đoán ảnh

Ảnh hiển thị iOS 26.5.0, lỗi HW05 và HWID chưa sẵn sàng. Theo policy hiện tại,
26.5 dùng nhánh direct 3105; thông báo hỗ trợ trong ảnh phù hợp với policy.
HW05 phát sinh ở đọc/đối chiếu HWID local, trước request `/api/verify`, không
phải kết quả từ engine, App Group hoặc bằng chứng key không hợp lệ.

Thông báo cũ gộp `invalidIdentity` và `ambiguousIdentity`, nên ảnh không xác
định được bản Keychain hay mirror hỏng, hoặc hai bản có conflict thật.

Đã tái hiện bằng actual Swift production policy trước sửa:

- Primary hỏng chặn mirror UUID hợp lệ.
- Mirror hỏng chặn primary UUID hợp lệ.
- Hai UUID cùng identity nhưng khác hoa/thường bị so exact string thành conflict.

## Thay đổi giới hạn

Chỉ sửa enum `StableDeviceHWID` trong `views/SecurityUtils.swift` và test HWID:

- Đọc/validate hai bản riêng, dùng UUID đã lưu hợp lệ còn tồn tại.
- So sánh UUID identity nhưng giữ cách viết/case của primary hợp lệ; không ép
  uppercase vì server v1 có thể so exact chuỗi.
- Chấp nhận outer whitespace hoặc một UTF-8 BOM quanh UUID đúng 36 byte;
  không chấp nhận hash/URN/braces/NUL/UTF-8 lỗi và không sinh UUID khác.
- Giữ nguyên bytes của bản hỏng/không truy cập được. Chỉ bổ sung bản đã xác
  nhận thiếu hoặc đồng bộ biểu diễn của hai UUID vốn bằng nhau.
- Chỉ dùng IDFV cho lần đầu khi cả hai kho xác nhận chưa có dữ liệu.
- Hai UUID hợp lệ khác nhau tiếp tục bị chặn trước mọi ghi: `HW05-CONFLICT`.
  Không còn bản hợp lệ để dùng: `HW05-DATA`. Không xóa dữ liệu để che lỗi.

Các trường hợp DATA/CONFLICT thật cần xác minh dữ liệu/định danh đã đăng ký;
không thể khôi phục UUID bị mất chỉ từ ảnh. Không tuyên bố máy trong ảnh chắc
chắn thuộc một trong các nhánh đã tái hiện khi chưa có chẩn đoán bản lưu thực.

Rà soát toàn bộ engine tìm thêm một lỗi riêng: Task đã bị cancel trong lúc chờ
FFI queue vẫn có thể gọi native. Chỉ sửa `AirTrafficProtocolClient.runBlocking`
và thêm permit queued/started/cancelled dưới lock. Cancel trước khi bắt đầu
ngăn native dispatch; cancel sau khi bắt đầu vẫn đợi kết quả native thật,
giữ payload và busy/filesystem gate đến completion.

Ngoài hai file runtime trên, thay đổi chỉ ở hai regression fixtures, tài liệu
này và dữ liệu WebPreview sinh từ source HWID. Không đổi AuthManager, identity
keys/recovery, policy engine, native exploit/archive, transaction, UI layout,
server/SQL, pins/crypto, project/workflow, version/build 2.4 (37).

## Kiểm chứng cuối

| Nhóm | Kết quả |
| --- | --- |
| Toàn bộ unittest client | 74 bài: 67 pass, 7 skip cần macOS |
| HWID + retry đăng nhập production | 74 assertions pass (trước sửa: 38) |
| AirLift entry/native lifetime/cancellation | 42 checks pass (trước sửa: 37) |
| Pairing completion regression | 10/10 pass |
| Policy boundary độc lập | 260 assertions pass |
| So policy với snapshot 3105 | 24.696 tổ hợp OS/build pass |
| Coordinator/provenance/gate | 26 checks pass |
| Container identity evidence | 34 assertions pass |
| Full direct transaction/rollback, file tạm thực | 14 checks pass |
| WQ preparation với OS boundary fixture | Pass 26.6.2/26.7.0/26.7.2/27.0.1 |
| Identity bootstrap/recovery trước đó, real software P-256 | 219 assertions pass |
| Swift frontend parse + public production config | Pass |

Các số HWID/AirLift/policy/coordinator/evidence đã nằm trong unittest, không
cộng chúng như các test độc lập. Linux fixtures thay boundary Apple
Keychain/Secure Enclave/Combine/native; không chứng minh runtime iPhone.

CI của commit 82e5f04 (Astra 2.4 build 37 trước engine isolation/HW05 mới)
đã thành công, nhưng không được dùng làm kết quả build cho source mới này.
Chưa push, chạy CI hoặc build IPA cho các thay đổi hiện tại. Cần Xcode với iOS
SDK và IPA ký thật để xác nhận typecheck/linkage/quyền Keychain trên thiết bị.

Snapshot trước lần sửa này, diff, SHA-256 và logs:
`scratch/hw05-verification-20261113/` cục bộ, không nằm trong GitHub repository.
