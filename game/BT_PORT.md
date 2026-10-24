# ĐẶC TẢ CHUYỂN ĐỔI BEHAVIOR TREE (BT_PORT.md)
## Chuyển giao cây Devour Ghost_42115 sang Framework Godot Behavior Tree

> **Tài liệu tham chiếu:**  
> - File gốc BD: `/home/hazeruno/IT/workspace/game-reverse/devour/data/bt/Ghost_42115.json` (203 nodes, 20 biến blackboard)  
> - Decompile C# skeleton: `/home/hazeruno/IT/workspace/game-reverse/devour/src/skeleton/`  
> - Recovered C pseudocode: `/home/hazeruno/IT/workspace/game-reverse/devour/src/recovered/`  
> - GDScript flow ports: `/home/hazeruno/IT/workspace/game-reverse/devour/godot/scripts/flow/`

---

## 1. CẤU TRÚC 3 NHÁNH GỐC CỦA CÂY (PARALLEL ROOT)

Cây AI của Ghost trong Devour có gốc là một node **`Parallel`** chạy song song **3 nhánh Repeater lặp vô tận**. Đây là thiết kế then chốt tạo nên trí thông minh đa nhiệm thời gian thực của quái vật:

```diagram
┌────────────────────────────────────────────────────────────────────────┐
│                        ROOT: Parallel (Node 1)                         │
└───────┬───────────────────────────┬───────────────────────────┬────────┘
        │                           │                           │
        ▼ Branch 0                  ▼ Branch 1                  ▼ Branch 2
┌───────────────────────────┐ ┌───────────────────────────┐ ┌───────────────────────────┐
│       Repeater (2)        │ │       Repeater (167)      │ │       Repeater (187)      │
│     CHU TRÌNH CHÍNH       │ │     THIÊU ĐỐI & CHẾT      │ │  PHẢN XẠ & ĐIỀU TỐC ĐỘ  │
│ - Tuần tra (Wander)       │ │ - Lắng nghe rọi đèn UV    │ │ - Bị rọi UV: Hit (666)  │
│ - Cảm tri người chơi      │ │   (fryOnly = True).       │ │   và giảm tốc còn 0.1   │
│ - Tranh cướp Ritual Book  │ │ - Đếm thời gian rọi:      │ │ - Không rọi: Tốc độ     │
│ - Rượt đuổi & Tóm bắt     │ │   Focus >= 0.75s + 1.5s   │ │   Flee (3.0) hoặc       │
│   (Pursue & Attack)       │ │ - Kích hoạt Death (204)   │ │   Pursue (1.0..2.2)     │
└───────────────────────────┘ └───────────────────────────┘ └───────────────────────────┘
```

---

### Chi tiết Nhánh 0 (Nodes 2 – 166): Vòng lặp Hành vi Cốt lõi
Nhánh này quản lý hành vi cấp cao (High-level decision making) của Ghost:
1. **Khởi tạo lại trạng thái (Nodes 4–8):** Gửi event `SetLookAtEntity`, `OnGhostPursue`, đặt `IsFleeing = False`, reset `AbilityIndex = 0` và `AbilityIntData = 0`.
2. **Selector 9 — Lựa chọn hành vi tuần tra vs ứng biến:**
   - **Nhánh con 1 (Node 10):** `PlayerFlashlightOnMe` (fryOnly=True). Nếu Ghost đang bị người chơi rọi UV trực diện thì ưu tiên xử lý.
   - **Nhánh con 2 (Node 11): `ParallelSelector`:** Chạy song song 3 nhánh con với cơ chế "nhánh nào kết thúc trước sẽ quyết định":
     - *Sub-branch 1 (Node 12–20):* Bọc trong decorator `Interrupt` (id: 12) — Đi tuần tra ngẫu nhiên (`GhostGetWanderDestination` -> `GhostMoveTowards` -> `Wait` idle 3-8s).
     - *Sub-branch 2 (Node 21–35):* Bọc trong decorator `Interrupt` (id: 21) — Quét cảm tri liên tục bằng `UntilSuccess`: phát hiện người chơi qua `CanSeePlayer`, `PlayerFlashlightOnMe`, `PlayerTouchingMe`, hoặc `CanHearPlayer` (với điều kiện player không trốn trong tủ/gầm giường: `AbilityIndex != 108`). Khi phát hiện, nhánh này trả về SUCCESS khiến `ParallelSelector` kết thúc thành công!
     - *Sub-branch 3 (Node 36–74):* **Ưu tiên bảo vệ Cuốn sách Nghi thức (Ritual Book):** Dùng `AdvancedWithinDistance` quét nếu sách bị rời khỏi vị trí ban đầu (do người chơi nhấc đi). Nếu sách bị động tới:
       - Gọi `PerformInterruption` (ngắt cả 2 nhánh [12] và [21] ngay lập tức).
       - Chạy tới chỗ cuốn sách (`GhostMoveTowards` book với `speed = 1.5`).
       - Nhặt sách lên tay (`OnRitualBookCarried`, `BoltDetach`, gán `CarryObjectName`).
       - Tha sách đi tuần tra (`GhostGetWanderDestination`), nếu có người chơi tới gần trong 5m thì quay đầu bỏ chạy (`IsFleeing = True`, `GhostGetFleeDestination`, `speed = 3.0`).
