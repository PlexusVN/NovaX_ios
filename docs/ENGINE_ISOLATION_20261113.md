# Cô lập 3105, worse_query và AirLift — 13/11/2026

## Phạm vi

Sửa điều phối client, tìm container, provenance của giao dịch và các điều khiển
engine. Không thay native exploit/FFI archive, certificate/profile, server/SQL,
license/HWID, identity recovery, download crypto, TLS pins hoặc version/build.
Source vẫn là Astra 2.4 (37); các IPA đã build trước thay đổi này không chứa nó.

Snapshot trước sửa và diff/hash được lưu cục bộ tại
`scratch/engine-isolation-20261113/`, không nằm trong repo app.

## Một policy, một provider

`ExploitSupportPolicy` tiếp tục là nguồn quyết định duy nhất. Permissions,
pairing/VPN hoặc preference cũ không chuyển engine khi thất bại.

| OS/build | Provider | Pairing |
| --- | --- | --- |
| 16.x | Nhánh direct của Astra/3105; không kernel | Không |
| 17.0–17.7.x; 18.0–18.7.1 | 3105, kernel trong phạm vi policy | Không |
| 18.7.2+ thuộc major 18 | AirLift | Nhập file |
| 26.0–26.6.1 | 3105/MHA-C2/bad_query | Không |
| 26.6.2–26.7.2 | worse_query | Không; App Group phải dùng được |
| 26.7.3+ thuộc major 26 | AirLift | Nhập file |
| 27.0.0 với 24A5355q/24A5370h/24A5380h/24A5390f | 3105 | Không |
| 27.0/27.1 còn lại, gồm 27.0.1; 27.2.0 | worse_query | Không; App Group phải dùng được |
| 27.0.0 không đọc được build | Chặn vì chưa phân biệt được provider | Không |
| 17.8+, 27.2.1+, 27.3+ và major khác | Unsupported | Không |

Các dải này là policy theo source tham khảo, không chứng minh mọi build/SoC đã
chạy thành công trên iPhone. iOS 18/26 AirLift vẫn là dải mở theo policy trước;
không tự mở thêm major. Nhãn Settings làm rõ giới hạn này. Unknown build chỉ
bị chặn ở 27.0.0, nơi cần phân biệt bốn beta 3105; 27.0.1 không bị gán AirLift.

AirLift public entry points, lifecycle callback và điểm enqueue FFI đều kiểm
provider. Manager inactive không đọc/xóa pairing hoặc probe peer. Giao diện
chỉ hiển thị AirLift trên provider đó; toggle override được thay bằng nhãn.
Readiness ban đầu đòi health xác thực, không chỉ có pairing file/route.
Pairing đã lưu vẫn được giữ khi inactive; persisted setup bypass không thay
canary/transport checks trước mỗi lần ghi.

## worse_query: target và bằng chứng truy cập

Preparation nhận tập Bundle ID từ capability map của app/caller. Lõi discovery
không hardcode Free Fire và không gọi MCM/LaunchServices/AirLift khi thất bại.
Initial gate chỉ cần ít nhất một target dùng được; dừng sau chunk đầu có target
khi không yêu cầu full scan. Lazy preparation kiểm từng target cần cho thao tác,
không để cache của A làm bỏ qua việc tìm B.

Một root chỉ được publish sau khi có directory read và identifier đúng target
dưới token đang giữ. Counter tách handle/read/identifier/match. Xattr đọc theo
độ dài, kiểm UTF-8/NUL và identifier; metadata được kiểm độc lập. Xattr invalid
có thể fallback metadata, hai nguồn hợp lệ mâu thuẫn thì loại root. Hai UUID
cùng target được phát hiện trong một lượt cũng bị loại thay vì chọn UUID cuối.

Cache được re-identify trước dùng. Hết `probe inode + 2048` là hết cửa sổ ước
lượng, không chứng minh app chưa cài hay đã quét toàn filesystem. Cancellation
có thể tiếp tục chunk hiện tại trong cùng process/OS/group/target set; restart
không tin root chưa được xác minh. Không ghi file thử vào container game.

## Giao dịch, lịch sử và khôi phục

