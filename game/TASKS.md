# DANH MỤC CUSTOM BEHAVIOR TREE TASKS (TASKS.md)
## Hợp đồng Giao tiếp Kỹ thuật giữa BT Behaviors Agent và Gameplay Code Agent

> Mọi file script được lưu trong: `game/scripts/bt_tasks/`  
> Mọi task kế thừa từ `BTTask` (Action/Condition) hoặc `BTParentTask` (Composite/Decorator).  
> Các task phải hỗ trợ tham số động: dùng `get_param("name", default_val)` để tự động resolve binding `@key` hoặc `$key` từ Blackboard.

---

## 1. NHÓM ĐIỀU KHIỂN LUỒNG & TỔ HỢP TÙY BIẾN (COMPOSITES & DECORATORS)

### 1.1. `BTParallelComplete`
- **File:** `game/scripts/bt_tasks/bt_parallel_complete.gd`
- **Class:** `class_name BTParallelComplete extends BTParentTask`
- **Category:** `Composite`
- **Mục đích:** Port từ `BehaviorDesigner.Runtime.Tasks.ParallelComplete`. Chạy song song các task con. Trả về trạng thái của **con đầu tiên kết thúc** (SUCCESS hoặc FAILURE). Ngay khi có 1 con kết thúc, các con còn lại đang RUNNING sẽ bị hủy (`abort`).
- **Tham số:** Không có tham số bắt buộc.
- **Blackboard:** Không đọc/ghi trực tiếp.
- **Hành vi từng tick (`on_update`):**
  - Khởi động: Cho chạy tất cả các con song song.
  - Mỗi tick: Quét kết quả trả về của từng con.
  - Nếu có bất kỳ con nào trả về `SUCCESS` -> Hủy các con khác, trả về `SUCCESS`.
  - Nếu có bất kỳ con nào trả về `FAILURE` -> Hủy các con khác, trả về `FAILURE`.
  - Nếu tất cả các con vẫn đang `RUNNING` -> Trả về `RUNNING`.
- **Hợp đồng Actor:** Không gọi hàm trên actor.

---

### 1.2. `BTParallelSelector`
- **File:** `game/scripts/bt_tasks/bt_parallel_selector.gd`
- **Class:** `class_name BTParallelSelector extends BTParentTask`
- **Category:** `Composite`
- **Mục đích:** Port từ `BehaviorDesigner.Runtime.Tasks.ParallelSelector`. Chạy song song các con. "Thắng nếu có nhánh thành công": nếu có **bất kỳ con nào SUCCESS**, composite lập tức kết thúc với `SUCCESS`. Nếu tất cả các con đều `FAILURE` -> trả về `FAILURE`.
- **Tham số:** Không có.
- **Blackboard:** Không đọc/ghi.
- **Hành vi từng tick (`on_update`):**
  - Chạy đồng thời các con.
  - Nếu bất kỳ con nào trả về `SUCCESS` -> Hủy các con còn lại, trả về `SUCCESS`.
  - Nếu tất cả các con đều đã kết thúc với `FAILURE` -> Trả về `FAILURE`.
  - Còn ít nhất 1 con đang chạy và chưa ai thành công -> Trả về `RUNNING`.
- **Hợp đồng Actor:** Không gọi hàm trên actor.

---

### 1.3. `BTInterrupt`
- **File:** `game/scripts/bt_tasks/bt_interrupt.gd`
- **Class:** `class_name BTInterrupt extends BTParentTask`
- **Category:** `Decorator`
- **Mục đích:** Port từ `BehaviorDesigner.Runtime.Tasks.Interrupt`. Bọc một cây con. Cung cấp API `do_interrupt(status)` để `BTPerformInterruption` có thể cắt ngang cây con này bất cứ lúc nào.
- **Biến nội bộ:**
  - `interrupt_status: int = BTStatus.FAILURE`
  - `is_interrupted: bool = false`
- **Phương thức công khai:**
  - `func do_interrupt(p_status: int) -> void:` Đánh dấu `is_interrupted = true`, ghi `interrupt_status = p_status`, và hủy con đang chạy nếu có.
- **Hành vi từng tick (`on_update`):**
  - Nếu `is_interrupted == true`: Reset cờ và trả về `interrupt_status`.
  - Nếu chưa bị ngắt: Ủy quyền tick cho con bên trong và trả về trạng thái của con.