3. **Pha Truy đuổi & Tấn công (Nodes 75–166):**
   - Đặt `IsFleeing = False`, nâng `AbilityIndex = 202` (Trạng thái rượt đuổi).
   - Gọi SubTree **`ghost_pursue`** (Nodes 104–143):
     - Ghost lao về phía mục tiêu (`GhostPursue`), vừa chạy vừa lượn sóng (`swayDistance = 0.25`), né tránh đèn pin, cho đến khi áp sát người chơi (`PlayerTouchingMe` khoảng cách <= 0.2m).
     - Khi chạm vào người chơi: Nếu không bị rọi đèn (`AbilityIntData != 666`), kích hoạt đòn cào bắt (`AbilityIndex = 201`), vừa xoay người đối diện (`RotateTowards`) vừa thực hiện animation tấn công.
     - Kiểm tra khoảng cách: Nếu người chơi nhảy thoát xa > 1.5m, Ghost hạ `AbilityIndex` về 202 để tiếp tục dí.
   - **Điều kiện kết thúc Truy đuổi (Nodes 144–163):** Dùng `ParallelComplete` dừng truy đuổi nếu:
     - Người chơi đã bị hạ gục (`IsPlayerBeingKnockedOut`).
     - Người chơi đã kịp chui vào chỗ trốn (`AbilityIndex == 108`).
     - Người chơi bò trườn thoát khỏi tầm (`IsAbilityActive` Crawl).
     - Mất dấu hoàn toàn (không nhìn thấy, không nghe thấy, không thấy ánh đèn) liên tục trong 3.0 giây (`Wait 3s`).
   - Sau khi kết thúc truy đuổi: Xóa mục tiêu `PlayerToChase = null`, reset `AbilityIndex = 0`, quay lại đầu vòng lặp tuần tra.

---

### Chi tiết Nhánh 1 (Nodes 167 – 186): Cơ chế Thiêu đốt UV & Trục xuất / Chết
Nhánh này chạy ngầm độc lập với Nhánh 0, chuyên xử lý áp lực đèn pin UV từ người chơi:
1. `SetSharedBool` reset `StartedFocus = False`.
2. `ParallelComplete` (Node 170):
   - Nhánh trái: Quét `PlayerFlashlightOnMe` (fryOnly=True, viewDistance=6m). Khi phát hiện, đánh dấu `StartedFocus = True` và yêu cầu giữ chùm sáng liên tục tối thiểu 0.75s (`Wait 0.75s`).
   - Nhánh phải: `PlayersFocusingMeWait` (waitTime = 1.5s). Tích lũy thời gian bị rọi UV. Khi chạm mốc 1.5 giây, node này trả về `SUCCESS`!
3. Khi bị rọi đủ 1.5s:
   - Sequence 182 được kích hoạt:
   - `SetIntegerParameter` đặt `AbilityIndex = 204` (Trạng thái Chết / Tan biến / Trục xuất).
   - Bắn sự kiện `ExecuteEvent` "Spawn Egg" (hoặc `OnSpawnRitualBook`: rơi cuốn sách nếu Ghost đang giữ).
   - Reset `AbilityIntData = 0`.
   - Gọi `StopBehaviorTree` tạm dừng toàn bộ hoạt động của Ghost.

---