Record atomic `.engine-applications/<projectID>.plist` lưu schema, engine,
operation/journal ID, targets, baseline, phase và số batch xác nhận. Record không
chứa payload plaintext. Direct ghi record bound với journal trước target mutation;
AirLift ghi `writing` trước dispatch đầu tiên. Lỗi hoặc kết quả không rõ giữ
`writing/recoveryRequired`, không hiển thị OFF giả.

Filesystem gate giữ một chủ sở hữu qua apply/restore và các await. Catalog,
coordinator, các entry point injection cũ và project library dùng cùng gate;
core nội bộ nhận operation token để tránh acquire lồng. Direct filesystem work
vẫn chạy qua worker executor, không chuyển lên MainActor vì đi qua gate.

Swift deadline không giải phóng staging/gate/busy khi native AirLift còn dùng
payload. App đợi native completion thực. Nếu native bị treo ngoài timeout nội
bộ, thao tác tiếp theo vẫn bị chặn; không có giả định đã rollback.

Restore dựa vào provenance và journal, rồi kiểm provider hiện tại có thể thực
hiện hay không. Record direct bound mới không bị boolean AirLift lịch sử lấn át.
Legacy chỉ có journal + marker AirLift không chứng minh thứ tự/baseline thì bị
đánh ambiguous và giữ backup. Marker AirLift cũ không có target record chặn tạo
baseline mới, kể cả project UUID khác: không thể biết file nào đã bị sửa. Đây là
hạn chế có chủ đích; không tự xóa marker/backups để báo máy đã sạch.

`capturedPriorState` chỉ là bytes trước giao dịch, không chứng nhận game gốc.
Thông báo thành công nói khôi phục bản đã sao lưu trước lần áp dụng. AirLift
không có arbitrary read/backup, nên không tuyên bố restore được dữ liệu gốc.
Package có empty/independent directories vượt capability AirLift bị từ chối
trước ghi; direct transaction vẫn hỗ trợ directories.

## Kiểm chứng và phát hành

Các test mới trích production policy, coordinator, restore, provenance/gate,
AirLift entry points/continuation và identity evidence. Expected OS boundary
matrix độc lập tránh chỉ so các hàm cùng gọi một policy. Test thực thi với
native/transport fixtures xác nhận không gọi chéo, canceled callback không
publish, partial write không OFF và payload sống đến native completion.

Đã chạy thêm full production direct transaction với P-256/SHA thực từ Apple
SwiftCrypto trên Linux và thư mục tạm: backup/write/restore/rollback/provenance.
WQ preparation/session/monitor thực chạy với boundary Darwin/Combine/native
cô lập trên 26.6.2, 26.7.0, 26.7.2, 27.0.1. Các artifact Linux chỉ thay boundary
OS để kiểm control flow, không thay production code cho app iOS.

Cần CI macOS/Xcode và IPA ký thật để xác nhận SwiftUI/Combine/Security/native
linkage và quyền App Group, cùng thiết bị đại diện từng provider. Không gọi
test fixture thành công là chứng nhận mọi iOS/build. Không có push/deploy,
thay chứng chỉ hay cập nhật DB trong lần sửa source này.

Kết quả cục bộ cuối:

| Nhóm | Kết quả |
| --- | --- |
| Python unittest toàn client | 74 bài: 67 pass, 7 skip cần macOS |
| Ma trận boundary độc lập từ policy production | 260 assertions pass; nằm trong unittest |
| AirLift entry point/callback/native lifetime thực | 37 checks pass; nằm trong unittest |
| Coordinator/catalog restore/provenance/gate thực | 26 checks pass; nằm trong unittest |
| Container identity evidence production | 34 assertions pass; nằm trong unittest |
| So policy với snapshot 3105 | 24.696 tổ hợp OS/build pass |
| Full direct transaction với file tạm và SwiftCrypto | 14 checks pass |
| Full WQ preparation với OS boundary fixture | Pass trên 26.6.2/26.7.0/26.7.2/27.0.1 |
| Identity recovery regression trước đó | 219 assertions pass |
| Swift frontend parse các file runtime đã sửa | Pass; chưa thay thế Xcode typecheck/link |

WebPreview local đã đồng bộ provider Settings, nhãn/counter và source manifest;
`node --check` pass. Snapshot/diff và log cụ thể nằm trong artifact cục bộ nói
trên. Không có kết quả native exploit hoặc quyền ký máy thật trong các số này.
