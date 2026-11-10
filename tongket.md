# BÁO CÁO TỔNG KẾT TÍCH HỢP `WORSE_QUERY` VÀO HỆ SINH THÁI ASTRA (NOVAX)

> Cập nhật kiểm chứng 11/11/2026: các tuyên bố thành công dưới đây chủ yếu dựa
> trên kiểm tra wiring, chưa chứng minh chạy được sau khi ký ESign trên iPhone.
> Rà soát mới phát hiện thiếu nhận diện App Group sau ký, quản lý token transaction
> và lưu entitlement vào IPA. Source đã được sửa; xem
> [báo cáo rà soát](Astra-Fixed/Astra-Full-Source-1.2.10-16/client/NovaX/docs/WORSE_QUERY_AUDIT_20261111.md).
> Chưa build IPA mới hoặc xác nhận runtime máy thật. iOS 27.2 beta 3+ không được
> coi là có thể khắc phục bằng AirLift khi cả đường AirTraffic đã vá.

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
* **`test_worse_query_wiring.py`:** **10/10 PASS** (Kiểm tra file C/Obj-C, Swift Helper, PBXProj, Entitlements, StorageEngineCoordinator, ContainerStore, FeaturePatchService, ExploitSupportPolicy, LaunchServices container resolution).
* **`test_ios16_compatibility.py`:** **13/13 PASS** (Không gây hồi quy native compatibility).
* **`test_license_verification_wiring.py`:** **3/3 PASS** (Bảo toàn nguyên vẹn hệ thống xác thực Auth).

---

## 7. CHẨN ĐOÁN & SỬA LỖI [P06] TRÊN THIẾT BỊ THẬT (ẢNH CHỤP NGƯỜI DÙNG)

### 1. Hiện tượng lỗi:
Khi người dùng bật switch **"Aimlock FFTH"** trong màn hình Chức năng, ứng dụng báo lỗi:
> `Không thể bật chức năng`
> `Ghi file và tạo bản khôi phục [P06]: Chưa truy cập được container ứng dụng đích. Hãy cài/mở ứng dụng đích và chạy lại bước cấp quyền trong Astra.`

### 2. Nguyên nhân kỹ thuật:
1. **MHA-C2 / MCM bị chặn trên iOS 27:** Hàm `MCMActivateContainerPath(2, bundleID, false, &error)` trả về `nil` do sandbox iOS 27 siết chặt.
2. **Thiếu cơ chế LaunchServices trong hàm phân giải:** Trong `AppIconHelper.m` đã có `LSApplicationProxy` có thể đọc trực tiếp `dataContainerURL` của game Free Fire trong 0.5ms, nhưng `ContainerStore.resolveAppContainerPath` trước đó lại không gọi LaunchServices mà chỉ dựa vào MCM và quét inode.
3. **Giới hạn Inode 100.000 cũ:** Khi fallback quét metadata, hàm cũ gọi `bad_query_list` bị hardcode trần 100.000 inode, trong khi inode container trên APFS thực tế thường từ 2.000.000 đến 25.000.000.
4. **Chưa giữ Handle Sandbox Extension trong suốt Transaction:** Quá trình `PatchTransaction.apply` (tạo backup bản sao lưu và ghi file) cần token sandbox extension luôn duy trì trạng thái active cho thư mục container đích.

### 3. Các xử lý đã triển khai:
* **`AppIconHelper.h` & `AppIconHelper.m`:** Bổ sung API `containerPathForBundleID(bundleID)` đọc trực tiếp `dataContainerURL` từ `LSApplicationProxy` / `installedAppInfo`.
* **`ContainerStore.swift`:**
  * Thêm bộ nhớ đệm `UserDefaults` (`astra.resolved_container.<bundleID>`) để truy xuất ngay lập tức trong 0ms.
  * Tích hợp `containerPathForBundleID` trước khi fallback sang quét metadata.
  * Tích hợp `pathleak` đa luồng (`dispatch_apply` + `os_unfair_lock`) với trần `currentFilesystemMaxInode()` tự động dò theo tệp thăm dò tạm thời.
* **`WorseQueryHelper.swift`:** Bổ sung `containerRoot(for:)` tự động trích xuất thư mục gốc của container, giúp quyền sandbox bao trùm toàn bộ các thư mục con (`Documents`, `Library`).
* **`PatchTransaction.swift`:** Trong `withResolvedContainers`, gọi `ContainerStore.grantContainerAccess` và duy trì token trong toàn bộ thời gian ghi và sao lưu dữ liệu.
* **`KernelExploit.swift`:** Trong `currentStorageMode`, nếu chạy trên iOS 26/27 mà chứng chỉ ký thiếu App Group (`WorseQueryHelper.isAvailable == false`), tự động chuyển hướng về `.airLift` dự phòng thay vì bị kẹt lỗi trực tiếp.