- **Hợp đồng Actor:** Không gọi hàm trên actor.

---

### 1.4. `BTPerformInterruption`
- **File:** `game/scripts/bt_tasks/bt_perform_interruption.gd`
- **Class:** `class_name BTPerformInterruption extends BTTask`
- **Category:** `Action`
- **Mục đích:** Tìm kiếm các node `BTInterrupt` trong cây dựa theo mảng ID và gọi lệnh ngắt.
- **Tham số:**
  - `interrupt_tasks: Array` (Kiểu Array int, mặc định `[]`): Mảng chứa các ID node cần ngắt (ví dụ trong Ghost gốc là `[12, 21]`).
  - `interrupt_success: bool` (Mặc định `false`): Nếu true thì ngắt trả SUCCESS, false thì ngắt trả FAILURE.
- **Blackboard:** Không đọc/ghi.
- **Hành vi từng tick (`on_update`):**
  - Duyệt qua danh sách ID trong `interrupt_tasks`.
  - Tìm node tương ứng trong cây thông qua `tree.get_node_by_id(id)`.
  - Nếu node có hàm `do_interrupt`, gọi `node.do_interrupt(BTStatus.SUCCESS if interrupt_success else BTStatus.FAILURE)`.
  - Luôn luôn trả về `SUCCESS` ngay trong 1 tick.
- **Hợp đồng Actor:** Không gọi hàm trên actor.

---

## 2. NHÓM CẢM TRI & PHÁT HIỆN (PERCEPTION & DETECTION)

### 2.1. `BTPlayerFlashlightOnMe`
- **File:** `game/scripts/bt_tasks/bt_player_flashlight_on_me.gd`
- **Class:** `class_name BTPlayerFlashlightOnMe extends BTTask`
- **Category:** `Condition` / `Action`
- **Tham số:**
  - `view_distance: float` (Mặc định `15.0`): Tầm chiếu xa của đèn pin.
  - `fry_only: bool` (Mặc định `false`): Nếu `true`, chỉ phát hiện khi người chơi đang bật chế độ UV tập trung (Fry mode).
  - `target_player_mode: bool` (Mặc định `false`): Nếu true, chỉ kiểm tra player đang gán trong tham số `target_player`.
  - `target_player: String` (Mặc định `"$PlayerToChase"`): Blackboard key tham chiếu player cần check.
  - `returned_player: String` (Mặc định `"$PlayerToChase"`): Blackboard key để ghi nhận player phát hiện được.
- **Blackboard:**
  - Đọc: `$PlayerToChase` (khi `target_player_mode = true`).
  - Ghi: `$PlayerToChase` hoặc `$PlayerFryingMe` (lưu node player phát hiện được).
  - Ghi: `$StartedFocus` (đặt thành `true` khi phát hiện bị chiếu).
- **Hành vi từng tick (`on_update` hoặc `evaluate_condition`):**
  - Gọi `actor.is_flashlight_shining_on_me(fry_only, view_distance)`.
  - Nếu có đèn chiếu trúng:
    - Ghi nhận player vào blackboard theo `returned_player`.
    - Trả về `SUCCESS`.
  - Nếu không có: Trả về `FAILURE`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func is_flashlight_shining_on_me(p_fry_only: bool, p_max_dist: float) -> Node3D:` Trả về Node của Player nếu tia sáng đèn pin (Cone / Raycast) đang chiếu trúng Mesh/Collider của Ghost không bị cản tường, ngược lại trả về `null`.

---

### 2.2. `BTCanSeePlayer`
- **File:** `game/scripts/bt_tasks/bt_can_see_player.gd`
- **Class:** `class_name BTCanSeePlayer extends BTTask`
- **Category:** `Condition`
- **Tham số:**
  - `fov_angle: float` (Mặc định `75.0`): Góc nón thị giác (độ).
  - `view_distance: float` (Mặc định `20.0`): Tầm nhìn xa tối đa (mét).
  - `target_player_mode: bool` (Mặc định `false`): Nếu true, chỉ kiểm tra người chơi chỉ định.
  - `target_player: String` (Mặc định `"$PlayerToChase"`).
  - `returned_player: String` (Mặc định `"$PlayerToChase"`).
- **Blackboard:**
  - Đọc: `$PlayerToChase` (khi `target_player_mode = true`).
  - Ghi: `$PlayerToChase` (lưu tham chiếu player nhìn thấy).
- **Hành vi từng tick (`on_update` / `evaluate_condition`):**
  - Gọi `actor.can_see_player(target, fov_angle, view_distance)`.
  - Nếu người chơi nằm trong góc nhìn, trong khoảng cách và raycast trực tiếp không chạm tường -> Trả về `SUCCESS`.
  - Ngược lại -> Trả về `FAILURE`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func can_see_target(p_target: Node3D, p_fov_deg: float, p_max_dist: float) -> bool:`

