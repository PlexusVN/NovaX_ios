# Astra 2.2 (34) — chính sách truy cập tệp

Chính sách duy nhất nằm trong `ThreeOneOSFive/helpers/KernelExploit.swift`, enum `ExploitSupportPolicy.AccessProvider`. Chọn theo phiên bản **và build**, theo thứ tự 3105 → worse_query → AirLift → không hỗ trợ. Kết quả không phụ thuộc App Group, trạng thái kernel, VPN, pairing hay lựa chọn cũ lưu trong Settings.

| Phiên bản/build | Cơ chế được chọn | Chuẩn bị worse_query | Pairing |
| --- | --- | --- | --- |
| iOS 16.x | Tương thích trực tiếp hiện có của Astra | Không | Không |
| iOS 17.0–17.7.x | 3105; kernel chỉ trong phạm vi upstream cho phép | Không | Không |
| iOS 18.0–18.7.1 | 3105 | Không | Không |
| iOS 18.7.2+ thuộc 18.x | AirLift qua bản port AirCard/AirliftFFI | Không | File pairing nhập từ máy tính + tunnel loopback |
| iOS 26.0–26.6.1 | 3105: MHA/MCM class 2, bad_query; không chạy kernel | Không | Không |
| iOS 26.6.2–26.7.2 | worse_query | Bắt buộc sau đăng nhập | Không |
| iOS 26.7.3+ thuộc 26.x | AirLift qua bản port AirCard/AirliftFFI | Không | File pairing nhập từ máy tính + tunnel loopback |
| iOS 27.0.0 beta 1–4, đúng build 24A5355q / 24A5370h / 24A5380h / 24A5390f | 3105 theo allowlist upstream | Không | Không |
| Các bản 27.0/27.1 còn lại | worse_query | Bắt buộc | Không |
| iOS 27.2.0, theo README worse_query; không dùng allowlist beta của AirLift | worse_query | Bắt buộc | Không |
| 27.2.1+; 27.3+; OS major không được liệt kê | Không hỗ trợ | Không | Không được tự khởi động |

`3105-main` chỉ liệt kê kernel trên 17.0–17.7.x và 18.0–18.7.1. Không dùng điều kiện “OS hỗ trợ 3105” để suy ra “kernel hỗ trợ” cho 26.x hoặc 27 beta. iOS 16 là nhánh tương thích của Astra; không được mô tả là đã được upstream 3105 xác nhận.

## Ranh giới giữa các cơ chế

- `WorseQueryHelper.isOSSupported/isAvailable` chỉ đúng trên tuyến worse_query đã chọn. Có App Group không thể chuyển iOS 26.6.1 hoặc beta 27 thuộc 3105 sang worse_query.
- MCM native dùng cầu nối `AstraUses3105ContainerAccess` để đọc cùng chính sách Swift. Tuyến 3105 ưu tiên MHA-C2 trước LaunchServices; giữ bản sửa ownership ARC đã xử lý crash build 29.
- Tuyến worse_query chỉ lấy root đã xác minh trong màn hình chuẩn bị; giữ nguyên native query class/part/flags, chọn App Group có thể ghi, token theo UUID và vòng đời token trong giao dịch.
- Thiếu App Group hoặc chuẩn bị thất bại phải báo lỗi; không cho bỏ qua màn hình bằng nút AirLift dự phòng và không rơi xuống ghi tệp thô.
- Tuyến AirLift cần pairing, transport đã xác thực và canary trước ghi. Native core không thay đổi. Các thao tác đọc/restore chưa được FFI hỗ trợ tiếp tục báo không hỗ trợ.
- Tài liệu AirLift nói 27.2 beta 3+ đã vá AirTraffic; README worse_query nói hỗ trợ đến 27.2. Đây là hai exploit khác nhau: không lấy giới hạn beta của AirLift để chặn worse_query. Không suy ra hỗ trợ 27.2.1 hoặc 27.3 từ dòng tài liệu 27.2.

## Đối chiếu nguồn và giới hạn xác nhận

Nguồn tại workspace: `3105-main/3105-main/ThreeOneOSFive/helpers/SupportPolicy.swift`, `worse_query-main/README.md`, `worse_query-main/worse_query/ContentView.swift`, `airlift-main/airlift-main/README.md` và `supplemental-source/aircard-upstream-source/README.md`.

`airlift-main` gốc là PoC chạy trên Mac đã pairing. Ứng dụng iPhone dùng bản port AirCard/AirliftFFI; không tuyên bố ứng dụng chạy nguyên bản chương trình Mac. Phạm vi 18.x/26.x nhập pairing lấy từ tài liệu bản port. Các phạm vi phiên bản là chính sách định tuyến theo tài liệu, không phải chứng nhận đã thử mọi thiết bị/build.

Kiểm thử biên dùng chính enum production, so với snapshot nguyên bản SupportPolicy của 3105 (chỉ đổi tên enum). Kiểm thử resolver/grant production dùng native spies để xác nhận MHA-C2, worse_query và chặn gọi chéo. Không thay thế kiểm thử IPA đã ký trên iPhone thật. Không có thay đổi server hoặc giao thức tải file build 33 trong bản sửa định tuyến này.