### Chi tiết Nhánh 2 (Nodes 187 – 203): Phản xạ Trực diện & Điều chỉnh Tốc độ Motor
Nhánh này can thiệp trực tiếp vào tốc độ di chuyển và hoạt ảnh rung giật của Ghost mỗi frame:
1. **Kiểm tra rọi đèn UV (Sequence 189):**
   - Nếu `PlayerFlashlightOnMe` (fryOnly=True, viewDistance=6m) VÀ Ghost chưa chết (`AbilityIndex != 204`):
   - Đặt `AbilityIntData = 666` (Mã số kích hoạt hoạt ảnh gào thét, co giật và hiệu ứng khói bốc cháy trên thân ma).
   - Gọi `SetSpeed` đặt tốc độ di chuyển tụt dốc thê thảm: **`speed = 0.1 m/s`**.
2. **Khi không bị rọi đèn (Sequence 195):**
   - Đặt lại `AbilityIntData = 0` (Bình thường).
   - Điều chỉnh tốc độ dựa trên trạng thái nội tại:
     - Nếu đang tha sách bỏ chạy (`IsFleeing == True`): `SetSpeed(3.0 m/s)` (Tốc độ chạy trốn cực nhanh).
     - Nếu không bỏ chạy (`IsFleeing == False`): `SetSpeed(1.0 m/s)` (Tốc độ tuần tra / dí cơ bản, tự động tăng dần lên 1.5 -> 2.2 m/s theo số vật phẩm đã cúng tế).

---

## 2. BẢNG MAPPING TOÀN DIỆN: BEHAVIOR DESIGNER → GODOT BT ADDON

Toàn bộ 48 loại node xuất hiện trong `Ghost_42115.json` được phân loại:
- **NATIVE:** Có sẵn trong core addon (`addons/godot_bt/core/`). Dùng trực tiếp trong JSON.
- **CUSTOM:** Viết dưới dạng custom task trong `game/scripts/bt_tasks/` kế thừa `BTTask` hoặc `BTParentTask`.

