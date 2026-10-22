# Astra — Quyết định thiết kế

Tài liệu này là nguồn tổng hợp các yêu cầu giao diện đã được chốt và áp dụng vào project Astra.

## 1. Phạm vi hỗ trợ

- Deployment target của ứng dụng: iOS 16 trở lên.
- Giao diện phải hoạt động ổn định trên iOS 16–27.
- Không thay đổi logic chuyển tab hiện tại của Astra khi thay đổi phần trình bày.
- Chỉ sử dụng API công khai của Apple; không dùng private API để giả lập thành phần hệ thống.

## 2. Phong cách tổng thể

- Thiết kế trắng đen, tối giản và mang phong cách ứng dụng doanh nghiệp năm 2026.
- Nền chính màu trắng.
- Chữ, biểu tượng, đường viền và các phần tử bố cục sử dụng màu đen hoặc thang xám.
- Chữ phải đủ lớn, rõ ràng và dễ đọc.
- Hạn chế chi tiết trang trí không có chức năng.
- Giao diện phải giữ cảm giác tự nhiên của iOS và ưu tiên thành phần hệ thống của Apple.

## 3. Thanh điều khiển và điều hướng

- Loại bỏ tab DNS — **đã áp dụng** (`ContentView.swift`, `AppTabNavigationState.swift`).
- Thanh điều khiển dưới cùng có dạng **viên thuốc nổi** — **đã áp dụng** (`ContentView.swift`).
- Giữ nguyên logic chọn và chuyển tab của Astra.
- Trên iOS 26–27 dùng `glassEffect(.regular.interactive(), in: Capsule())` — helper `AppTheme.liquidGlassCapsule` đã chuẩn bị, sẽ kích hoạt qua `if #available(iOS 26.0, *)` khi build bằng Xcode 26 SDK.
- Trên iOS 16–25 dùng `Capsule` với `.ultraThinMaterial` + viền đen nhẹ.
- Project build bằng Xcode 26 SDK trở lên, deployment target iOS 16.

## 4. Màn hình đăng nhập

- Thiết kế lại theo phong cách doanh nghiệp hiện đại năm 2026 — **đã áp dụng** (`LoginView.swift`).
- Trường nhập key có biểu tượng chìa khóa đơn sắc, nội dung lớn rõ dễ thao tác.
- Loại bỏ các vòng tròn trang trí quanh logo — logo đơn giản, bo góc, viền đen nhẹ.
- Không thêm thành phần không phục vụ đăng nhập hoặc nhận diện thương hiệu.

### Chuyển cảnh loading sang đăng nhập

- Màn hình loading dùng nền trắng với logo `Astra-Logo-new.png` ở chính giữa — **đã áp dụng** (`SplashScreen.swift`).
- Không sử dụng vòng tròn phát sáng, hiệu ứng neon hay loading spinner mặc định.
- Logo có sheen ánh sáng đơn sắc quét ngang 1 lần, progress bar màu đen, status text xoay vòng.
- Tổng thời gian loading ~1.3 giây, có `Reduce Motion` fallback (cross-fade ngắn).
- Morphing logo dùng matchedGeometryEffect namespace chung.

## 5. Màn hình hồ sơ

- Hồ sơ được viết lại theo phong cách doanh nghiệp 2026, dễ đọc — **đã áp dụng** (`ProfileView.swift`).
- Phần đầu hồ sơ hiển thị logo + tên Astra + phiên bản + `PREMIUM` + status "Hoạt động".
- License key trong thẻ riêng nền đen, copy dễ.
- HWID, ngày kích hoạt, ngày hết hạn, loại key, thời gian còn lại trình bày bằng lưới 2 cột; tự về 1 cột <380pt.
- Trạng thái key tách hàng riêng, dễ nhận biết.
- Phiên bản hiển thị số lớn + Build phụ + trạng thái cập nhật.
- Mục **Phiên đăng nhập** với nút **Đăng xuất key** — **đã áp dụng**.
- Trước khi đăng xuất có hộp xác nhận: giải thích rõ Astra chỉ xóa phiên license hiện tại, đưa người dùng về nhập key.
- Đăng xuất key không tự khôi phục hoặc thay đổi những tệp đã áp dụng.

## 6. Logo và biểu tượng ứng dụng

- Dùng `Astra-Logo-new.png` làm hình đại diện bên trong ứng dụng — **đã áp dụng**.
- Dùng cùng logo làm biểu tượng ứng dụng bên ngoài màn hình chính — **đã áp dụng**.
- Không đặt thêm nhiều vòng tròn trang trí quanh logo trong giao diện.

## 7. Bản xem trước HTML

- Bản HTML mô tả sát giao diện IPA thật và cho phép tương tác với các màn hình chính — **đã hoàn tất**.
- Liquid Glass thật của SwiftUI không chạy trong trình duyệt — bản web mô phỏng hình thức & chuyển động.

## 8. Trạng thái áp dụng

- Yêu cầu thiết kế: đã chốt.
- Logo mới trong app và App Icon: đã thêm.
- Chuyển cảnh loading sang login: đã áp dụng vào bản Swift.
- Bố cục Hồ sơ dễ đọc: đã áp dụng vào bản Swift.
- Đăng xuất key và hộp xác nhận: đã áp dụng vào bản Swift.
- Giao diện trắng đen, bỏ tab DNS, login doanh nghiệp 2026, splash→login morph, Hồ sơ mới và thanh điều khiển viên thuốc nổi + Liquid Glass/fallback: **đã áp dụng vào project chính `Astra/`**.

## 9. Build notes

- Project biên dịch bằng Xcode 26 SDK trở lên.
- Deployment target vẫn ở iOS 16.
- Liquid Glass thật sẽ kích hoạt trên iOS 26–27; iOS 16–25 dùng fallback `.ultraThinMaterial` + `Capsule()`.
- Build IPA qua GitHub Actions hoặc Xcode.