---

### 2.3. `BTCanHearPlayer`
- **File:** `game/scripts/bt_tasks/bt_can_hear_player.gd`
- **Class:** `class_name BTCanHearPlayer extends BTTask`
- **Category:** `Condition`
- **Tham số:**
  - `hearing_radius: float` (Mặc định `1.5`): Bán kính nghe tiếng bước chân đi bộ bình thường (mét).
  - `audibility_distance: float` (Mặc định `15.0`): Bán kính nghe tiếng chạy nhanh Sprint (mét).
  - `returned_player: String` (Mặc định `"$PlayerToChase"`).
- **Blackboard:**
  - Ghi: `$PlayerToChase` hoặc `$PlayerHeard`.
- **Hành vi từng tick (`on_update` / `evaluate_condition`):**
  - Gọi `actor.check_hearing(hearing_radius, audibility_distance)`.
  - Nếu player đang chạy (`sprint`) trong tầm 15m, hoặc đang đi bộ trong tầm 1.5m -> Trả về `SUCCESS`.
  - Nếu player đang ngồi (`crouch`) -> Khoảng cách nghe = 0, luôn trả về `FAILURE`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func detect_player_noise(p_walk_radius: float, p_sprint_radius: float) -> Node3D:`

---

### 2.4. `BTPlayerTouchingMe`
- **File:** `game/scripts/bt_tasks/bt_player_touching_me.gd`
- **Class:** `class_name BTPlayerTouchingMe extends BTTask`
- **Category:** `Condition`
- **Tham số:**
  - `touching_distance: float` (Mặc định `0.2` hoặc `0.8` tùy vị trí trong cây).
  - `target_player: String` (Mặc định `"$PlayerToChase"`).
- **Blackboard:**
  - Đọc: `$PlayerToChase`.
- **Hành vi từng tick (`on_update` / `evaluate_condition`):**
  - Lấy tọa độ Ghost và tọa độ Player.
  - Nếu `ghost.global_position.distance_to(player.global_position) <= touching_distance` -> Trả về `SUCCESS`.
  - Ngược lại -> Trả về `FAILURE`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func get_target_distance(p_target: Node3D) -> float:`

---

### 2.5. `BTAdvancedWithinDistance`
- **File:** `game/scripts/bt_tasks/bt_advanced_within_distance.gd`
- **Class:** `class_name BTAdvancedWithinDistance extends BTTask`
- **Category:** `Condition` / `Action`
- **Tham số:**
  - `magnitude: float` (Mặc định `5.0`): Bán kính kiểm tra.
  - `target_tag: String` (Mặc định `"RitualBook"` hoặc `""`): Tag đối tượng cần tìm.
  - `line_of_sight: bool` (Mặc định `true`): Cần nhìn thẳng không bị cản tường.
  - `returned_object: String` (Mặc định `"$RitualBook"` hoặc `"$PlayerWithinDistance"`).
- **Blackboard:**
  - Ghi: `$RitualBook` hoặc `$PlayerWithinDistance`.
- **Hành vi từng tick (`on_update` / `evaluate_condition`):**
  - Quét trong bán kính `magnitude` xem có đối tượng mang `target_tag` không.
  - Nếu có và thỏa mãn `line_of_sight`: Lưu đối tượng vào blackboard, trả về `SUCCESS`.
  - Ngược lại -> Trả về `FAILURE`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func query_nearby_objects(p_tag: String, p_radius: float, p_los: bool) -> Node3D:`

---

## 3. NHÓM ĐIỀU HƯỚNG & DI CHUYỂN (NAVIGATION & MOVEMENT)

### 3.1. `BTGhostGetWanderDestination`
- **File:** `game/scripts/bt_tasks/bt_ghost_wander_dest.gd`
- **Class:** `class_name BTGhostGetWanderDestination extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `min_distance: float` (Mặc định `5.0`).
  - `max_distance: float` (Mặc định `10.0`).
  - `returned_destination: String` (Mặc định `"WanderDestination"`).