| STT | BD Node Type (Gốc) | Loại Node | Addon Equivalent | Cấu hình / Tham số trong JSON Addon | Ghi chú & Cạm bẫy thực thi |
|---|---|---|---|---|---|
| 1 | `Parallel` | Composite | **`Parallel`** (NATIVE) | `{"type_name": "Parallel", "category": "Composite"}` | Chạy đồng thời các con. Đạt SUCCESS khi tất cả con SUCCESS. |
| 2 | `ParallelComplete` | Composite | **`BTParallelComplete`** (CUSTOM) | `{"type_name": "ParallelComplete", "category": "Composite"}` | Chạy song song, **trả về trạng thái của con ĐẦU TIÊN hoàn thành** (SUCCESS hoặc FAILURE). Dừng các con còn lại. |
| 3 | `ParallelSelector` | Composite | **`BTParallelSelector`** (CUSTOM) | `{"type_name": "ParallelSelector", "category": "Composite"}` | Chạy song song. Nếu có **bất kỳ con nào SUCCESS -> SUCCESS ngay**. Hết con mà không ai SUCCESS -> FAILURE. |
| 4 | `Sequence` | Composite | **`Sequence`** (NATIVE) | `{"type_name": "Sequence", "parameters": {"abort_type": 0}}` | Chạy tuần tự, dừng khi gặp FAILURE. |
| 5 | `Selector` | Composite | **`Selector`** (NATIVE) | `{"type_name": "Selector", "parameters": {"abort_type": 0}}` | Chạy tuần tự, dừng khi gặp SUCCESS. |
| 6 | `Repeater` | Decorator | **`Repeater`** (NATIVE) | `{"type_name": "Repeater", "parameters": {"count": 1, "repeat_forever": true, "end_on_failure": false}}` | Lặp lại con theo count hoặc vô tận. Chú ý map `repeatForever` -> `repeat_forever`. |
| 7 | `Inverter` | Decorator | **`Inverter`** (NATIVE) | `{"type_name": "Inverter", "category": "Decorator"}` | Đảo SUCCESS <-> FAILURE. RUNNING giữ nguyên. |
| 8 | `UntilSuccess` | Decorator | **`UntilSuccess`** (NATIVE) | `{"type_name": "UntilSuccess", "category": "Decorator"}` | Lặp lại con cho đến khi con trả về SUCCESS. |
| 9 | `UntilFailure` | Decorator | **`UntilFailure`** (NATIVE) | `{"type_name": "UntilFailure", "category": "Decorator"}` | Lặp lại con cho đến khi con trả về FAILURE. |
| 10 | `ReturnSuccess` | Decorator | **`ReturnSuccess`** (NATIVE) | `{"type_name": "ReturnSuccess", "category": "Decorator"}` | Ép kết quả kết thúc của con thành SUCCESS. |
| 11 | `ReturnFailure` | Decorator | **`ReturnFailure`** (NATIVE) | `{"type_name": "ReturnFailure", "category": "Decorator"}` | Ép kết quả kết thúc của con thành FAILURE. |
| 12 | `Interrupt` | Decorator | **`BTInterrupt`** (CUSTOM) | `{"type_name": "Interrupt", "category": "Decorator"}` | Bọc con lại. Nhận tín hiệu từ `BTPerformInterruption` để cắt ngang và trả về trạng thái ép buộc. |
| 13 | `PerformInterruption` | Action | **`BTPerformInterruption`** (CUSTOM) | `{"type_name": "PerformInterruption", "parameters": {"interrupt_tasks": [12, 21], "interrupt_success": false}}` | Gọi lệnh ngắt đến danh sách node Interrupt theo id. |
| 14 | `PlayerFlashlightOnMe` | Condition/Action | **`BTPlayerFlashlightOnMe`** (CUSTOM) | `{"type_name": "PlayerFlashlightOnMe", "parameters": {"view_distance": 15.0, "fry_only": false, "target_player_mode": false}}` | Kiểm tra raycast/cone đèn pin người chơi có chiếu trúng Ghost không. Lưu player vào blackboard `$PlayerToChase`. |
| 15 | `CanSeePlayer` | Condition | **`BTCanSeePlayer`** (CUSTOM) | `{"type_name": "CanSeePlayer", "parameters": {"fov_angle": 75.0, "view_distance": 20.0, "target_player": "$PlayerToChase"}}` | Tính góc hướng mặt và khoảng cách, raycast kiểm tra vật cản. Trả về SUCCESS nếu thấy. |
| 16 | `CanHearPlayer` | Condition | **`BTCanHearPlayer`** (CUSTOM) | `{"type_name": "CanHearPlayer", "parameters": {"hearing_radius": 1.5, "audibility_distance": 15.0}}` | Kiểm tra tiếng chân: đi bộ (1.5m), chạy (15m), ngồi (0m). |
| 17 | `CanSeeOtherSurvivalPlayer` | Condition | Map sang **`BTCanSeePlayer`** | Nhập chung với `BTCanSeePlayer` trong single-player (chỉ có 1 player). | Tiết kiệm code; trong single-player nhánh chọn người khác tự động fail. |
| 18 | `CanHearOtherPlayer` | Condition | Map sang **`BTCanHearPlayer`** | Nhập chung với `BTCanHearPlayer` trong single-player. | Không cần tách task riêng. |
| 19 | `OtherPlayerFlashlightOnMe`| Condition | Map sang **`BTPlayerFlashlightOnMe`** | Nhập chung với `BTPlayerFlashlightOnMe`. | Đỡ phân mảnh task. |
| 20 | `PlayerTouchingMe` | Condition | **`BTPlayerTouchingMe`** (CUSTOM) | `{"type_name": "PlayerTouchingMe", "parameters": {"touching_distance": 0.2}}` | Kiểm tra khoảng cách Ghost - Player <= `touching_distance`. |
| 21 | `OtherPlayerTouchingMe` | Condition | Map sang **`BTPlayerTouchingMe`** | Nhập chung trong single-player. | Giữ nguyên logic. |
| 22 | `GhostGetWanderDestination`| Action | **`BTGhostGetWanderDestination`** (CUSTOM) | `{"type_name": "GhostGetWanderDestination", "parameters": {"min_distance": 5.0, "max_distance": 10.0}}` | Lấy điểm ngẫu nhiên trên NavMesh trong phạm vi min/max. Lưu vào `$WanderDestination`. |
| 23 | `GhostGetFleeDestination` | Action | **`BTGhostGetFleeDestination`** (CUSTOM) | `{"type_name": "GhostGetFleeDestination", "parameters": {"look_ahead_distance": 2.5}}` | Tính vector chạy ngược hướng với `$PlayerWithinDistance`. Lưu vào `$FleeDestination`. |
| 24 | `GhostMoveTowards` | Action | **`BTGhostMoveTowards`** (CUSTOM) | `{"type_name": "GhostMoveTowards", "parameters": {"speed": 1.0, "arrive_distance": 0.2, "look_at_target": true, "fleeing": false}}` | Ra lệnh actor di chuyển tới điểm đích qua NavMesh. Trả RUNNING khi đang đi, SUCCESS khi tới nơi. |
| 25 | `GhostPursue` | Action | **`BTGhostPursue`** (CUSTOM) | `{"type_name": "GhostPursue", "parameters": {"arrive_distance": 1.0, "rotation_speed": 720.0, "sway_distance": 0.25}}` | Di chuyển dí theo `$PlayerToChase`, có hiệu ứng lượn sóng zic-zac né đèn pin. |
| 26 | `RotateTowards` | Action | **`BTRotateTowards`** (CUSTOM) | `{"type_name": "RotateTowards", "parameters": {"max_rotation_delta": 5.0, "only_y": true}}` | Xoay từ từ mặt Ghost hướng về người chơi. |
| 27 | `SetSpeed` | Action | **`BTSetSpeed`** (CUSTOM) | `{"type_name": "SetSpeed", "parameters": {"speed": 1.0}}` | Đặt tốc độ motor trên Ghost actor và biến `$Speed`. |
| 28 | `SetIntegerParameter` | Action | **`BTSetIntegerParameter`** (CUSTOM) | `{"type_name": "SetIntegerParameter", "parameters": {"parameter_name": "AbilityIndex", "int_value": 202}}` | Ghi giá trị vào kênh `AbilityIndex` hoặc `AbilityIntData`. |
| 29 | `GetIntegerParameter` | Action | **`BTGetIntegerParameter`** (CUSTOM) | `{"type_name": "GetIntegerParameter", "parameters": {"parameter_name": "AbilityIndex", "store_variable": "AbilityIndex"}}` | Đọc giá trị kênh điều khiển lưu vào blackboard. |
| 30 | `CompareIntegerParameter` | Condition | **`BTCompareIntegerParameter`** (CUSTOM)| `{"type_name": "CompareIntegerParameter", "parameters": {"parameter_name": "AbilityIndex", "compare_to": 108}}` | So sánh giá trị kênh điều khiển (ví dụ kiểm tra player có đang trốn không). |
| 31 | `SetSharedBool` | Action | **`BTSetSharedBool`** (CUSTOM) | `{"type_name": "SetSharedBool", "parameters": {"variable_name": "IsFleeing", "value": true}}` | Ghi giá trị bool vào biến blackboard. |
| 32 | `CompareSharedBool` | Condition | **`BTCompareSharedBool`** (CUSTOM) | `{"type_name": "CompareSharedBool", "parameters": {"variable_name": "IsFleeing", "compare_to": true}}` | Kiểm tra giá trị bool trên blackboard. |
| 33 | `CompareSharedInt` | Condition | **`BTCompareSharedInt`** (CUSTOM) | `{"type_name": "CompareSharedInt", "parameters": {"variable_name": "AbilityIndex", "compare_to": 202}}` | So sánh số nguyên trên blackboard. |
| 34 | `SetSharedGameObject` | Action | **`BTSetSharedGameObject`** (CUSTOM) | `{"type_name": "SetSharedGameObject", "parameters": {"target_variable": "PlayerToChase", "source_variable": "OtherPlayerToChase"}}` | Gán hoặc reset object tham chiếu trên blackboard. |
| 35 | `AdvancedWithinDistance` | Condition/Action | **`BTAdvancedWithinDistance`** (CUSTOM)| `{"type_name": "AdvancedWithinDistance", "parameters": {"magnitude": 5.0, "target_tag": "RitualBook", "line_of_sight": true}}` | Kiểm tra vật thể mang tag (RitualBook hoặc Player) trong tầm `magnitude`. |
| 36 | `DistanceToGameObject` | Action | **`BTDistanceToGameObject`** (CUSTOM) | `{"type_name": "DistanceToGameObject", "parameters": {"target": "$PlayerToChase", "store_variable": "DistanceToPursuedPlayer"}}` | Tính khoảng cách thực tế giữa Ghost và Target, lưu blackboard. |
| 37 | `FloatComparison` | Condition | **`BTFloatComparison`** (CUSTOM) | `{"type_name": "FloatComparison", "parameters": {"operation": "LessThanOrEqualTo", "val1": "@DistanceToPursuedPlayer", "val2": 1.5}}` | So sánh 2 số float (hỗ trợ `@key` tham số động từ blackboard). |
| 38 | `Wait` | Action | **`BTWait`** (CUSTOM) | `{"type_name": "Wait", "parameters": {"wait_time": 0.8, "random_wait": false}}` | Chờ đợi thời gian xác định hoặc ngẫu nhiên. Trả RUNNING trong khi chờ, SUCCESS khi hết giờ. |
| 39 | `PlayersFocusingMeWait` | Action | **`BTPlayersFocusingMeWait`** (CUSTOM)| `{"type_name": "PlayersFocusingMeWait", "parameters": {"wait_time": 1.5}}` | Đếm tích lũy thời gian Ghost bị người chơi rọi đèn UV tập trung. Đạt 1.5s trả SUCCESS. |
| 40 | `ExecuteLocalEventGameObject`| Action | **`BTExecuteEvent`** (CUSTOM) | `{"type_name": "ExecuteEvent", "parameters": {"event_name": "SetLookAtEntity"}}` | Bắn signal nội bộ lên Ghost actor để cập nhật hoạt cảnh/hướng nhìn. |
| 41 | `ExecuteEvent` | Action | **`BTExecuteEvent`** (CUSTOM) | `{"type_name": "ExecuteEvent", "parameters": {"event_name": "OnSpawnRitualBook"}}` | Bắn signal gameplay (ví dụ rơi sách cúng tế). |
| 42 | `IsPlayerBeingKnockedOut` | Condition | **`BTIsPlayerBeingKnockedOut`** (CUSTOM)| `{"type_name": "IsPlayerBeingKnockedOut", "parameters": {"player": "$PlayerToChase"}}` | Kiểm tra player đã bị gục chưa. |
| 43 | `IsAbilityActive` | Condition | **`BTIsAbilityActive`** (CUSTOM) | `{"type_name": "IsAbilityActive", "parameters": {"ability_type": "Crawl"}}` | Kiểm tra trạng thái đặc biệt của player. |
| 44 | `StopBehaviorTree` | Action | **`BTStopBehaviorTree`** (CUSTOM) | `{"type_name": "StopBehaviorTree", "parameters": {}}` | Dừng runner AI khi Ghost bị tiêu diệt. |
| 45 | `CanCarryInteractable` | Action | **`BTRitualBookAction`** (CUSTOM) | `{"type_name": "RitualBookAction", "parameters": {"action_type": "can_carry"}}` | Kiểm tra quyền nhặt sách cúng tế. |
| 46 | `BoltDetach` | Action | **`BTRitualBookAction`** (CUSTOM) | `{"type_name": "RitualBookAction", "parameters": {"action_type": "detach"}}` | Tháo rời sách cúng tế khỏi bệ bàn thờ. |
| 47 | `GetStringStateValue` | Action | **`BTRitualBookAction`** (CUSTOM) | `{"type_name": "RitualBookAction", "parameters": {"action_type": "get_metadata"}}` | Lấy chuỗi metadata định danh sách. |
| 48 | `SetStringStateValue` | Action | **`BTRitualBookAction`** (CUSTOM) | `{"type_name": "RitualBookAction", "parameters": {"action_type": "set_carry_name"}}` | Gán tên vật phẩm đang mang trên Ghost. |

