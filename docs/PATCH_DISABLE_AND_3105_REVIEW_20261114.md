# Tắt công tắc khi chưa khôi phục được file; đối chiếu 3105

## Phạm vi thay đổi

Theo yêu cầu người dùng, một lần tắt trong danh mục sẽ thử khôi phục trước.
Nếu không khôi phục được, Astra lưu lựa chọn OFF riêng và ghi rõ file game
chưa được khôi phục, có thể vẫn còn tác dụng. Card có nút **Thử khôi phục file**.
API `restorePatch` vẫn chỉ thành công khi khôi phục thực sự; `disablePatch`
trả một trong hai kết quả `restored` hoặc `disabledWithoutRestore`.

Lựa chọn OFF gắn với catalog ID/variant và transaction: journal ID của direct,
hoặc operation ID của AirLift khi không có journal. Sửa sidecar của cùng journal
không làm mất OFF. Một transaction mới không kế thừa OFF của transaction trước.
Lựa chọn được giữ qua mở lại app và migration từ slug cũ.

Fallback chỉ ghi preference của công tắc và cờ recovery. Không xóa association,
backup, journal, sidecar, lịch sử AirLift; không đặt phase thành restored/off.
Trạng thái filesystem vẫn lấy từ giao dịch gốc và tiếp tục chặn tạo baseline
mới khi nghĩa vụ khôi phục còn tồn tại. Guard chạy trước download/associate
release mới của catalog item. Retry dùng cùng filesystem gate và cơ chế restore.
Cancellation/URL cancellation và auth revision thay đổi không được chuyển thành
OFF thành công. Lỗi khôi phục được ghi type/domain/code vào log, không ghi key
hoặc đường dẫn file trong log mới này.

Không sửa lõi apply/restore/atomic I/O của `PatchTransaction`, native exploit,
MCM/bad_query, chính sách OS/provider, worse_query, AirLift FFI, server, HWID,
license, crypto/TLS, version/build. Source vẫn 2.4 (37).

## So sánh source local với 3105-main

Nguồn đối chiếu là `3105-main/3105-main` trong workspace, không phải chứng nhận
runtime cho mọi bản iOS hoặc thiết bị.

| OS | Astra chọn | Quan hệ với upstream 3105 |
| --- | --- | --- |
| 16.x | Nhánh direct tương thích của Astra | Không nằm trong upstream support policy; không chạy kernel 17/18 hoặc bad_query từ 26 |
| 17.0–17.7.x | 3105; kernel theo policy | Theo phạm vi upstream |
| 18.0–18.7.1 | 3105; kernel theo policy | Theo phạm vi upstream |
| 26.0–26.6.1 | 3105/MHA-C2/bad_query, không kernel 17/18 | Theo phạm vi upstream |

Các OS ngoài các dải trên vẫn dùng provider do policy hiện hành chọn; lượt sửa
này không đổi routing và không thêm fallback gọi engine khác khi thất bại.

Pipeline direct của Astra giữ nền transaction của upstream: validate path →
copy file gốc/backup digest → journal prepared → atomic write → SHA read-back →
journal applied. Restore kiểm digest backup, snapshot trạng thái hiện tại để
rollback, copy backup/xóa file được tạo mới rồi cập nhật journal. Astra thêm
worker executor, auth/network cancellation permit, shared gate và provenance.

Bản sửa P06 trước đây giữ writable stage descriptor qua bước copy metadata,
ghi, fsync, close và rename, tránh phải mở lại file stage mang mode gốc 0444.
Điều đó cải thiện I/O so với upstream tại điểm này; không chứng minh quyền
truy cập native sẽ có trên mọi máy iOS 16.

## Những giới hạn còn tìm thấy, chưa thay đổi trong lượt này

1. **Crash consistency của sidecar:** journal prepared của transaction N được
   ghi trước engine sidecar N. Nếu ngắt/ghi sidecar thất bại ở khoảng đó, sidecar
   của transaction P trước có thể còn tồn tại. Latest receipt chọn N rồi guard
   thấy P/N khác nhau và báo `invalidRecord`. Đây là đường lỗi xác định được từ
   source; chưa có log chứng minh điện thoại trong ảnh gặp đúng trường hợp này.
2. **Giới hạn sidecar không đối xứng:** reader chặn trên 2 MiB nhưng writer chưa
   có cùng cap. Package đủ lớn có thể tạo record đã lưu mà reader từ chối.
   Không có bằng chứng package trong ảnh lớn tới mức này.
3. **Native MCM lease cache kế thừa upstream:** một retained lease có rootPath
   không rỗng được trả lại ngay trong cùng process. Container đổi UUID hoặc
   lease mất quyền cần được xử lý riêng; test MCM spy không xác nhận cache native.
4. **Phân biệt không tồn tại và lỗi quyền:** `FileManager.fileExists` Bool được
   dùng để quyết định có original backup. False không phân biệt đầy đủ ENOENT
   với lỗi quyền/stat; logic này được kế thừa upstream.
5. **Restore chưa có final read-back tương đương apply:** digest backup được
   kiểm trước copy, nhưng chưa tự đọc lại digest target/xác nhận removal trước
   khi commit restored. Test đọc bytes từ bên ngoài không thay bước xác minh đó.
6. **Kernel R/W không tự chứng minh pipeline ghi có quyền:** comment nhắc vnode
   redirect nhưng pipeline catalog hiện dùng FileManager/POSIX/MCM. Không thêm
   fallback exploit từ comment này.

Force-OFF giải quyết công tắc bị giữ ON; không sửa metadata hỏng, không tạo lại
bytes gốc và không làm mất tác dụng của patch trong game nếu restore chưa chạy.
Việc sửa sidecar cần chứng minh binding/target/backup đúng trước khi rebuild,
không được bỏ qua kiểm tra receipt hoặc xóa lịch sử để báo đã khôi phục.

## Kiểm chứng và giới hạn môi trường

Các test transaction trích body production, dùng filesystem tạm và boundary
native/transport giả lập. Kiểm tra force-OFF gồm byte của journal/backup/sidecar
được giữ, restart/migration, binding, retry, guard bật lại, auth/cancellation và
filesystem gate. Pipeline direct chạy thêm với SwiftCrypto thực trên Linux.

Kết quả local:

| Nhóm kiểm tra | Kết quả |
| --- | --- |
| Full client unittest | 74 bài: 68 pass, 6 skip cần macOS |
| Actual coordinator/catalog/provenance/gate/force-OFF | 128 checks pass; nằm trong unittest |
| Actual direct transaction, filesystem tạm, SwiftCrypto thực | 63 checks pass |
| Swift frontend parse 3 file runtime đã sửa | Pass |
| Production config validation | Pass |
| WebPreview JavaScript syntax và fixture control flow | Pass |
| Scope/hash audit | Lõi transaction và strict restore body giống baseline; upstream/native routing không đổi |

Log, baseline/hash/diff cuối nằm cục bộ tại
`scratch/patch-disable-audit-20261114/`. Các test Linux không xác nhận quyền ký,
Apple Keychain, MCM native, exploit hoặc hành vi filesystem trên iPhone. Cần
Xcode build và IPA ký thật trên thiết bị đại diện để xác nhận runtime.

Đây là thay đổi local; chưa push, chưa build IPA mới cho thay đổi force-OFF này.