- **Blackboard:**
  - Ghi: `$WanderDestination` (Vector3 tọa độ đích).
- **Hành vi từng tick (`on_update`):**
  - Gọi `actor.get_random_navmesh_point(min_distance, max_distance)`.
  - Lưu tọa độ trả về vào biến blackboard `$WanderDestination`.
  - Trả về `SUCCESS` ngay trong 1 tick.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func get_random_navmesh_point(p_min: float, p_max: float) -> Vector3:`

---

### 3.2. `BTGhostGetFleeDestination`
- **File:** `game/scripts/bt_tasks/bt_ghost_flee_dest.gd`
- **Class:** `class_name BTGhostGetFleeDestination extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `look_ahead_distance: float` (Mặc định `2.5`).
  - `player_variable: String` (Mặc định `"$PlayerWithinDistance"`).
  - `returned_destination: String` (Mặc định `"FleeDestination"`).
- **Blackboard:**
  - Đọc: `$PlayerWithinDistance`.
  - Ghi: `$FleeDestination` (Vector3 tọa độ chạy trốn).
- **Hành vi từng tick (`on_update`):**
  - Lấy vector ngược hướng từ Player tới Ghost: `dir = (ghost.pos - player.pos).normalized()`.
  - Tính điểm chạy trốn trên NavMesh theo hướng `dir * look_ahead_distance * 4.0`.
  - Lưu vào `$FleeDestination`.
  - Trả về `SUCCESS` trong 1 tick.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func compute_flee_point(p_threat_pos: Vector3, p_dist: float) -> Vector3:`

---

### 3.3. `BTGhostMoveTowards`
- **File:** `game/scripts/bt_tasks/bt_ghost_move_towards.gd`
- **Class:** `class_name BTGhostMoveTowards extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `speed: float` (Mặc định `1.0`, hỗ trợ `@Speed` binding).
  - `arrive_distance: float` (Mặc định `0.2`).
  - `target_variable: String` (Mặc định `"$WanderDestination"` hoặc `"$RitualBook"`).
  - `look_at_target: bool` (Mặc định `true`).
  - `rotation_speed: float` (Mặc định `90.0`).
  - `fleeing: bool` (Mặc định `false`).
- **Blackboard:**
  - Đọc: Tọa độ đích hoặc Node đích từ blackboard.
  - Đọc: `$Speed` (nếu dùng binding).
- **Hành vi từng tick (`on_update`):**
  - `on_start()`: Lấy tọa độ đích, gọi `actor.set_nav_target(dest_pos)`.
  - `on_update()`:
    - Gọi `actor.step_navigation(delta, speed, look_at_target)`.
    - Kiểm tra khoảng cách tới đích: nếu `dist <= arrive_distance` -> Dừng di chuyển, trả về `SUCCESS`.
    - Nếu đích không thể tới được (unreachable) -> Trả về `FAILURE`.
    - Đang di chuyển -> Trả về `RUNNING`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func set_nav_target(p_pos: Vector3) -> void:`
  - `func step_navigation(p_delta: float, p_speed: float, p_look_at: bool) -> float:` (trả về khoảng cách còn lại).
  - `func stop_navigation() -> void:`

---

### 3.4. `BTGhostPursue`
- **File:** `game/scripts/bt_tasks/bt_ghost_pursue.gd`
- **Class:** `class_name BTGhostPursue extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `arrive_distance: float` (Mặc định `1.0`).
  - `rotation_speed: float` (Mặc định `720.0`).
  - `sway_distance: float` (Mặc định `0.25`): Biên độ lượn sóng zic-zac.
  - `sway_speed: float` (Mặc định `1.5`): Tần số lượn sóng.
  - `target_variable: String` (Mặc định `"$PlayerToChase"`).
- **Blackboard:**
  - Đọc: `$PlayerToChase`.
  - Đọc: `$Speed`.