---

## 3. THIẾT KẾ CÁC SUBTREE JSON TÁI SỬ DỤNG (REUSABLE SUBTREES)

Nhằm tối ưu hóa khả năng bảo trì, giảm bớt độ cồng kềnh của file JSON chính và tận dụng tính năng `BTSubTree` của addon, hai khối logic lớn được tách thành file subtree riêng biệt:

### 3.1. Subtree 1: `res://game/bt/subtrees/ghost_pursue.json`
- **Mục đích:** Đóng gói toàn bộ quy trình tiếp cận, né tránh đèn pin, lượn sóng và tấn công mục tiêu `$PlayerToChase`.
- **Đầu vào (Blackboard Scoping):**
  - `$PlayerToChase`: Object (Shared = true).
  - `$Speed`: Float (Shared = true).
  - `$DistanceToPursuedPlayer`: Float (Private = true).
- **Cấu trúc:** Gồm `ParallelSelector` [110] chạy song song `GhostPursue` [111] và `PlayerTouchingMe` [113], tiếp nối bởi Sequence tấn công [114] (`SetIntegerParameter AbilityIndex=201`, `RotateTowards`, vòng lặp kiểm tra cự ly 1.5m).

### 3.2. Subtree 2: `res://game/bt/subtrees/ghost_wander.json`
- **Mục đích:** Đóng gói hành vi tuần tra định kỳ tìm điểm ngẫu nhiên và di chuyển.
- **Đầu vào:**
  - `$WanderDestination`: Vector3 (Private = true).
  - `$Speed`: Float (Shared = true).
