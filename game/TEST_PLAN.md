# KẾ HOẠCH KIỂM THỬ HEADLESS E2E & CÁC BẤT BIẾN (TEST_PLAN.md)
## Quy chuẩn Kiểm thử Tự động cho Devour Ghost Behavior Tree & Farmhouse Ritual

> **Mục tiêu:** Chạy kiểm thử tự động không cần cửa sổ đồ họa (`godot --headless -s game/tests/test_game_e2e.gd`).  
> **Phạm vi:** Kiểm tra trọn vẹn các logic phản xạ, chuyển đổi trạng thái, ưu tiên nhiệm vụ của Ghost AI và cơ chế gameplay của Map Farmhouse (thu thập & đốt chuột, cửa khóa, cầu chì bật điện, thắng/thua).

---

## 1. NGUYÊN TẮC THIẾT KẾ TEST SUITE HEADLESS

1. **Không phụ thuộc Render / Window:** Mọi test case phải khởi tạo cây Behavior Tree thông qua `BTRunner.new(tree)`, gắn với một `MockGhostActor` và `MockGameManager` mô phỏng hoàn toàn trong bộ nhớ RAM.
2. **Deterministic Time-Stepping:** Tuyệt đối không dùng `await get_tree().create_timer()`. Toàn bộ thời gian được thúc đẩy thủ công thông qua `runner.tick(0.1)` (mỗi tick tương ứng 100ms trong thế giới game).
3. **Mock Actor & Systems Pattern:** Tạo các class Mock kế thừa `Node3D`/`RefCounted` triển khai đầy đủ các hàm quy định trong `TASKS.md` và `DESIGN.md`:
   - `MockGhostActor`: cho phép test script can thiệp vào các cờ giả lập:
     + `mock.is_flashlight_on = true/false`
     + `mock.player_distance = 10.0`
     + `mock.player_in_fov = true/false`
     + `mock.has_ritual_threat = true/false`
   - `MockFarmhouseGame`: mô phỏng NavMesh bounds, danh sách chuột, thùng rác, cửa khóa, hộp cầu chì và lò thiêu Altar.
4. **Đo đạc 3 chiều (Multi-metric Verification):**
   - **Blackboard Inspection:** Kiểm tra `runner.tree.blackboard.get_var(key)`.
   - **Tick Count Assertion:** Đếm số tick tối đa để chuyển trạng thái (ví dụ: phản xạ ngắt <= 2 ticks).
   - **Signal Monitoring:** Đếm số lần signal `task_started`, `task_finished`, `task_aborted` được phát ra từ `BTRunner`.

---

## 2. BẢNG BẤT BIẾN KIỂM THỬ (TEST INVARIANTS)

### Phần A: Các Bất biến Ghost AI (Duy trì từ cây `Ghost_42115` gốc)

