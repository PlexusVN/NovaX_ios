# BÁO CÁO TỔNG KẾT TÍCH HỢP `WORSE_QUERY` VÀO HỆ SINH THÁI ASTRA (NOVAX)

---

## 1. TỔNG QUAN
Dự án đã tích hợp thành công cơ chế **Sandbox Escape on-device `worse_query`** và thuật toán dò tìm inode nhanh **`pathleak`** (kế nhiệm từ `bad_query` của tác giả Taj C / forcequit) vào bản mã nguồn chính `Astra-Fixed` (`client/NovaX`).

### Kết quả đạt được:
1. **Loại bỏ hoàn toàn yêu cầu ghép nối máy tính (No-Pairing)** đối với các tác vụ patch mod game (Free Fire / Free Fire MAX) trên các phiên bản **iOS 26.0 – 26.7.2** và **iOS 27.0 – 27.2 Beta 2**.
2. **Khôi phục file gốc (Restore) trực tiếp ngay trên máy**: Trước đây khi dùng AirLift, thao tác tắt mod không thể khôi phục file gốc (báo lỗi `airLiftRestoreUnsupported`). Với `worse_query`, app có quyền POSIX trực tiếp vào container game để khôi phục bản sao lưu gốc hoặc dọn dẹp sạch sẽ khi tắt mod.
3. **Cơ chế dự phòng thông minh (Fallback)**: Nếu thiết bị chạy trên bản iOS cao hơn (như iOS 27.2 Beta 3+ trở lên khi Apple đã vá `containermanagerd`) hoặc chứng chỉ ký không có App Group, app sẽ tự động chuyển sang cơ chế AirLift.

---

## 2. CHI TIẾT CÁC FILE ĐÃ THÊM MỚI (NEW FILES)

| Đường dẫn file | Vai trò & Chức năng |
| :--- | :--- |
| `ThreeOneOSFive/exploit/worse_query.h` | Header C/Objective-C khai báo hàm `worse_query` và `worse_query_release`. |
| `ThreeOneOSFive/exploit/worse_query.m` | Triển khai kỹ thuật tráo đổi symlink tại `[AppGroup]/Library/Caches` và gửi query qua `libsystem_containermanager.dylib` để nhận Sandbox Extension Token từ kernel. |
| `ThreeOneOSFive/exploit/pathleak.h` | Header C/Objective-C khai báo hàm `pathleak`. |
| `ThreeOneOSFive/exploit/pathleak.m` | Triển khai thuật toán brute-force inode qua syscall `fsgetpath()` để định vị container theo Bundle ID cực nhanh mà không cần brute-force UUID. |
| `ThreeOneOSFive/helpers/WorseQueryHelper.swift` | Wrapper cấp cao bằng Swift: tự động nhận diện App Group khả dụng, quản lý vòng đời token sandbox, cung cấp API `readFile`, `writeFile`, `restoreFile`, `removeItem`, `withSandboxAccess`. |
| `Tests/test_worse_query_wiring.py` | Bộ test suite tự động (9 bài test) kiểm tra toàn vẹn liên kết mã nguồn, entitlements, bridging header và logic routing. |

---

## 3. CHI TIẾT CÁC FILE ĐÃ SỬA ĐỔI (MODIFIED FILES)

1. **`ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`**:
   * Khai báo `#import "exploit/worse_query.h"` và `#import "exploit/pathleak.h"` để Swift gọi trực tiếp các hàm C/Obj-C.

2. **`ThreeOneOSFive/ThreeOneOSFive.entitlements`**:
   * Bổ sung entitlement `com.apple.security.application-groups` với các nhóm:
     * `group.com.novax.app`
     * `group.cc.forcequit.worse-query`
     * `group.com.astra.app`

3. **`ThreeOneOSFive.xcodeproj/project.pbxproj`**:
   * Đăng ký đầy đủ `PBXBuildFile` (`3105W001`, `3105W002`, `3105W003`), `PBXFileReference` (`3105W011` -> `3105W015`), liên kết vào các group `exploit`, `helpers` và `PBXSourcesBuildPhase`.

4. **`ThreeOneOSFive/helpers/StorageEngineCoordinator.swift`**:
   * Ưu tiên số 1: Tự động phát hiện và định tuyến `writeFile`, `readFile` qua `WorseQueryHelper` nếu đường dẫn thuộc container game (`/var/mobile/Containers/Data/Application/*`).
   * Hỗ trợ `applyPatchProject` ghi trực tiếp hàng loạt file patch vào container mà không cần AirLift tunnel.

5. **`ThreeOneOSFive/helpers/ContainerStore.swift`**:
   * Nâng cấp `grantContainerAccess`: Thử cấp quyền bằng `WorseQueryHelper` trước khi gọi `bad_query` cũ.
   * Nâng cấp `resolveAppContainerPathByMetadataScan`: Sử dụng `WorseQueryHelper` và `getxattr` (`com.apple.containermanager.identifier`) để quét và nhận diện container game ngay lập tức mà không cần kernel r/w exploit.
   * Hỗ trợ đọc metadata plist trực tiếp qua token sandbox.

6. **`ThreeOneOSFive/helpers/FeaturePatchService.swift`**:
   * Cập nhật `installProtectedCodePatch`: Khi bật mod trên iOS 26/27 có `worse_query`, app lấy thư mục game trực tiếp, không bắt người dùng cắm cáp pair AirLift.
   * Cập nhật `restoreOriginalCodePatch`: Gỡ bỏ điều kiện chặn `.airLiftRestoreUnsupported`, cho phép khôi phục hoàn toàn file gốc và xóa file mod an toàn khi tắt chức năng.