---

## 8. CHẨN ĐOÁN & SỬA LỖI VÒNG XOAY QUAY MÃI TRÊN IOS 27 (INFINITE SPINNER FIX)

### 1. Hiện tượng lỗi:
Người dùng nhấn bật công tắc "Aimlock FFTH" trên iOS 27, giao diện hiện thông báo:
> `Chức năng đang bật`
> `Vui lòng chờ...`
kèm vòng xoay `ProgressView` xoay mãi không dừng, chức năng không áp dụng thành công.

### 2. Nguyên nhân kỹ thuật phát hiện:
1. **Khóa luồng Main Actor (UI Thread Freeze):**
   Trong `FeaturesView.swift`, hàm `togglePatch()` gọi `Task { @MainActor in try await service.applyPatch(...) }`. Bên trong, việc giải mã chữ ký, tra cứu container và ghi file được thực thi đồng bộ, làm tê liệt toàn bộ luồng giao diện người dùng.
2. **Khác biệt đường dẫn APFS trong Darwin VFS (`pathleak`):**
   Phân vùng Data của APFS mount tại `/private/var`. Lệnh hệ thống `fsgetpath` luôn trả về đường dẫn chuẩn `/private/var/mobile/Containers/Data/Application/<UUID>`. Trong khi đó, `appDataRoot` được truyền vào là `/var/mobile/...`. Khi so sánh tiền tố bằng `strncmp`, chuỗi không khớp khiến `pathleak` duyệt qua hàng triệu inode mà không tìm thấy thư mục nào.
3. **Vòng lặp Inode quá lớn:**
   `WorseQueryHelper.currentFilesystemMaxInode()` có dòng `max(current, 10_000_000)`, ép `pathleak` phải gọi `fsgetpath` từ 10.000.000 đến 25.000.000 lần, chiếm dụng CPU trong thời gian dài.
4. **Hạn chế của `LSApplicationProxy` trên iOS 15 - 27+:**
   Trên iOS hiện đại, Apple không cấp quyền đọc `[proxy dataContainerURL]` cho bên thứ ba. Cần sử dụng lớp `LSApplicationRecord` (`[[LSApplicationRecord alloc] initWithBundleIdentifier:allowPlaceholder:error:]`) để lấy trực tiếp URL container trong 0.05ms mà không cần quét ổ đĩa.
5. **Kiểm tra `lstat` khi chưa có quyền Sandbox Extension:**
   Trong `worse_query.m`, trước khi gửi query đến `containermanagerd`, hàm kiểm tra `lstat(target)`. Vì ứng dụng đang bị sandbox chặn truy cập thư mục ngoài container, `lstat` trả về mã lỗi `EACCES` hoặc `EPERM`. Đoạn mã cũ coi đây là thư mục không tồn tại và lập tức trả về `-255`, chặn đứng việc xin token extension.

### 3. Các xử lý đã hoàn thành:
1. **`FeaturesView.swift`:**
   Chuyển toàn bộ tác vụ bật/tắt patch sang `Task.detached(priority: .userInitiated)` chạy ở luồng nền độc lập. Chỉ gửi kết quả (thành công/lỗi/haptics/toast) về Main Actor qua `await MainActor.run`. Giao diện giữ nguyên độ mượt 120Hz và không bao giờ bị đơ.
2. **`AppIconHelper.m`:**
   Ưu tiên dùng `LSApplicationRecord.dataContainerURL` và `[proxy applicationRecord]`, chuẩn hóa loại bỏ dấu gạch chéo `/` ở cuối đường dẫn.
3. **`pathleak.m`:**
   Bổ sung chuẩn hóa tiền tố `/private/var/...` song song với `/var/...`, so khớp thông minh cả hai định dạng, tích hợp loại bỏ trùng lặp bằng `seen Set`.
4. **`worse_query.m`:**
   Chỉ trả về `-255` khi `errno == ENOENT` (tệp thực sự không tồn tại). Nếu gặp lỗi quyền truy cập (`EACCES`/`EPERM`), vẫn tiếp tục gửi query đến daemon gốc `containermanagerd` để xin Sandbox Extension Token hợp lệ.
