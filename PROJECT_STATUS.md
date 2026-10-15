# NovaX — trạng thái tích hợp on-device AirLift

NovaX dùng ứng dụng LocalDevVPN riêng cùng `AirliftFFI` để ghép đôi, kết nối dịch vụ thiết bị và ghi patch ngay trên iPhone. NovaX không còn chứa packet-tunnel extension và không tự tạo cấu hình VPN.

## Thành phần đã tích hợp

| Thành phần | Trạng thái | Cách xác minh |
| --- | --- | --- |
| LocalDevVPN | Ứng dụng bên ngoài | NovaX mở `localdevvpn://` và kiểm tra dịch vụ tại `10.7.0.1` |
| VPN tích hợp | Đã gỡ | Không còn `TunnelProv.appex`, target dependency hay quyền `packet-tunnel-provider` |
| RPPairing host | Đã tích hợp | `al_pairing_run_host` sinh identity, TXT record và PIN thật |
| Bonjour | Đã tích hợp | Chỉ publish `_remotepairing-pairable-host._tcp` với dữ liệu do RPPairing engine trả về |
| RSD/Lockdown | Đã tích hợp | Kiểm tra `10.7.0.1:49152` hoặc Lockdown `10.7.0.1:62078` |
| AFC + streaming zip + AirTraffic | Đã tích hợp | `al_exploit_run` bắt buộc xác nhận canary read-back trước khi `al_exploit_write_dir` chạy |
| Patch `.3105` | Đã nối vào router | Nhóm file theo container/thư mục rồi ghi từng batch qua AirTraffic khi bật AirLift |

## Luồng người dùng trên iOS 27+

1. Cài NovaX và ứng dụng LocalDevVPN riêng.
2. Trong NovaX, chọn **Pair trên máy** rồi **Bắt đầu phát sóng**.
3. Mở **Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển**, chọn **Pair with NovaX** và nhập PIN NovaX hiển thị.
4. Mở LocalDevVPN, bật tunnel, trở lại NovaX và bấm kiểm tra cho đến khi RSD/Lockdown sẵn sàng.
5. Bật **Sử dụng AirLift Engine toàn bộ**, chọn patch và áp dụng.
6. NovaX chỉ báo thành công sau khi canary được đọc lại đúng byte và phiên ghi AirTraffic trả về thành công.

## Giới hạn phải giữ rõ

- Khả năng khai thác phụ thuộc đúng bản iOS. Theo upstream AirCard-iOS, iOS 27.2 beta 3 trở lên đã vá đường AirTraffic này.
- `AirliftFFI` hiện không xuất API đọc một file tùy ý. Vì vậy NovaX có thể xác minh canary và phiên ghi, nhưng không thể đọc lại từng file patch nếu sandbox không cho phép truy cập trực tiếp.
- Vì không đọc được file gốc qua AirLift, NovaX không giả vờ rằng có thể sao lưu/khôi phục patch AirLift. Nút áp dụng lại và khôi phục được chặn cho trạng thái này.
- Kiểm tra tĩnh trong workspace đã đạt; build/link và runtime vẫn phải được xác nhận bằng Xcode và iPhone thật.

Nguồn `AirliftFFI`: AirCard-iOS commit `40640c4d827aeab8d798285b57d24fcf6be070d0`, giấy phép MIT. Xem `THIRD_PARTY_NOTICES.md`.
