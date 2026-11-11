# Rà soát worse_query và lỗi tìm container — 11/11/2026

## Bổ sung build 25: khởi động và màn hình quét

Người dùng báo iOS 27 văng ngay khi chạm biểu tượng, chưa thấy đăng nhập. Chưa có
crash report `.ips`, nên chưa xác nhận được exception/signal hay lỗi chữ ký/dyld.
Build 25 loại bỏ việc tự dò container game và probe sandbox kiểu kernel trên
iOS 27 khi khởi động. Quét/token chỉ bắt đầu khi một chức năng thực sự cần chúng.
Lookup App Group chuyển qua cầu nối Objective-C có chặn Foundation exception;
Swift do/catch không chặn được loại exception này. Đây là phòng vệ cho đường
khởi động đã tìm thấy, không phải bằng chứng đã tái hiện crash trên thiết bị.

Màn hình chờ iOS 27 xuất hiện khi fallback scan thực sự chạy, không tự quét chỉ
vì mở app. Hiện phần trăm phạm vi inode thật, số container tìm được/truy cập được,
log có giờ, nút dừng và sao chép. Dừng chờ đoạn native hiện tại kết thúc rồi ném
cancellation trước commit. Thành công chỉ xác nhận tìm được container, không
đánh dấu patch đã bật. Không đổi auth/network/integrity gates.

Giữ tối đa 200 log quét, 500 log chung; checkpoint lịch sử vào Application Support
riêng của Astra, không ghi license/token. Mở lại chỉ đọc lịch sử, nhận diện phiên
gián đoạn và không tự chạy lại exploit. Xem lại ở Cài đặt → Quét thư mục iOS 27.

## Kết luận

Astra đã tích hợp lõi native worse_query, nhưng phần tìm container trước build 24 chưa theo đủ logic của bản gốc. Đã tìm thấy và sửa lỗi giới hạn 500.000 inode; lỗi này có thể bỏ sót ứng dụng khi cache/LaunchServices/MCM không trả được đường dẫn. Ảnh P06 trên iOS 27.0.1 không có log inode/token, nên chưa đủ để khẳng định đây là nguyên nhân duy nhất trên điện thoại đó.

Đối chiếu bản upstream có sẵn trong workspace: `worse_query-main/worse_query/{worse_query.m,pathleak.m,ContentView.swift}`.

## Chuỗi upstream và tích hợp

1. Cần App Group thực sự truy cập được trong bản đã ký. Astra đọc entitlement runtime trước rồi thử tên dự phòng. Khai báo nhóm trong source không tự cấp quyền; ESign/profile vẫn phải giữ quyền hợp lệ.
2. Query dùng class 7, part 3; symlink `AppGroup/Library/Caches` trỏ đến container đích. Flag `0x0000000800000000` chỉ cho AppGroup trên iOS 26; các đích khác, gồm Data/Application trên iOS 27.0.1, dùng `0x0000008000000000`.
3. Nhận token, consume, dọn query/library/symlink; giữ handle khi đọc/ghi rồi release. Astra tuần tự hóa thay symlink để các tác vụ không đè lên nhau.
4. Trên iOS 27, grant cho thư mục cha Application không thay thế việc dò UUID. Upstream tạo tệp baseline mới, lấy inode, quét từ 1 đến baseline bằng fsgetpath, cấp token cho TỪNG UUID rồi đọc xattr định danh.
5. Astra ưu tiên cache/LaunchServices/MCM. Fallback build 24 làm theo bước 4, dùng baseline + 2.048 và các đoạn liên tiếp 250.000 inode, dừng khi tìm đúng bundle ID. Kích thước đoạn chỉ để hủy/ghi log; không giới hạn tổng phạm vi.

## Sửa chữa ở build 24

