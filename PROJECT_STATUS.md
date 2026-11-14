## Astra 2.4 (38): đối chiếu IPA và sửa luồng truy cập

Build 38 khôi phục thứ tự tra Bundle ID → MCM path/LaunchServices → worse_query
grant → kiểm tra đọc trước khi quét inode; xử lý hỏng khóa Secure Enclave qua
recovery có quyền, thông báo lệch giờ riêng và sửa tính nhất quán journal/sidecar.
Đã bỏ probe ghi thử khi khởi động. Phạm vi và giới hạn kiểm chứng tại
[REFERENCE_FLOW_FIX_20261115.md](docs/REFERENCE_FLOW_FIX_20261115.md).

## Source update 13/11/2026: cô lập engine và provenance

Đã sửa source để 3105/worse_query/AirLift dùng cùng policy, giới hạn entry point của từng engine, preparation theo Bundle ID và lưu engine/journal của giao dịch. Partial AirLift giữ trạng thái cần xử lý; legacy không rõ baseline giữ backup và không báo khôi phục gốc. Chưa phát hành IPA mới; version vẫn 2.4 (37). Xem [phạm vi và kiểm chứng](docs/ENGINE_ISOLATION_20261113.md).

## Build 2.4 (37): Khôi phục định danh thiết bị

Astra 2.4 (build 37) đóng gói bản sửa recovery sau cài lại/reset thiết bị: dùng lại khóa hợp lệ, hoàn tất recovery được admin cấp quyền và tiếp tục đúng bộ khóa đã lưu khi mất phản hồi đăng ký. Đồng bộ phiên bản trong Info.plist, hai cấu hình Xcode và artifact CI. Xem [phạm vi, kiểm thử và giới hạn triển khai](docs/IDENTITY_RECOVERY_FIX_20261112.md).

## Build 2.3 (36): Nâng cấp phiên bản Astra 2.3

Nâng cấp phiên bản chính thức lên Astra 2.3 (build 36). Đồng bộ toàn bộ các cập nhật định tuyến động cơ worse_query / 3105 / AirLift, tối ưu hóa lưu trữ định danh HWID và truy cập container game.

## Build 2.2 (35): HWID trước đăng nhập

Đã sửa lỗi nuốt lỗi đọc/lưu HWID thành chuỗi rỗng và luôn hướng dẫn mở khóa. Thêm bản dự phòng HWID công khai trong Application Support có Data Protection và loại khỏi backup; giữ nguyên khóa ký/giải mã trong Keychain. Đọc lại khi foreground/unlock, retry có giới hạn, báo mã HW01–HW06/OSStatus và cho sao chép thông tin lỗi. Giữ nguyên định tuyến engine build 34. Đã qua 38 kiểm tra mã Swift thực, 60 bài local; 7 bài chỉ chạy macOS được bỏ qua. Source đã được push lên GitHub; CI đang xác minh và đóng gói IPA build 35.

## Cập nhật 2.2 (34): định tuyến engine theo upstream

3105 được ưu tiên cho toàn bộ phạm vi upstream, cộng nhánh iOS 16 của Astra. Worse_query chỉ dùng từ 26.6.2 trong phạm vi được hỗ trợ, trừ các build 27 beta đã thuộc 3105. Các bản 18.x/26.x còn lại dùng AirLift + file pairing. Không tự đổi engine theo App Group. Xem [bảng và giới hạn kiểm chứng](docs/ENGINE_ROUTING_ASTRA_2_2.md).

# Astra — trạng thái tích hợp on-device AirLift

> Cập nhật 11/11/2026: source hiện ưu tiên worse_query khi OS và App Group cho
> phép. Phần dưới mô tả luồng AirLift dự phòng. Xem
> [rà soát worse_query/P06](docs/WORSE_QUERY_AUDIT_20261111.md) để biết các lỗi
> tích hợp đã sửa, yêu cầu bản ký và giới hạn kiểm chứng máy thật.

Astra dùng ứng dụng LocalDevVPN riêng cùng `AirliftFFI` để ghép đôi, kết nối dịch vụ thiết bị và ghi patch ngay trên iPhone. Astra không còn chứa packet-tunnel extension và không tự tạo cấu hình VPN.

## Thành phần đã tích hợp

| Thành phần | Trạng thái | Cách xác minh |
| --- | --- | --- |
| LocalDevVPN | Ứng dụng bên ngoài | Astra mở `localdevvpn://` và kiểm tra dịch vụ tại `10.7.0.1` |
| VPN tích hợp | Đã gỡ | Không còn `TunnelProv.appex`, target dependency hay quyền `packet-tunnel-provider` |
| RPPairing host | Đã tích hợp | `al_pairing_run_host` sinh identity, TXT record và PIN thật |
| Bonjour | Đã tích hợp | Chỉ publish `_remotepairing-pairable-host._tcp` với dữ liệu do RPPairing engine trả về |
| RSD/Lockdown | Đã tích hợp | Nhận diện route tới `10.7.0.1` qua interface tunnel thực tế, sau đó xác minh Lockdown `10.7.0.1:62078` |
| AFC + streaming zip + AirTraffic | Đã tích hợp | `al_exploit_run` bắt buộc xác nhận canary read-back trước khi `al_exploit_write_dir` chạy |
| Patch `.3105` | Đã nối vào router | Nhóm file theo container/thư mục rồi ghi từng batch qua AirTraffic khi bật AirLift |

## Luồng người dùng trên iOS 27+

1. Cài Astra và ứng dụng LocalDevVPN riêng.
2. Trong Astra, chọn **Pair trên máy** rồi **Bắt đầu phát sóng**.
3. Mở **Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển**, chọn **Pair with Astra** và nhập PIN Astra hiển thị.
4. Mở LocalDevVPN, bật tunnel, trở lại Astra và bấm kiểm tra cho đến khi RSD/Lockdown sẵn sàng.
5. Bật **Sử dụng AirLift Engine toàn bộ**, chọn patch và áp dụng.
6. Astra chỉ báo thành công sau khi canary được đọc lại đúng byte và phiên ghi AirTraffic trả về thành công.

## Giới hạn phải giữ rõ

- Khả năng khai thác phụ thuộc đúng bản iOS. Theo upstream AirCard-iOS, iOS 27.2 beta 3 trở lên đã vá đường AirTraffic này.
- `AirliftFFI` hiện không xuất API đọc một file tùy ý. Vì vậy Astra có thể xác minh canary và phiên ghi, nhưng không thể đọc lại từng file patch nếu sandbox không cho phép truy cập trực tiếp.
- Vì không đọc được file gốc qua AirLift, Astra không giả vờ rằng có thể sao lưu/khôi phục patch AirLift. Nút áp dụng lại và khôi phục được chặn cho trạng thái này.
- Kiểm tra tĩnh trong workspace đã đạt; build/link và runtime vẫn phải được xác nhận bằng Xcode và iPhone thật.

Nguồn `AirliftFFI`: AirCard-iOS commit `40640c4d827aeab8d798285b57d24fcf6be070d0`, giấy phép MIT. Xem `THIRD_PARTY_NOTICES.md`.