- **Cấu trúc:** Sequence gồm `GhostGetWanderDestination` -> `GhostMoveTowards` -> `Wait` ngẫu nhiên 3..8s.

---

## 4. CƠ CHẾ CONDITIONAL ABORT & NGẮT INTERRUPT

Trong Behavior Designer gốc của Devour, tác giả sử dụng cặp đôi:
- **`Interrupt` (Decorator):** Bọc một cây con, lưu trạng thái ngắt.
- **`PerformInterruption` (Action):** Nhận mảng các id của node Interrupt, khi chạy sẽ gọi thẳng lệnh ngắt con bên trong.

### Phương án triển khai trong Godot BT Addon:
Hệ thống Behavior Tree của repo hỗ trợ native 2 cơ chế rất mạnh:
1. **Custom `BTInterrupt` & `BTPerformInterruption`:** Giữ nguyên 100% ngữ nghĩa của Devour (Node 43 gọi ngắt Node 12 và Node 21) để cây JSON port sang khớp từng ID.
2. **Conditional Abort `LOWER_PRIORITY` & `SELF`:**
   - Tại Selector 9: Đặt `abort_type = 2 (LOWER_PRIORITY)`. Khi đang tuần tra (nhánh thấp hơn) mà phát hiện `PlayerFlashlightOnMe` hoặc `AdvancedWithinDistance` (nhánh ưu tiên cao hơn) đổi sang TRUE, Selector sẽ lập tức hủy nhánh tuần tra mà không cần chờ.
   - Tại Sequence truy đuổi: Đặt `abort_type = 1 (SELF)`. Nếu điều kiện mục tiêu còn sống / còn nhìn thấy bị vi phạm giữa chừng, toàn bộ Sequence bị hủy tức thì.

