# Behavior Tree A/B Benchmark Results: GDScript vs Rust GDExtension (Lượt đo CHỐT)

Báo cáo đo đạc và so sánh hiệu năng trực tiếp (A/B testing) giữa bản **GDScript thuần** (baseline commit `967bfa1`) và bản **Rust GDExtension** (release build sau tối ưu hóa FFI & `from_dict`) trên cùng một bộ test harness portable (`tests/bench_ab.gd`) và cùng môi trường phần cứng.

- **Ngày đo:** 23/10/2026 (Lượt đo CHỐT sau khi tối ưu engine)
- **Tình trạng:** Engine Rust đã được tối ưu hóa `from_dict`, cache schema và overhead dispatch loop.

---

## 1. Môi trường thực nghiệm

- **CPU:** Intel(R) Core(TM) i5-6500T CPU @ 2.50GHz (4 cores / 4 threads)
- **OS / Kernel:** Linux x86_64 (Ubuntu, kernel 6.8.0-142-generic)
- **Godot Version:** `4.7.2.stable.official.ed1daf0bf` (chạy `--headless`)
- **GDScript Baseline:** Commit `967bfa1` trong git worktree `/tmp/bt-gd-baseline` (runtime thuần GDScript, không có `addons/godot_bt_native`)
- **Rust Native Runtime:** Repo chính `/home/hazeruno/IT/workspace/godot-behavior-tree`, binary `addons/godot_bt_native/bin/libgodot_bt_native.release.so` biên dịch với profile `release` (`cargo build --release`)
- **Phương pháp đo:**
  - Harness portable `tests/bench_ab.gd` chỉ dùng public API có ở cả hai bản (`BTTree`, `BTTask`, `BTComposite.BTSequence`, `BTDecorator.BTRepeater`, `BTRunner`, `BTTaskRegistry`, `BTStatus`).
  - Warmup: 500 tick khởi động trước khi đo.
  - Measurement: 5,000 tick đo liên tục cho mỗi cấu hình tick.
  - Serialization: 5 lần chạy lặp lại đo `from_dict` và `to_dict`, lấy trung vị trong mỗi lượt.
  - Chạy toàn bộ suite 3 lượt độc lập cho mỗi runtime, lấy **trung vị (median)** của từng metric để triệt tiêu nhiễu OS scheduler.

---

## 2. Kết quả đo Tick Execution CHỐT (µs/tick & ticks/s)

Bảng số liệu lấy trung vị từ 3 lượt chạy độc lập (warmup 500 ticks, measure 5,000 ticks):

| Cấu hình | Quy mô | Runtime | p50 (µs) | p90 (µs) | p99 (µs) | Throughput (ticks/s) | Hệ số nhanh hơn (p50) | Hệ số throughput |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **leaf1** (1-Leaf under Repeater) | 2 nodes | **GDScript**<br>**Rust Native** | 14.00<br>**7.00** | 15.00<br>**7.00** | 19.00<br>**7.00** | 70,279.0/s<br>**139,198.2/s** | **2.00x** | **1.98x** |
| **seq3** (Sequence + 3 Leaves) | 5 nodes | **GDScript**<br>**Rust Native** | 37.00<br>**18.00** | 37.00<br>**19.00** | 52.00<br>**32.00** | 26,579.6/s<br>**53,230.6/s** | **2.06x** | **2.00x** |
| **commander800** (RTS Commander JSON) | 850 nodes | **GDScript**<br>**Rust Native** | 806.00<br>**474.00** | 1,232.00<br>**769.00** | 1,376.00<br>**877.00** | 1,125.4/s<br>**1,868.0/s** | **1.70x** | **1.66x** |
| **commander2000** (RTS Commander JSON) | 2,000 nodes | **GDScript**<br>**Rust Native** | 1,670.00<br>**997.00** | 3,015.00<br>**1,929.00** | 3,391.00<br>**2,137.00** | 500.9/s<br>**808.1/s** | **1.68x** | **1.61x** |

---

## 3. Kết quả đo Tree Serialization CHỐT: `from_dict` & `to_dict` (ms)

Bảng đo trung vị thời gian nạp cây từ Dictionary và tuần tự hóa ngược lại Dictionary:

| Cấu hình | Số node | Metric | GDScript Baseline | Rust Native | Tỷ lệ (GDScript / Rust) | Ghi chú sau tối ưu |
| :--- | :---: | :--- | :---: | :---: | :---: | :--- |
| **commander800** | 850 | `from_dict` | 59.55 ms | 50.62 ms | **1.18x** | **Rust nhanh hơn GDScript** (trước: 262 ms -> 50.6 ms) |
| | 850 | `to_dict` | 7.04 ms | 8.24 ms | **0.85x** | Xấp xỉ tương đương (~1 ms chênh lệch) |
| **commander2000** | 2,000 | `from_dict` | 240.09 ms | 220.97 ms | **1.09x** | **Rust nhanh hơn GDScript** (trước: 913 ms -> 221 ms) |
| | 2,000 | `to_dict` | 19.11 ms | 19.46 ms | **0.98x** | Hoàn toàn tương đương |