| Mã Bất Biến | Tên Bất Biến | Điều kiện Kích hoạt | Kỳ vọng Logic | Giới hạn Đo lường |
|---|---|---|---|---|
| **INV-01** | `Wander Step` | Không có người chơi, không có đèn pin, không động vào chuột/altar. | Ghost tuần tra bình thường, `$WanderDestination` được tạo mới và `$AbilityIndex == 0`. | Sau 1 tick. |
| **INV-02** | `Sight Detection` | Player bước vào góc nhìn 75° ở cự ly 15m (`can_see = true`). | Ghost phát hiện player, gán `$PlayerToChase = player`, chuyển sang trạng thái rượt đuổi `$AbilityIndex == 202`. | <= 2 ticks (0.2s). |
| **INV-03** | `Noise Detection` | Player chạy nhanh Sprint trong bán kính 10m (`can_hear = true`). | Ghost nghe thấy tiếng bước chân, gán `$PlayerToChase` và chuyển `$AbilityIndex == 202`. | <= 2 ticks (0.2s). |
| **INV-04** | `UV Frying Slowdown` | Player rọi đèn pin UV tập trung vào Ghost (`fry_only = true`). | Ngay lập tức Nhánh 2 chuyển `$AbilityIntData == 666` (Hit) và tốc độ `$Speed == 0.1`. | Chính xác 1 tick (0.1s). |
| **INV-05** | `UV Fry Release` | Player tắt đèn pin hoặc quay chùm sáng đi nơi khác. | Nhánh 2 lập tức hồi phục `$AbilityIntData == 0` (Not Hit) và tốc độ hồi phục về bình thường. | Chính xác 1 tick (0.1s). |
| **INV-06** | `Focus Banish / Death` | Player rọi đèn pin UV liên tục vào Ghost trong 1.5s (15 ticks). | Nhánh 1 tích lũy đủ `PlayersFocusingMeWait`, chuyển `$AbilityIndex == 204` (Death), phát event `OnSpawnRitualBook`, và `runner.is_running() == false`. | Đúng sau 15–16 ticks (1.5–1.6s). |
| **INV-07** | `Ritual Preemption` | Ghost đang rượt đuổi Player, Player bế chuột hoặc tiếp cận Altar (`has_ritual_threat = true`). | Ghost lập tức ngắt săn đuổi (`PerformInterruption` [12, 21]), ưu tiên chạy tới bảo vệ Altar/chuột. | <= 2 ticks (0.2s). |
| **INV-08** | `Pursuit Timeout` | Player cắt đuôi thành công (ra khỏi tầm nhìn, đi khẽ, tắt đèn pin). | Sau khi mất dấu liên tục 3.0s (30 ticks), Ghost hủy `$PlayerToChase = null`, reset `$AbilityIndex = 0` và quay về Wander. | Đúng sau 30 ticks (3.0s). |
| **INV-09** | `Ghost Never Stuck in 202` | Mất dấu người chơi quá 3.5s. | Ghost KHÔNG BAO GIỜ duy trì `$AbilityIndex == 202` khi không còn mục tiêu hợp lệ. | Bất biến xuyên suốt. |
| **INV-10** | `Grab Attack Execution` | Ghost áp sát Player ở cự ly <= 0.2m (`PlayerTouchingMe`). | Ghost kích hoạt đòn tấn công cào bắt `$AbilityIndex == 201`. | <= 1 tick khi chạm. |
| **INV-11** | `Game Over on 3 Grabs` | Ghost chạm và tấn công Player đủ 3 lần. | `GameManager.is_game_over == true` và kết quả là THUA (Loss). | Đúng 3 lần grab. |
| **INV-12** | `SubTree Variable Isolation` | Chạy subtree `ghost_pursue.json`. | Biến nội bộ private `$DistanceToPursuedPlayer` không làm ghi đè hay rò rỉ sang parent tree blackboard. | 100 ticks. |

---

### Phần B: Các Bất biến Bản đồ Farmhouse & Cơ chế Đốt Chuột (Mới)