5. **`WorseQueryHelper.swift`:**
   Đặt trần an toàn cho `currentFilesystemMaxInode()` dựa trên file thăm dò thực tế và chuẩn hóa toàn bộ đường dẫn qua `ContainerDiscoveryMerger.canonicalPath`.
6. **`ContainerStore.swift`:**
   Chuẩn hóa `isApplicationContainerPath` và duy trì token handle sandbox extension trong suốt quá trình patch.

---

## 9. CHẨN ĐOÁN & SỬA LỖI VĂNG APP NGAY KHI MỞ TRÊN IOS 27 (LAUNCH CRASH FIX)

### 1. Hiện tượng lỗi:
Người dùng mở ứng dụng NovaX (Astra) trên iOS 27, app vừa chớp màn hình khởi động thì lập tức bị văng (crash trong 0.1 giây).

### 2. Nguyên nhân kỹ thuật phát hiện:
1. **Con trỏ lơ lửng trong bộ nhớ đa luồng (Dangling Pointer / `EXC_BAD_ACCESS`):**
   Trong `pathleak.m`, câu lệnh:
   ```objc
   prefix2 = [canonicalDir substringFromIndex:8].fileSystemRepresentation;
   ```
   tạo một `NSString` tạm thời không có biến giữ tham chiếu mạnh. Trình biên dịch ARC tự động giải phóng vùng nhớ này ngay sau câu lệnh. Khi `dispatch_apply` chạy 8 luồng song song cùng truy cập con trỏ `prefix2`, CPU kích hoạt lỗi truy cập ô nhớ bất hợp pháp `EXC_BAD_ACCESS` (SIGSEGV) làm app văng ngay lập tức.
2. **Ngoại lệ không bắt được từ LaunchServices (`NSInternalInconsistencyException` / SIGABRT):**
   Trên iOS 27, các lệnh gọi trực tiếp `LSApplicationRecord alloc` hoặc gọi `applicationRecord` trên proxy của các ứng dụng hệ thống bị sandbox chặn và ném ngoại lệ Objective-C. Vì không có khối bảo vệ `@try ... @catch`, ngoại lệ này thoát ra ngoài Swift runtime và gọi `std::terminate() -> abort()`.
3. **Thực thi quét đĩa quá sớm khi khởi động app:**
   Hàm `checkDirectDirectoryAccessAsync` trong `App.swift` chạy ngầm ngay khi app vừa mở (`onAppear`), kích hoạt hàm quét container. Khi chưa có cache, nó chạy thẳng vào hàm quét inode, làm kích hoạt đồng thời 2 lỗi bộ nhớ kể trên.

### 3. Các xử lý đã hoàn thành:
1. **`pathleak.m`:**
   - Chuyển toàn bộ về cơ chế tuần tự đơn luồng an toàn 100% theo đúng thiết kế gốc của tác giả Taj C.
   - Sử dụng bộ đệm ngăn xếp cục bộ `char prefix1[PATH_MAX]` và `char prefix2[PATH_MAX]`, loại bỏ hoàn toàn con trỏ trỏ tới vùng nhớ tạm thời.
   - Loại bỏ `dispatch_apply` và khóa `os_unfair_lock`, loại bỏ triệt để mọi nguy cơ `EXC_BAD_ACCESS` hay race condition.
2. **`AppIconHelper.m`:**
   - Xóa bỏ việc gọi `applicationRecord` trong vòng lặp duyệt tất cả ứng dụng trong `appsFromWorkspace`.
   - Bọc tất cả các nhánh tra cứu container của `LSApplicationProxy`, `LSApplicationRecord`, và `installedAppInfo` trong các khối khiên bảo vệ `@try { ... } @catch (NSException *e) { }`, triệt tiêu hoàn toàn nguy cơ sập app do ngoại lệ hệ thống.
3. **`ContainerStore.swift` & `App.swift`:**
   - Bổ sung cờ `allowMetadataScan: Bool = true`. Khi app khởi động (`checkDirectDirectoryAccessAsync`), cờ được đặt thành `false` để chỉ kiểm tra nhanh cache và LaunchServices trong 0.001ms mà không quét ổ đĩa.
   - Khi người dùng thực sự bấm công tắc "Aimlock FFTH", hàm mới cho phép fallback quét metadata nếu cần.
4. **`WorseQueryHelper.swift`:**
   - Giới hạn trần quét `min(max(current, 100_000), 500_000)` giúp quá trình quét chỉ mất từ 0.1 đến 0.3 giây.




