# Astra 2.4 (39): đồng bộ Bundle ID package với server

Package `.3105` tải từ catalog bảo mật có thể nhắm mọi Bundle ID hợp lệ được
server chấp nhận. Ba alias `ffth`, `ffmax`, `capcut` giữ nguyên; ứng dụng khác
dùng variant `bundle:<BundleID>` chính xác, có phân biệt chữ hoa/thường.

Policy trong `AppSecurityConfiguration` dùng cùng grammar với server: ASCII,
tối đa 255 byte, ít nhất hai thành phần gồm chữ/số/gạch ngang, không có thành
phần rỗng hoặc gạch ngang ở đầu/cuối. Native `mod/original` tiếp tục giới hạn
FFTH/FFMAX; chỉ package được mở rộng target.

## Luồng hoạt động

- Decoder và download service dùng chung policy target trước khi cấp quyền
  tải/giải mã. Chữ ký, recipient, session, nonce, hạn grant, AES-GCM và SHA-256
  giữ nguyên.
- Sau decode package, mọi Bundle ID trong rule/directory/project phải khớp
  target của artifact. Gói trộn ứng dụng hoặc khai variant khác target bị từ chối.
- Bước chuẩn bị worse_query lấy tập ứng dụng từ catalog của license hiện tại,
  thay cho ba target cố định lúc khởi động. Thiết bị chỉ có ứng dụng custom có
  thể dùng luồng chuẩn bị này. Catalog thất bại không được coi là catalog rỗng.
- Catalog rỗng đã xác thực cho vào giao diện mà không công bố quyền truy cập.
  Khi áp dụng, lazy preparation vẫn xác minh từng target thực sự cần dùng.
- Đồng bộ catalog cùng auth revision được gộp; đổi license/logout hủy context
  catalog/preparation. Kết quả cũ không công bố root cho phiên mới. Ảnh danh mục
  không làm chậm việc chuẩn bị target.
- Nút hủy hoạt động cả trong lúc tải catalog và khi đang dò native. Retry giữ
  nguyên kiểm tra quyền; không coi hủy/timeout là đã truy cập được container.
- Định danh lưu trữ custom dùng SHA-256 của variant chính xác để giữ tên file
  ngắn khi Bundle ID dài tới 255 byte. Association cũ được migrate bằng cơ chế
  hiện có; backup, journal và lịch sử restore được giữ.

OS/build policy, native exploit/FFI, entitlement, license/HWID/recovery và cơ chế
transaction/restore không đổi. Bundle ID được chấp nhận không chứng minh app
có quyền truy cập mọi container trên mọi phiên bản iOS hoặc bản ký.

## Kiểm chứng

Portable checks compile policy production với Swift và đối chiếu fixture tạo
từ policy Node server. Preparation checks chạy body production với boundary
native cô lập, gồm custom-only, catalog rỗng/thất bại, cancel/retry, auth reset và
late result. Catalog fixtures do server ký bao gồm target custom, max-length,
system-app và những gói/manifest không khớp để kiểm tra từ chối.

Workflow macOS chạy cả catalog cũ và custom bằng CryptoKit, codec `.3105` và
apply/restore transaction thực trên filesystem tạm, rồi build/link IPA với
AirliftFFI rebuild từ source pin hiện có. Test trên Windows/WSL không thay thế
Apple Keychain/Secure Enclave/Combine hoặc quyền native trên iPhone. Phải dùng
đúng IPA build 39 được CI tạo và ký cài đặt bằng profile phù hợp để thử thiết bị.

Source được cập nhật từ nền build 38 (`7f416a6c2733b1f053846f057fa86b8ebc05f406`).
Kết quả CI và IPA được ghi riêng trong báo cáo release sau build; tài liệu này
không tự xác nhận build hoặc thử iPhone đã thành công.