- **Hành vi từng tick (`on_update`):**
  - Lấy vị trí thời gian thực của `$PlayerToChase`.
  - Tính toán độ lệch ngang hình sin `sin(time * sway_speed) * sway_distance` để tạo quỹ đạo ma quái lượn sóng khó đoán.
  - Ra lệnh `actor.step_pursue(target_pos, speed, delta)`.
  - Nếu khoảng cách <= `arrive_distance` -> Trả về `SUCCESS`.
  - Đang dí -> Luôn trả về `RUNNING`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func step_pursue(p_target_pos: Vector3, p_speed: float, p_delta: float) -> void:`

---

### 3.5. `BTRotateTowards`
- **File:** `game/scripts/bt_tasks/bt_rotate_towards.gd`
- **Class:** `class_name BTRotateTowards extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `target_variable: String` (Mặc định `"$PlayerToChase"`).
  - `max_rotation_delta: float` (Mặc định `5.0`).
  - `only_y: bool` (Mặc định `true`).
- **Blackboard:**
  - Đọc: `$PlayerToChase`.
- **Hành vi từng tick (`on_update`):**
  - Xoay góc `rotation.y` của Ghost hướng về mục tiêu với tốc độ góc giới hạn `max_rotation_delta`.
  - Trả về `SUCCESS` khi góc lệch < 5 độ, ngược lại `RUNNING`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func rotate_towards_point(p_pos: Vector3, p_max_delta: float) -> bool:`

---

## 4. NHÓM ĐIỀU TRẠNG THÁI & THAM SỐ (STATE & PARAMETERS)

### 4.1. `BTSetSpeed`
- **File:** `game/scripts/bt_tasks/bt_set_speed.gd`
- **Class:** `class_name BTSetSpeed extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `speed: float` (Mặc định `1.0`).
- **Blackboard:**
  - Ghi: `$Speed = speed`.
- **Hành vi từng tick (`on_update`):**
  - Ghi giá trị vào biến `$Speed` trên blackboard.
  - Gọi `actor.set_motor_speed(speed)`.
  - Trả về `SUCCESS` ngay lập tức.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func set_motor_speed(p_speed: float) -> void:`

---

### 4.2. `BTSetIntegerParameter`
- **File:** `game/scripts/bt_tasks/bt_set_int_param.gd`
- **Class:** `class_name BTSetIntegerParameter extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `parameter_name: String` (Ví dụ `"AbilityIndex"`, `"AbilityIntData"`).
  - `int_value: int` (Ví dụ `0`, `201`, `202`, `204`, `666`).
- **Blackboard:**
  - Ghi: Cập nhật biến tương ứng trên blackboard.
- **Hành vi từng tick (`on_update`):**
  - Đặt biến trên blackboard: `set_blackboard_var(parameter_name, int_value)`.
  - Gọi kênh điều khiển trên actor: `actor.set_parameter(parameter_name, int_value)`.
  - Trả về `SUCCESS` trong 1 tick.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func set_parameter(p_name: String, p_val: int) -> void:`

---

### 4.3. `BTCompareIntegerParameter`
- **File:** `game/scripts/bt_tasks/bt_compare_int_param.gd`
- **Class:** `class_name BTCompareIntegerParameter extends BTTask`
- **Category:** `Condition`
- **Tham số:**
  - `parameter_name: String` (Mặc định `"AbilityIndex"` hoặc `"AbilityIntData"`).
  - `compare_to: int` (Mặc định `108`, `204`, `666`).
  - `animator_game_object: String` (Tùy chọn: kiểm tra trên player hay trên ghost).
- **Blackboard:**
  - Đọc: `parameter_name` từ blackboard (hoặc từ player state).
- **Hành vi từng tick (`on_update` / `evaluate_condition`):**
  - Nếu đối tượng là player (ví dụ check `AbilityIndex == 108` - đang ẩn nấp):
    - Đọc `player.get_ability_index()`.
  - Nếu đối tượng là Ghost: Đọc từ blackboard `get_blackboard_var(parameter_name)`.
  - Trả về `SUCCESS` nếu bằng nhau, ngược lại `FAILURE`.
- **Hợp đồng Actor (`player_controller.gd` & `ghost_actor.gd`):**
  - `func get_ability_index() -> int:`

---

### 4.4. `BTSetSharedBool` & `BTCompareSharedBool`
- **File:** `game/scripts/bt_tasks/bt_shared_bool.gd`
- **Class:** `class_name BTSetSharedBool extends BTTask` / `class_name BTCompareSharedBool extends BTTask`
- **Category:** `Action` / `Condition`
- **Tham số:**
  - `variable_name: String` (Ví dụ `"IsFleeing"`, `"StartedFocus"`, `"NearRitualBook"`).
  - `value: bool` (hoặc `compare_to: bool`).
- **Blackboard:** Đọc/Ghi biến bool tương ứng.
- **Hành vi:**
  - `BTSetSharedBool`: Gán biến trên blackboard, trả về `SUCCESS`.
  - `BTCompareSharedBool`: Đọc biến trên blackboard, so sánh, trả về `SUCCESS` nếu bằng, `FAILURE` nếu khác.

---

### 4.5. `BTSetSharedGameObject`
- **File:** `game/scripts/bt_tasks/bt_set_shared_game_object.gd`
- **Class:** `class_name BTSetSharedGameObject extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `target_variable: String` (Tên biến cần gán, ví dụ `"PlayerToChase"`).
  - `source_variable: String` (Tên biến nguồn, ví dụ `"OtherPlayerToChase"`).
  - `value_can_be_null: bool` (Mặc định `false`, nếu true và nguồn null thì xóa biến đích thành null).