---

## 4. Dữ liệu chi tiết 3 lần chạy (Kiểm tra tính nhất quán số đo)

### GDScript Baseline (`/tmp/bt-gd-baseline`):
- **leaf1:**
  - p50: `[14.0, 14.0, 14.0]` µs (0% dao động)
  - ticks/s: `[71263.6, 70279.0, 67084.4]` (dao động < 3.2%)
- **seq3:**
  - p50: `[36.0, 37.0, 37.0]` µs (dao động < 2.7%)
  - ticks/s: `[27185.7, 26579.6, 25637.6]` (dao động < 3.5%)
- **commander800:**
  - p50: `[806.0, 807.0, 803.0]` µs (dao động < 0.5%)
  - ticks/s: `[1125.3, 1125.4, 1131.3]` (dao động < 0.5%)
  - from_dict: `[64.21, 59.55, 58.67]` ms (dao động < 4.8%)
  - to_dict: `[7.58, 6.87, 7.04]` ms (dao động < 5.8%)
- **commander2000:**
  - p50: `[1681.0, 1670.0, 1663.0]` µs (dao động < 0.7%)
  - ticks/s: `[495.7, 500.9, 502.0]` (dao động < 1.0%)
  - from_dict: `[240.09, 240.67, 237.33]` ms (dao động < 1.1%)
  - to_dict: `[19.00, 19.12, 19.11]` ms (dao động < 0.6%)

### Optimized Rust Native (`/home/hazeruno/IT/workspace/godot-behavior-tree`):
- **leaf1:**
  - p50: `[7.0, 7.0, 7.0]` µs (0% dao động, nhanh hơn 2x)
  - ticks/s: `[139198.2, 139739.0, 138970.0]` (dao động < 0.5%, gấp đôi throughput)
- **seq3:**
  - p50: `[18.0, 18.0, 18.0]` µs (0% dao động, nhanh hơn 2.06x)
  - ticks/s: `[53120.3, 53469.1, 53230.6]` (dao động < 0.6%, gấp đôi throughput)
- **commander800:**
  - p50: `[474.0, 474.0, 485.0]` µs (dao động < 2.3%)
  - ticks/s: `[1868.0, 1881.9, 1831.3]` (dao động < 1.9%)
  - from_dict: `[50.46, 51.57, 50.62]` ms (dao động < 1.8%, nhanh hơn 5x so với bản Rust chưa tối ưu)
  - to_dict: `[8.23, 8.50, 8.24]` ms (dao động < 3.2%)
- **commander2000:**
  - p50: `[994.0, 997.0, 1021.0]` µs (dao động < 2.4%)
  - ticks/s: `[817.9, 808.1, 799.2]` (dao động < 1.8%)
  - from_dict: `[219.01, 221.25, 220.97]` ms (dao động < 0.9%, nhanh hơn 4.1x so với bản Rust chưa tối ưu)
  - to_dict: `[19.27, 19.46, 20.21]` ms (dao động < 3.8%)

---

## 5. Đánh giá & Kết luận

1. **Bước nhảy vọt ở Serialization (`from_dict`):**
   - Bản tối ưu hóa đã giải quyết hoàn toàn điểm nghẽn trước đây: thời gian `from_dict` cho 850 nodes giảm từ **262 ms xuống còn 50.6 ms** (~5.2x), và 2000 nodes giảm từ **913 ms xuống còn 221 ms** (~4.1x).
   - Rust hiện tại **nhanh hơn GDScript** cả ở khâu parse/load cây (`1.18x` cho 850 nodes, `1.09x` cho 2000 nodes).
2. **Tick Execution đồng đều gấp 1.6x – 2.0x:**
   - Cây nhỏ (1-4 nodes) đạt bước nhảy lớn: p50 giảm xuống còn 7 µs (1-leaf) và 18 µs (seq3), gấp đúng **2.0x** tốc độ GDScript và đạt throughput tới **139,000 ticks/giây**.
   - Cây lớn (850 - 2000 nodes) ổn định ở mức tăng tốc **1.68x – 1.70x** p50 và **1.61x – 1.66x** throughput, với p99 cải thiện rõ rệt giảm hiện tượng frame spike.
3. **Giới hạn thực nghiệm:**
   - Harness `tests/bench_ab.gd` gọi thông qua facade GDScript (`BTTree`, `BTTask`, `BTRunner`), đại diện cho cấu hình sử dụng thực tế (ship thật) của addon.