7. **`ThreeOneOSFive/helpers/KernelExploit.swift`**:
   * Bổ sung hàm `supportsWorseQuery(major:minor:patch:build:)` và thuộc tính `currentSupportsWorseQuery`.
   * Cập nhật `pairingMode`: Trả về `.none` cho iOS 26.0–26.7.2 và iOS 27.0–27.2b2 khi có `worse_query`.
   * Cập nhật `storageMode`: Trả về `.direct` cho các phiên bản hỗ trợ `worse_query`.

8. **Giao diện (`AirLiftSettingsSection.swift`, `OnboardingView.swift`, `SettingsView.swift`)**:
   * Hiển thị trạng thái: **"KHÔNG CẦN GHÉP NỐI (WORSE_QUERY)"** trên màn hình cài đặt khi chạy trên thiết bị được hỗ trợ.

9. **`Tests/IOSCompatibilitySelfCheck.swift`**:
   * Cập nhật các điều kiện kiểm tra chính sách tương thích hệ thống khớp với luồng định tuyến mới.

---

## 4. DANH SÁCH CÁC PHIÊN BẢN IOS ĐƯỢC HỖ TRỢ VÀ PHƯƠNG THỨC TRUY CẬP FILE

| Phiên bản iOS | Build / Dải phiên bản | Phương thức truy cập | Yêu cầu Pairing? | Đọc / Ghi Container Game | Khôi phục gốc (Restore) |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **iOS 16** | 16.0 – 16.7.x | Direct POSIX (MHA-C2) | ❌ Không | ✅ Đọc & Ghi trực tiếp | ✅ Hỗ trợ đầy đủ |
| **iOS 17** | 17.0 – 17.7.x | Kernel Exploit / Direct | ❌ Không | ✅ Đọc & Ghi trực tiếp | ✅ Hỗ trợ đầy đủ |
| **iOS 18 (Cũ)** | 18.0 – 18.7.1 | Direct / Kernel R/W | ❌ Không | ✅ Đọc & Ghi trực tiếp | ✅ Hỗ trợ đầy đủ |
| **iOS 18 (Mới)** | 18.7.2 – 18.10 | AirLift Engine |  Có (File máy tính) | ✅ Ghi qua AirTraffic | ⚠️ Yêu cầu cài lại game |
| **iOS 26 (Cũ)** | 26.0 – 26.6.1 | Direct / **worse_query** | ❌ Không | ✅ Đọc & Ghi trực tiếp | ✅ Hỗ trợ đầy đủ |
| **iOS 26 (Mới)** | **26.6.2 – 26.7.2** | **worse_query** *(Mới)* | ❌ **Không cần Pairing** | ✅ **Đọc & Ghi trực tiếp** | ✅ **Hỗ trợ đầy đủ** |
| **iOS 27 (Beta 1-2)**| **27.0 – 27.1** | **worse_query** *(Mới)* | ❌ **Không cần Pairing** | ✅ **Đọc & Ghi trực tiếp** | ✅ **Hỗ trợ đầy đủ** |
| **iOS 27.2 Beta 1** | `24B5084k` | **worse_query** *(Mới)* | ❌ **Không cần Pairing** | ✅ **Đọc & Ghi trực tiếp** | ✅ **Hỗ trợ đầy đủ** |
| **iOS 27.2 Beta 2** | `24B5089g` | **worse_query** *(Mới)* | ❌ **Không cần Pairing** | ✅ **Đọc & Ghi trực tiếp** | ✅ **Hỗ trợ đầy đủ** |
| **iOS 27.2 Beta 3+**| `24B5099f` trở lên | AirLift (Dự phòng tự động) |  Có (On-Device / File) | ✅ Ghi qua AirTraffic | ⚠️ Yêu cầu cài lại game |

---

## 5. LƯU Ý KHI KÝ VÀ PHÁT HÀNH ỨNG DỤNG (IPA SIGNING)

Để cơ chế `worse_query` hoạt động trên máy người dùng, **file chứng chỉ / profile ký phải hỗ trợ App Group**:
* **ESign / KSign / Feather / Scarlet:** Đảm bảo khi ký IPA có tích chọn giữ lại hoặc cấp quyền App Group (`com.apple.security.application-groups`).
* **Chứng chỉ Doanh nghiệp (Enterprise Cert):** Cấu hình App Group Identifier trùng với một trong các ID:
  * `group.<bundle_id_của_app>`
  * `group.com.novax.app`
  * `group.cc.forcequit.worse-query`
* Nếu chứng chỉ không có App Group, `WorseQueryHelper.isAvailable` sẽ tự động trả về `false`, và Astra sẽ tự chuyển sang luồng AirLift dự phòng mà không làm crash app.

---

## 6. KẾT QUẢ KIỂM THỬ
* **`test_worse_query_wiring.py`:** **9/9 PASS** (Kiểm tra file C/Obj-C, Swift Helper, PBXProj, Entitlements, StorageEngineCoordinator, ContainerStore, FeaturePatchService, ExploitSupportPolicy).
* **`test_ios16_compatibility.py`:** **13/13 PASS** (Không gây hồi quy native compatibility).
* **`test_license_verification_wiring.py`:** **3/3 PASS** (Bảo toàn nguyên vẹn hệ thống xác thực Auth).