- **Blackboard:** Đọc biến nguồn, gán sang biến đích.
- **Hành vi:** Trả về `SUCCESS` ngay trong 1 tick.

---

## 5. NHÓM ĐẾM THỜI GIAN & ĐỐI ĐẦU ĐÈN PIN (TIMERS & FRYING)

### 5.1. `BTWait`
- **File:** `game/scripts/bt_tasks/bt_wait.gd`
- **Class:** `class_name BTWait extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `wait_time: float` (Mặc định `1.0`).
  - `random_wait: bool` (Mặc định `false`).
  - `random_wait_min: float` (Mặc định `1.0`).
  - `random_wait_max: float` (Mặc định `3.0`).
- **Biến nội bộ:** `elapsed_time: float = 0.0`, `current_duration: float = 0.0`.
- **Hành vi từng tick (`on_update`):**
  - `on_start()`: Nếu `random_wait`, lấy ngẫu nhiên giữa min/max, ngược lại dùng `wait_time`. Reset `elapsed_time = 0.0`.
  - `on_update()`: Tích lũy `elapsed_time += delta`.
  - Nếu `elapsed_time >= current_duration` -> Trả về `SUCCESS`.
  - Còn lại -> Trả về `RUNNING`.

---

### 5.2. `BTPlayersFocusingMeWait`
- **File:** `game/scripts/bt_tasks/bt_players_focusing_me_wait.gd`
- **Class:** `class_name BTPlayersFocusingMeWait extends BTTask`
- **Category:** `Action`
- **Mục đích:** Port từ `BehaviorDesigner.Runtime.Tasks.PlayersFocusingMeWait`. Đo thời gian người chơi rọi UV tập trung vào Ghost.
- **Tham số:**
  - `wait_time: float` (Mặc định `1.5`): Thời gian cần rọi liên tục để thiêu chết Ghost.
- **Biến nội bộ:** `accumulated_time: float = 0.0`.
- **Hành vi từng tick (`on_update`):**
  - Hỏi actor: `actor.is_flashlight_shining_on_me(true, 6.0)`.
  - Nếu có tia UV chiếu trúng:
    - `accumulated_time += delta`.
    - Nếu `accumulated_time >= wait_time` -> Reset biến, trả về `SUCCESS` (Kích hoạt Death Sequence!).
    - Ngược lại -> Trả về `RUNNING`.
  - Nếu tia UV bị rời ra hoặc tắt:
    - Giảm dần thời gian tích lũy (decay rate: `accumulated_time -= delta * 0.5`) hoặc reset về 0.
    - Trả về `FAILURE`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func is_flashlight_shining_on_me(p_fry_only: bool, p_max_dist: float) -> Node3D:`

---

## 6. NHÓM TƯƠNG TÁC RITUAL BOOK & SỰ KIỆN GAMEPLAY

