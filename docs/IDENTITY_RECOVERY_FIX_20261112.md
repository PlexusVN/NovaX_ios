# Khôi phục định danh sau cài lại/reset — 12/11/2026

## Vấn đề và phạm vi

License có thể hợp lệ nhưng phiên tải từ chối `device_already_enrolled` sau
reset. Client cũ tiếp tục gửi khóa đã bị thu hồi; hàm recovery có sẵn chưa được
gọi từ luồng tạo phiên. Một pending enrollment đã commit nhưng mất phản hồi
cũng phải được thử lại bằng đúng bộ khóa đã lưu, trước định danh cũ.

Kế hoạch thực hiện giới hạn ở vòng đời định danh:

1. Giữ bootstrap bằng khóa cũ khi thiết bị vẫn hợp lệ.
2. Nối recovery có quyền admin vào luồng tạo phiên và lần thử lại catalog.
3. Giữ khóa thay thế bền vững để chịu được gián đoạn/lost response.
4. Kiểm tra canonical scope đầy đủ trước khi đổi định danh active.
5. Kiểm thử luồng thực và đối chiếu SHA-256 với bản gốc.

Hai file runtime được sửa là `helpers/ProtectedDownloadService.swift` và
`helpers/DeviceIdentityService.swift`. Các thay đổi khác là test, test runner
và tài liệu liên quan. Không tăng version/build. Không sửa engine, native
exploit, pairing/VPN, patch/restore, license login, HWID, giao diện SwiftUI,
pin/cấu hình bảo mật, artifact crypto hoặc runtime server/SQL.

## Hành vi sau sửa

- Update/restart dùng lại đúng khóa và định danh; server trả metadata canonical.
- Một pending recovery còn nguyên được thử trước khóa cũ. Fresh challenge dùng
  lại installation ID và cả hai khóa pending khi phản hồi trước bị thất lạc.
- Lỗi enrollment/revoked hoặc thiếu identity chỉ cho phép hỏi quyền recovery.
  App chỉ tạo bộ thay thế sau challenge đã qua pinned TLS, đúng license/key ID
  và `recovery_authorized=true`.
- Canonical recovery response phải khớp license binding, key ID, installation
  ID, device UUID, revision 2 và fingerprint của cả signing/recipient keys.
- Khóa cũ và các generation trước được giữ; active pointer chỉ chuyển sau khi
  dữ liệu thay thế đã ghi và kiểm tra đầy đủ.
- Pending bị mất material chỉ được thay bằng generation mới sau một quyền
  recovery mới; thiếu quyền thì giữ nguyên archive. Lỗi Keychain tạm thời,
  entitlement, mạng, ban/quarantine và dữ liệu mơ hồ không tự đổi khóa.
- Lần tạo khóa đầu tiên có record chuẩn bị riêng. App có thể hoàn tất hai khóa
  sau gián đoạn trước enrollment; trạng thái submitted được lưu trước POST để
  mất khóa sau khi đã gửi không bị hiểu nhầm thành bản cài mới.
- Tạo phiên thử lại cùng khóa tối đa một lần, recovery tối đa một lần trong
  mỗi chu kỳ. Catalog đọc được thử lại một lần khi phiên/định danh bị từ chối,
  kể cả reset trong khi app đang mở. Grant/content dùng một lần không được
  phát lại tự động.
- Logout/đổi key/context epoch hoặc task cancellation chặn phản hồi muộn
  chuyển định danh. Thông báo cần admin cấp lại quyền hướng dẫn thử lại sau
  khi được duyệt.

## Backend và triển khai

Server source hiện tại đã có canonical enrollment và same-key resume. Reset
production gọi RPC `novax_reset_license_devices`, không cần thay bằng các lệnh
DELETE tuần tự. Runtime server và SQL được giữ nguyên trong bản sửa này.

Xem [backend contract/preflight](../../../production-server/AUTH/server/docs/IDENTITY_RECOVERY_CONTRACT_20261112.md).
Phải kiểm tra definition/constraint thực tế của RPC reset/enroll trên VPS:
gói source hiện thiếu migration recovery cuối, nên không thể chứng nhận
transaction replacement thực tế chỉ bằng schema legacy trong package.

Không chạy schema legacy để thay thế database hiện hành. Không xóa device
keys, sessions, recoveries hoặc lịch sử enforcement để che lỗi. Không cần
đổi signer, master key, bucket hay catalog cho bản sửa client này.

Trước phát hành: xác minh backend contract, chạy CI macOS/Xcode hiện có rồi
thử IPA ký thật trên iPhone với update/cài lại/reset một thiết bị. Giữ quyền
Keychain của cấu hình ký hiện hành; lỗi quyền ký không được coi là khóa mới.

## Kiểm chứng

Kết quả cuối và danh sách SHA-256/diff được lưu trong workspace
`scratch/identity-recovery-20261112/`. Snapshot được tạo trước thay đổi, không
dùng Git HEAD cũ của workspace làm đại diện cho source hiện tại.

Kiểm tra client gồm unittest/wiring toàn bộ, Swift orchestration trích từ
production, actual identity/bootstrap/recovery với transport và storage cô
lập. Bổ sung thử phần mềm P-256/SHA-256 bằng Apple swift-crypto 3.0.0 trên
Linux; chỉ thay boundary Keychain/Secure Enclave không có trên Linux trong
artifact kiểm thử. Các body logic production được giữ. Đây không phải kiểm
chứng Apple Keychain/Secure Enclave, TLS delegate hoặc runtime iPhone.

Kiểm tra backend gồm canonical enrollment, reset helper, same-key retry,
session logout, chống replay, artifact crypto/gateway/transfer và enforcement.
Existing recovery SQL suite bị chặn bởi schema snapshot thiếu bảng v2;
không thay fixture/schema để báo thành công giả. Kết quả và giới hạn cụ thể
được ghi trong báo cáo kiểm thử cuối.

Kết quả cuối tại thời điểm bàn giao:

| Nhóm | Kết quả |
| --- | --- |
| Python unittest toàn bộ client | 68 bài: 61 pass, 7 skip yêu cầu macOS |
| Actual session/catalog orchestration | 44 assertions pass; nằm trong unittest trên |
| HWID regression nguyên bản | 38 assertions pass; nằm trong unittest trên |
| Actual identity/storage/recovery/bootstrap với software P-256 | 219 assertions pass (30 + 62 + 46 + 81) |
| Recovery authorization contract production | 43 assertions pass |
| Node identity/reset/session/crypto/gateway/enforcement | 129 test pass, không skip |
| Existing recovery SQL integration | 2 pass, 3 fail vì thiếu `novax_enrollment_challenges` trong schema snapshot |

Ba SQL test thất bại trước khi thực thi RPC recovery thực tế; đây là giới hạn
schema đã có từ baseline. Chưa build IPA mới, chạy CI macOS hay xác minh VPS/
iPhone. Không dùng kết quả Linux/fixture để tuyên bố các bước đó đã thành công.