---

## 5. BẢNG BIẾN BLACKBOARD CỦA GHOST (20 BIẾN TỪ GHOST_42115)

Dưới đây là đặc tả 20 biến blackboard của cây gốc, tương ứng với schema JSON của addon:

```json
"blackboard": {
  "WanderDestination": {
    "type_name": "vector3",
    "value": "(0, 0, 0)",
    "is_shared": false,
    "description": "Tọa độ điểm đến tuần tra ngẫu nhiên"
  },
  "WanderColliders": {
    "type_name": "array",
    "value": [],
    "is_shared": false,
    "description": "Danh sách vùng tuần tra hợp lệ"
  },
  "Players": {
    "type_name": "array",
    "value": [],
    "is_shared": true,
    "description": "Danh sách tất cả người chơi trong phòng"
  },
  "PlayerToChase": {
    "type_name": "object",
    "value": null,
    "is_shared": true,
    "description": "Người chơi mục tiêu đang bị rượt đuổi"
  },
  "OtherPlayerToChase": {
    "type_name": "object",
    "value": null,
    "is_shared": false,
    "description": "Người chơi phụ phát hiện được để đổi mục tiêu"
  },
  "PlayerWithinDistance": {
    "type_name": "object",
    "value": null,
    "is_shared": false,
    "description": "Người chơi ở quá gần cuốn sách cúng tế"
  },
  "PlayerHeard": {
    "type_name": "object",
    "value": null,
    "is_shared": false,
    "description": "Người chơi bị phát hiện tiếng bước chân"
  },
  "PlayerFryingMe": {
    "type_name": "object",
    "value": null,
    "is_shared": true,
    "description": "Người chơi đang rọi đèn pin UV thiêu đốt Ghost"
  },
  "SeekPosition": {
    "type_name": "vector3",
    "value": "(0, 0, 0)",
    "is_shared": false,
    "description": "Tọa độ dò tìm đường đi"
  },
  "FleeDestination": {
    "type_name": "vector3",
    "value": "(0, 0, 0)",
    "is_shared": false,
    "description": "Tọa độ chạy trốn khi bị người chơi áp sát mang sách"
  },
  "TargetOffset": {
    "type_name": "vector3",
    "value": "(0, 0.8, 0)",
    "is_shared": false,
    "description": "Độ lệch tâm ngực người chơi"
  },
  "StartedFocus": {
    "type_name": "bool",
    "value": false,
    "is_shared": true,
    "description": "True nếu đèn pin UV đã rọi trúng bắt đầu đếm thời gian"
  },
  "NumPlayersFocusingMe": {
    "type_name": "int",
    "value": 0,
    "is_shared": true,
    "description": "Số lượng người chơi đang rọi UV vào Ghost"
  },
  "IsFleeing": {
    "type_name": "bool",
    "value": false,
    "is_shared": true,
    "description": "True khi Ghost đang tha sách bỏ chạy"
  },
  "NearRitualBook": {
    "type_name": "bool",
    "value": false,
    "is_shared": true,
    "description": "True khi phát hiện sách cúng tế bị di dời"
  },
  "DistanceToPursuedPlayer": {
    "type_name": "float",
    "value": 0.0,
    "is_shared": false,
    "description": "Khoảng cách đo đạc thực tế tới mục tiêu"
  },
  "AbilityIndex": {
    "type_name": "int",
    "value": 0,
    "is_shared": true,
    "description": "Kênh trạng thái chính: 0=Idle/Patrol, 201=Attack, 202=Pursue, 203=Flee, 204=Death/Banished, 206=PickBook"
  },
  "AbilityIntData": {
    "type_name": "int",
    "value": 0,
    "is_shared": true,
    "description": "Kênh hiệu ứng phụ: 666=Hit by UV Flashlight (Frying / Stagger)"
  },
  "Speed": {
    "type_name": "float",
    "value": 1.0,
    "is_shared": true,
    "description": "Tốc độ di chuyển hiện thời của Ghost"
  },
  "RitualBook": {
    "type_name": "object",
    "value": null,
    "is_shared": true,
    "description": "Node tham chiếu đến Cuốn sách Cúng tế"
  },
  "RitualBookMetadata": {
    "type_name": "string",
    "value": "",
    "is_shared": false,
    "description": "Chuỗi nhận diện cuốn sách"
  }
}
```

