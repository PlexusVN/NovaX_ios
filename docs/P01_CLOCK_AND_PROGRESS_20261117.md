# Astra 2.4 (40): thời gian quyền tải, chẩn đoán P01 và tiến trình thao tác

Video đầu ghi nhận `clockNotSynchronized` dù iPhone đã bật Đặt tự động. Decoder
cũ so `issuedAt <= Date()` không có dung sai; hai đồng hồ ở hai giây khác nhau
có thể làm từ chối một grant mới. Video `loi2.mp4` ghi lại thao tác chờ khoảng
50 giây với thông báo chung và không có nút hủy hoặc tiến trình theo bước.
Ảnh P01 khác ghi `invalidResponse`; chưa tái hiện được đúng nhánh lỗi đó bằng
dữ liệu production hiện tại. Không quy thông báo chung đó cho native exploit.

## Thay đổi

- `ProtectedResponseTime` nhận HTTP Date chỉ từ phản hồi đã qua system trust,
  TLS pinning, kiểm epoch/auth và HTTP 2xx của `SecureAPIClient`.
- `downloadArtifact` giữ mẫu thời gian của chính phản hồi content và dùng uptime
  để tính thời gian xác minh. Toàn bộ RTT và một giây độ phân giải HTTP Date được
  cộng theo hướng bảo thủ; cách này có thể rút ngắn thời gian dùng grant, không
  gia hạn `expiresAt`. Header thiếu/hỏng hoặc mẫu stale dùng kiểm local như cũ.
- Chữ ký, issuedAt/expiry tuyệt đối, recipient/session/nonce, manifest binding,
  hash/size và xác thực AES-GCM giữ nguyên. Không replay grant/content và không
  tự thay key hoặc bypass quyền server.
- P01 invalidResponse có mã tĩnh DLxx cho từng điều kiện: grant/content JSON,
  metadata/manifest fields, hash/size và các phản hồi enrollment/session. Mã
  chẩn đoán không chứa key, token, đường dẫn hoặc nội dung phản hồi.
- Thiếu identity và context/license thay đổi trả lỗi có kiểu tương ứng, không
  gộp nhầm thành lỗi dữ liệu tải. Không thêm retry grant đã dùng một lần.
- Card hiển thị bước thực: chờ, tải/xác minh, decode, tìm container, kiểm quyền,
  ghi và restore. Task được giữ trong service; card dựng lại không mất busy.
- Hủy được phép trước commit; sau hủy giữ busy đến khi worker thật kết thúc.
  Không thả gate/staging/native payload sớm và không cho card khác xếp thêm tác vụ.
  Nút hủy bị khóa khi ghi/restore đã được tiếp nhận.

## Bằng chứng và kiểm thử

Đã kiểm read-only 13 artifact production: chữ ký, metadata và manifest digest
đều hợp lệ; dữ liệu Storage giải mã đúng hash/size. Canonical JSON Swift/Node
của cả 13 manifest giống nhau; actual descriptor guard chấp nhận 13 descriptor
và từ chối 65 descriptor bị đổi field. Việc này không chứng minh phản hồi tại
thời điểm lỗi trên iPhone giống dữ liệu hiện tại.

Các test mới thực thi policy thời gian và body `downloadArtifact`, dictionary,
validateDescriptor, lifecycle progress production với boundary OS/transport
cô lập; CryptoKit thật tiếp tục chạy nhóm signed artifact/catalog trên macOS.
Windows/WSL full suite: 82 tests, 76 pass, 6 skip cần macOS. Trong các nhóm này
có 23 checks thời gian, 94 checks tải/chẩn đoán, 23 checks task/progress/cancel
và 128 checks coordinator/provenance/restore. Không cộng số checks thành test.

Giới hạn: chưa biết nhánh DL cụ thể của ảnh generic P01 cũ và chưa thử IPA sau
ký trên iPhone. Sau cài bản mới, nếu lỗi còn xuất hiện cần mã DL hiển thị để
xác định response field/identity chính xác. Không tuyên bố sửa quyền native trên
mọi app/iOS/build chỉ từ fixture hoặc kết quả build.

Lượt sửa client này không thay source/runtime VPS, database, key khách hàng,
server clock hoặc policy đóng băng thời gian sản phẩm. Source từ build 39;
metadata release là Astra 2.4 (40). Kết quả CI/IPA được ghi riêng sau build.