### 6.1. `BTRitualBookAction`
- **File:** `game/scripts/bt_tasks/bt_ritual_book_action.gd`
- **Class:** `class_name BTRitualBookAction extends BTTask`
- **Category:** `Action`
- **Mục đích:** Gom các task nhỏ liên quan tới Cuốn sách Cúng tế (`CanCarryInteractable`, `BoltDetach`, `GetStringStateValue`, `SetStringStateValue`).
- **Tham số:**
  - `action_type: String` (Các giá trị: `"can_carry"`, `"detach"`, `"get_metadata"`, `"set_carry_name"`).
  - `book_variable: String` (Mặc định `"$RitualBook"`).
- **Blackboard:** Đọc `$RitualBook`, ghi `$RitualBookMetadata`.
- **Hành vi từng tick (`on_update`):**
  - `"can_carry"`: Kiểm tra sách có thể nhặt không -> `SUCCESS`.
  - `"detach"`: Tháo chốt sách khỏi bàn thờ -> `SUCCESS`.
  - `"get_metadata"`: Lưu chuỗi `"CursedBook_01"` vào `$RitualBookMetadata` -> `SUCCESS`.
  - `"set_carry_name"`: Gọi `actor.attach_object_to_hand(book)` -> `SUCCESS`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func attach_carried_object(p_obj: Node3D) -> void:`

---

### 6.2. `BTExecuteEvent`
- **File:** `game/scripts/bt_tasks/bt_execute_event.gd`
- **Class:** `class_name BTExecuteEvent extends BTTask`
- **Category:** `Action`
- **Tham số:**
  - `event_name: String` (Ví dụ `"SetLookAtEntity"`, `"OnGhostPursue"`, `"OnSpawnRitualBook"`).
  - `target_object: String` (Tùy chọn: đối tượng gửi kèm).
- **Hành vi từng tick (`on_update`):**
  - Gọi `actor.handle_bt_event(event_name, target)`.
  - Trả về `SUCCESS` ngay lập tức.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func handle_bt_event(p_event_name: String, p_data = null) -> void:`

---

### 6.3. `BTStopBehaviorTree`
- **File:** `game/scripts/bt_tasks/bt_stop_behavior_tree.gd`
- **Class:** `class_name BTStopBehaviorTree extends BTTask`
- **Category:** `Action`
- **Hành vi từng tick (`on_update`):**
  - Gọi `runner.stop()` hoặc `actor.on_ghost_banished()`.
  - Trả về `SUCCESS`.
- **Hợp đồng Actor (`ghost_actor.gd`):**
  - `func on_ghost_banished() -> void:`

---

## 7. BẢNG TỔNG KẾT HỢP ĐỒNG ACTOR API (`ghost_actor.gd`)

Để toàn bộ cây AI chạy trơn tru, class `GhostActor` trong `game/scripts/ghost_actor.gd` **bắt buộc phải khai báo đầy đủ các phương thức sau**:

```gdscript
class_name GhostActor
extends CharacterBody3D

# --- Motor & Movement ---
func set_motor_speed(p_speed: float) -> void: pass
func set_nav_target(p_destination: Vector3) -> void: pass
func step_navigation(p_delta: float, p_speed: float, p_look_at: bool) -> float: return 0.0 # Trả cự ly còn lại
func step_pursue(p_target_pos: Vector3, p_speed: float, p_delta: float) -> void: pass
func stop_navigation() -> void: pass
func get_random_navmesh_point(p_min_dist: float, p_max_dist: float) -> Vector3: return Vector3.ZERO
func compute_flee_point(p_threat_pos: Vector3, p_distance: float) -> Vector3: return Vector3.ZERO
func rotate_towards_point(p_point: Vector3, p_max_delta: float) -> bool: return true

# --- Perception & Sensors ---
func is_flashlight_shining_on_me(p_fry_only: bool, p_max_dist: float) -> Node3D: return null
func can_see_target(p_target: Node3D, p_fov_deg: float, p_max_dist: float) -> bool: return false
func detect_player_noise(p_walk_radius: float, p_sprint_radius: float) -> Node3D: return null
func query_nearby_objects(p_tag: String, p_radius: float, p_los: bool) -> Node3D: return null
func get_target_distance(p_target: Node3D) -> float: return 999.0

# --- State & Events ---
func set_parameter(p_name: String, p_val: int) -> void: pass
func get_ability_index() -> int: return 0
func handle_bt_event(p_event_name: String, p_data = null) -> void: pass
func attach_carried_object(p_obj: Node3D) -> void: pass
func drop_carried_object() -> void: pass
func on_ghost_banished() -> void: pass
```