---

## 6. CÁC ĐIỂM CẦN KIỂM CHỨNG LẠI (`TODO(verify)`)

Dành cho Agent BT kiểm tra chéo với mã nguồn C# decompile:
1. `TODO(verify)`: Giá trị `layerMask` trong `PlayerFlashlightOnMe` (gốc là số nguyên bitmask Unity: `69220865` và `-2078275071`). Trong Godot 4, cần map thành collision layer thích hợp (ví dụ Layer 1: World, Layer 2: Player, Layer 3: Ghost).
2. `TODO(verify)`: Cơ chế `FloatListdodgeSpeeds` trong `GhostPursue` (gốc là mảng `[1.25, 1.4, 1.55, 1.7, 1.85, 2, 2.15, 2.3, 2.5, 2.5]`). Trong game Devour, mảng này được lập chỉ mục dựa theo số lượng vật phẩm tế lễ đã đốt (`NumBurntObjects`). Cần kiểm tra xem có cần nối `Altar.get_burnt_count()` vào đây không.
3. `TODO(verify)`: Hành vi `StopBehaviorTree` ở Node 186: Trong engine của Devour, task này ngắt toàn bộ cây. Trong addon của repo, việc này tương ứng với việc gọi `runner.stop()` hoặc `runner.pause(true)`.
4. `TODO(verify)`: Task `BoltDetach` (Node 50): Trong Devour gốc, Ritual Book bị khóa vào bệ thờ bằng then sắt (bolt). Khi Ghost tới cướp sách, nó tháo chốt để lấy sách. Trong game clone đơn giản hóa, có thể coi đây là thao tác detach parent sang tay Ghost.