| Mã Bất Biến | Tên Bất Biến | Điều kiện Kích hoạt | Kỳ vọng Logic | Giới hạn Đo lường |
|---|---|---|---|---|
| **INV-13** | `Rat Spawn Bounds & NavMesh` | Khởi tạo ván chơi tại scene Farmhouse. | Toàn bộ 11 con chuột ban đầu (`initial_rats == 11`) phải nằm trong giới hạn không gian chơi (AABB) và nằm trên NavMesh, không bị kẹt trong tường (`NavigationServer3D.map_get_closest_point(pos) == pos`). | Ngay lúc Init (Tick 0). |
| **INV-14** | `Rat Pickup Inventory` | Người chơi đứng gần chuột (`distance <= 1.5m`) và nhấn E (`interact()`). | Con chuột bị nhặt khỏi scene (`rat.visible = false` / `reparent`), số chuột trên tay người chơi tăng lên 1 (`player.held_rat != null`), không được nhặt thêm con thứ 2 (`max_capacity == 1`). | Chính xác 1 tick tương tác. |
| **INV-15** | `Altar Rat Burn & Count` | Người chơi đang cầm chuột, đứng gần Altar lò thiêu (`distance <= 2.0m`) và nhấn E (`burn_rat()`). | Con chuột bị phá hủy hoàn toàn (`queue_free()`), `player.held_rat = null`, và số chuột đã đốt tăng lên 1 (`game_manager.burnt_count += 1`). | Chính xác 1 tick. |
| **INV-16** | `Win State on 9 Rats` | Số chuột thiêu đốt đạt mốc 9 con (`burnt_count == 9`). | `GameManager.is_game_won == true`, Ghost Molly gào thét tan biến hoàn toàn, `ghost_runner.stop()` được gọi, cờ chiến thắng WIN được kích hoạt. | <= 1 tick sau khi đốt con thứ 9. |
| **INV-17** | `Locked Door & Key` | Cửa phòng ngủ / tầng hầm đang khóa (`door.is_locked == true`). | Khi không có chìa khóa: nhấn E không mở được cửa (`door.is_open == false`). Khi nhặt được đúng `Key` trong túi đồ: nhấn E thì `door.is_locked = false` và `door.is_open = true`. | Kiểm tra 2 giai đoạn (trước và sau khi nhặt Key). |
| **INV-18** | `Fuse & Electrical Power` | Hộp cầu chì ở bếp ban đầu trống (`fusebox.has_fuse == false`). | Toàn bộ đèn hành lang tắt (`hallway_lights.visible == false`). Sau khi nhặt `Fuse` và lắp vào: `fusebox.has_fuse = true`, đèn hành lang lập tức bật sáng (`hallway_lights.visible == true`). | Chính xác 1 tick sau khi lắp. |
| **INV-19** | `Enrage Speed Scaling` | `burnt_count` tăng từ 0 đến 8 con. | Tốc độ rượt đuổi cơ sở của Ghost tăng dần theo từng mốc chuột bị đốt (từ 1.25 m/s lên 2.5 m/s), không bị giữ nguyên tốc độ ban đầu. | Đo sau mỗi mốc đốt. |

---

## 3. THIẾT KẾ MOCK ACTOR & FARMHOUSE SIMULATOR

```gdscript
# Mô hình giả lập kiểm thử trong test_game_e2e.gd
class_name MockFarmhouseGame
extends Node3D

var burnt_count: int = 0
var max_burn_target: int = 9
var is_game_won: bool = false
var is_game_over: bool = false
var player_downed_count: int = 0

var initial_rats: Array = []
var held_rat = null

func spawn_initial_rats(count: int = 11) -> void:
    initial_rats.clear()
    for i in range(count):
        var mock_rat = {
            "id": i,
            "position": Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)),
            "is_alive": true,
            "is_inside_bounds": true
        }
        initial_rats.append(mock_rat)

func player_pickup_rat(rat_index: int) -> bool:
    if held_rat != null:
        return false # Chỉ ôm được 1 con
    if rat_index < initial_rats.size() and initial_rats[rat_index].is_alive:
        held_rat = initial_rats[rat_index]
        initial_rats[rat_index].is_alive = false
        return true
    return false

func burn_held_rat_at_altar() -> bool:
    if held_rat == null:
        return false
    held_rat = null
    burnt_count += 1
    if burnt_count >= max_burn_target:
        is_game_won = true
    return true
```

---

## 4. QUY TRÌNH THỰC THI & LỆNH CHẠY TEST

Để QA Agent và CI kiểm thử tự động toàn bộ test suite:

```bash
# Chạy toàn bộ test suite headless
godot --headless -s game/tests/test_game_e2e.gd

# Hoặc nếu chạy thông qua runner test của project:
# Kết quả trả về Exit Code 0 nếu toàn bộ 19 bất biến đều XANH (PASS).
```

### Tiêu chuẩn Nghiệm thu Test (Pass Criteria)
- 100% 19 test invariants đều PASS.
- Không có rò rỉ bộ nhớ (Orphan nodes == 0).
- Không có lỗi Crash hoặc Null Reference trong quá trình tick runner.