- Bỏ trần 500.000 và sàn giả 100.000 của baseline nhánh worse_query. Lỗi tạo/stat baseline được trả về thay vì chuyển thành danh sách rỗng.
- pathleak_range giữ biên đầu/cuối, chuẩn hóa /var và /private/var, lọc con trực tiếp, chống lặp và tràn vòng lặp.
- Nếu statfs thư mục bảo vệ bị từ chối, lấy fsid từ home Astra trên cùng Data volume. Phân biệt lỗi thiết lập với đoạn quét chưa có kết quả.
- Cấp token từng UUID trước khi đọc xattr; đọc metadata plist trong cùng phạm vi token làm dự phòng; cache định danh hợp lệ và release cả khi return sớm.
- Loại bundleContainerURL/.app khỏi kết quả data container. Các đường dẫn phải là con UUID trực tiếp của Data/Application.
- Giữ lỗi query/token/consume; consume thất bại có mã riêng -7 để tránh báo nhầm thiếu group. Quét hết không tìm thấy có mã WQ02.
- Chạy discovery trong Task.detached. Task.detached ở View trước đây chưa đủ vì FeaturePatchService có MainActor. Apply/restore chuẩn bị roots trước commit, kiểm tra lại auth/network/cancellation rồi lấy lại token và giữ suốt transaction.
- Giữ xác thực, integrity, journal, backup/rollback và khôi phục. Tăng build 23 lên 24 trong Info.plist, Xcode và CI.

## Những sửa chữa đã có

Runtime pairing đi theo storage mode thực tế. Thiếu group và dùng AirLift thì cần VPN/pairing thật. VPN bất kỳ hoặc TCP refused không chứng minh đường AirLift hợp lệ. CI giữ entitlement trong chữ ký ad-hoc, kiểm tra native bridge/group trước khi đóng IPA. Chữ ký ad-hoc không thay thế profile cài đặt và không bảo đảm quyền còn tồn tại sau ESign.

Ảnh cũ `AirLift ... RPPairing timed out after 6s` xác nhận nhánh AirLift. Ảnh mới `Chưa truy cập được container ứng dụng đích` phản ánh lỗi tìm container cũ; chưa chứng minh daemon worse_query đã cấp token.

## Kiểm chứng

Windows: phát hiện 56 test, 53 thành công và 3 cần macOS được bỏ qua rõ ràng. Cấu hình production offline hợp lệ.

CI macOS biên dịch/chạy PathLeakSelfCheck.m và WorseQueryNativeSelfCheck.m với mã native production, thay riêng OS boundary bằng fixture. Bao gồm inode 500.001/2.000.000, denied statfs, path aliases/boundaries, class/part/flags, symlink lifecycle, lỗi -1 đến -7/-255, zero handle, release và tuần tự hóa truy vấn đồng thời.

ContainerDiscoverySelfCheck dùng resolver và async preparation trích trực tiếp từ production: toàn bộ đoạn inode, token còn sống khi đọc xattr, release khi return, giữ lỗi và scan ngoài main thread. Helper/routing có iOS 27.0.1. Xcode build và kiểm tra IPA trên CI là điều kiện phát hành; kết quả run cụ thể được báo khi hoàn tất.

## Giới hạn và thử trên điện thoại

Fixture không gọi daemon iPhone. Chưa có kết quả chạy build 24 trên iOS 27.0.1 ký ESign nên chưa thể tuyên bố lỗi đã hết trên máy đó. isAvailable chỉ xác nhận OS + group, không bảo đảm exploit thành công. Quét inode lần đầu có thể lâu theo thiết kế upstream; chạy nền/cache giảm ảnh hưởng, không bảo đảm bật tức thì. Baseline là ước lượng upstream, không phải API liệt kê mọi inode có thể tồn tại hoặc tạo đồng thời.

Thử build 24: giữ App Group khi ký, mở app đích một lần, bật chức năng trong Astra và chờ hoàn tất. Không cần VPN/pairing nếu worse_query hoạt động. Kiểm tra bật, tắt/khôi phục, đóng/mở lại Astra và thử lại khi VPN tắt. Log cần có `patch engine ... appGroup=true storage=direct`, `worse_query discovery: start ... baseline upper bound=...`, `matched ...` hoặc lỗi query cụ thể.
