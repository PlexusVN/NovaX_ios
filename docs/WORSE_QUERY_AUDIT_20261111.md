# Rà soát worse_query và lỗi P06 — 11/11/2026

## Kết luận và mức xác nhận

Source Astra đã liên kết lõi `worse_query`, nhưng phần tích hợp trước lượt sửa này
chưa hoàn chỉnh. Có mã nguồn không đồng nghĩa IPA sau build/ký đã dùng được nó.
Chưa kiểm chứng chạy exploit, build Xcode hay ký ESign trên iPhone trong lượt này.

Ảnh `P06: AirLift ... raw RPPairing timed out after 6s` xác nhận thao tác đã vào
nhánh AirLift. Người dùng xác nhận không bật LocalDevVPN. Đây là nguyên nhân
trực tiếp khiến kết nối nhánh đó thất bại; ảnh không chứa kết quả gọi worse_query.

Với source hiện tại trên iOS 27.0–27.1 và hai build 27.2 beta được liệt kê:

1. `WorseQueryHelper.isAvailable` yêu cầu OS được hỗ trợ và App Group truy cập được.
2. Khi thiếu điều kiện đó và không có sandbox access, `currentStorageMode` chọn AirLift.
3. Trước đây lý do chuyển engine không được giải thích trong lỗi P06.

Chưa có entitlements/log của bản **đã ký và đang cài** để kết luận chắc chắn
ESign đã bỏ quyền, đã đổi tên nhóm, hay thiết bị dùng build OS ngoài phạm vi.
Không coi việc người dùng nói đang dùng bản mới nhất là bằng chứng họ dùng IPA cũ.

## Đối chiếu mã gốc trong workspace

`worse_query-main/worse_query/worse_query.m` và `ContentView.swift`:

- Class 7, part 3, symlink `AppGroup/Library/Caches`, lấy token rồi consume/release:
  phần lõi Astra dùng đúng chuỗi thao tác này.
- Flag `0x0000000800000000` chỉ dùng với đích AppGroup trên iOS 26; các đích khác
  dùng `0x0000008000000000`: wrapper Astra khớp bản gốc.
- App Group được OS cho truy cập là điều kiện bắt buộc của bản gốc. Tự ký hoặc
  khai báo trong source không tự cấp quyền này. Xem [upstream](https://github.com/forcequitOS/worse_query).

## Các lỗi tích hợp đã sửa trong source

- Đọc App Group từ signed entitlements của tiến trình bằng binding Security tùy chọn,
  rồi mới thử các tên dự phòng. Nhận diện được tên nhóm mà công cụ ký lại đã đổi.
- Đồng bộ `currentPairingMode` với `currentStorageMode` thực tế: thiếu group dẫn
  tới AirLift thì giao diện phải cho cấu hình pairing tương ứng.
- Bỏ so sánh build bằng chuỗi; dùng chung chính sách OS cho helper và router.
  iOS 27.2 beta 3+ / build 27.2 không được liệt kê không tự chuyển sang AirLift
  vì đường AirTraffic đó cũng đã vá theo chính sách tương thích của dự án.
- `DevicePatchService` lấy token bằng lời gọi có thể throw, giữ token trong suốt
  transaction và giải phóng khi thành công hoặc thất bại. Không còn dựa vào các
  lời gọi grant bị bỏ kết quả trong resolver của luồng transaction.
- Nhánh WorseQuery trong `applyPatchProject` dùng transaction có journal/backup;
  không đánh dấu các lần ghi trực tiếp là một lần áp dụng qua AirLift.
- Ghi CodePatch qua helper khi WorseQuery khả dụng; sửa ranh giới đường dẫn và
  chuẩn hóa `/var` ↔ `/private/var` cho scope/container root.
- Tuần tự hóa thao tác thay symlink dùng chung giữa background scan và patch.
  Giữ ngoại lệ cho `lstat` bị sandbox từ chối; các lỗi khác không bị coi là thành công.
- Giải phóng token của metadata scan cả khi trả về sớm; kiểm tra cache container
  sau khi lấy quyền thay vì loại cache vì `fileExists` bị sandbox chặn.
- VPN bất kỳ hoặc TCP connection refused không còn đủ để báo route AirLift hợp lệ.
  Nếu OS hỗ trợ WorseQuery nhưng thiếu group và không có VPN, lỗi giải thích đúng
  điều kiện bản ký thay vì đi vào native RPPairing rồi timeout.

## Build và bản phát hành

CI trước đây build với `CODE_SIGNING_ALLOWED=NO` rồi zip trực tiếp. File source
`.entitlements` chưa được đưa vào một chữ ký ad-hoc để công cụ ký lại đọc.
Đã thêm bước ad-hoc sign bằng entitlements dự kiến, đọc lại group để kiểm tra,
và kiểm tra executable có ba symbol native mới trước khi đóng gói.
IPA vẫn cần ký bằng chứng chỉ/profile Apple hợp lệ để cài; ad-hoc signature không
cấp App Group được profile cho phép và công cụ ký lại vẫn có thể bỏ quyền.

IPA duy nhất trong `release/` là `1.2.10 (16)`; kiểm tra binary không thấy
`worse_query`/`WorseQueryHelper`. Đây là baseline đã lưu, không phải bằng chứng
về bản app người dùng đang cài. Không thay thế hoặc tuyên bố đã build IPA mới.

## Kiểm tra và giới hạn

- Kết quả tại Windows: 31 test Python PASS, 1 test chạy Swift được bỏ qua do
  thiếu macOS/compiler. 10 điều kiện kiểm tra completion pairing cũ cũng PASS.
- Các test Python liên quan kiểm tra wiring, cấu trúc nguồn, tương thích archive,
  chính sách deadline cũ và license. Chúng không chứng minh exploit chạy trên máy.
- Thêm `WorseQueryHelperSelfCheck.swift`: biên dịch helper production với cầu nối
  native và OS/group giả lập, kiểm tra tên group đổi, scope, flags, lifetime token
  và lỗi daemon. CI macOS chạy cùng test routing production; Windows bỏ qua rõ ràng.
- Chưa chạy Xcode, CI macOS, ESign hoặc iPhone trong lượt sửa này.
- `pathleak` fallback vẫn giới hạn 500.000 inode trong helper hiện tại. Nếu cache,
  LaunchServices và MCM đều không tìm được container, trần này có thể bỏ sót game;
  cần log máy thật để xác nhận nhánh này. Không gọi đây là dò container đầy đủ.
- Các caller duyệt file cũ ngoài transaction vẫn có thể giữ grant trong tiến trình;
  lượt sửa này quản lý token theo phạm vi cho transaction patch và metadata scan.

Khi kiểm tra máy thật, cần xác nhận log `patch engine` ghi `appGroup=true`,
`storage=direct`, sau đó apply/restore thực sự thành công khi VPN tắt.
`isAvailable=true` chỉ xác nhận điều kiện đầu vào, không bảo đảm daemon cấp token.
