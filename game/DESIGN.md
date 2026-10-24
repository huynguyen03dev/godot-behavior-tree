# TÀI LIỆU THIẾT KẾ GAME: DEVOUR CLONE (FARMHOUSE - MOLLY)

> **Dành cho:** Toàn bộ team phát triển (Asset/Blender, Gameplay Code, BT Behaviors, QA).  
> **Phiên bản tài liệu:** 2.0 — Chốt Map Farmhouse (Level 2 - Molly) & Nghi thức Thiêu Đốt Chuột.  
> **Framework AI cốt lõi:** Addon Behavior Tree nội bộ (`addons/godot_bt` native Rust + GDScript API) đặt tại `/home/hazeruno/IT/workspace/godot-behavior-tree`.

---

## 1. TỔNG QUAN DỰ ÁN & CONCEPT

- **Tên dự án:** *Devour Clone: Farmhouse Ritual (Molly)*
- **Bối cảnh & Map:** Nhà gỗ nông trại 2 tầng + tầng hầm bỏ hoang (Farmhouse).
- **Thể loại:** 3D Survival Horror góc nhìn thứ nhất (FPS), Single-player, nhịp độ căng thẳng.
- **Engine mục tiêu:** Godot 4.7.2 (Renderer: Forward+ hoặc Compatibility, low-poly 3D).
- **Mục tiêu cốt lõi:** Tái hiện trung thực 1:1 hành vi của con ma (Ghost/Demon Molly) từ game Devour (nguồn: reverse-engineering cây `Ghost_42115.json` 203 node với 3 nhánh song song).

### Tóm tắt Trải nghiệm (Elevator Pitch)
Người chơi thức tỉnh tại căn nhà gỗ nông trại hẻo lánh trong đêm mưa bão. Nơi đây từng diễn ra lễ tế tà giáo của Molly, biến cô thành một quỷ hồn khát máu tuần tra khắp các tầng lầu. Để phá giải lời nguyền và trục xuất Molly, người chơi phải lẻn qua các phòng, tìm chìa khóa mở các khu vực bị niêm phong, lắp cầu chì bật điện, lùng sục các thùng rác ở tầng hầm và ngóc ngách để **bắt những con chuột bị nguyền rủa (Cursed Rats)** mang về thiêu đốt tại Lò thiêu / Bàn thờ (Altar). Khi đủ 9 con chuột được hiến tế thành tro bụi, lời nguyền tan biến và Molly bị trục xuất vĩnh viễn. Nếu để Molly áp sát bắt đủ 3 lần, người chơi sẽ bỏ mạng.

---

## 2. BẢN ĐỒ FARMHOUSE & BỐ TRÍ KHÔNG GIAN

Map được thiết kế theo kiến trúc nhà gỗ 2 tầng + 1 tầng hầm với NavMesh 3D liền mạch:

```diagram
┌────────────────────────────────────────────────────────────────────────┐
│                          TẦNG 2 (UPSTAIRS)                             │
│      ┌─────────────────────┐             ┌─────────────────────┐       │
│      │  Phòng ngủ 1 (Lock) │             │  Phòng ngủ 2 (Lock) │       │
│      └──────────┬──────────┘             └──────────┬──────────┘       │
│                 │                                   │                  │
│                 └─────────────┬─────────────────────┘                  │
│                               │ Hành lang lầu 2                        │
│                               ▼ Cầu thang gỗ xuống                     │
├────────────────────────────────────────────────────────────────────────┤
│                          TẦNG 1 (GROUND FLOOR)                         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐    │
│  │  Hiên trước  │────▶│ Sảnh khách   │────▶│ Bếp (Kitchen)        │    │
│  │ (FrontPorch) │     │ (Living Room)│     │ Chứa Fusebox cầu chì │    │
│  └──────────────┘     └──────┬───────┘     └──────────┬───────────┘    │
│                              │                        │                │
│                              │     ┌───────────────┐  │                │
│                              ├────▶│ Nhà tắm (Bath)│  │                │
│                              │     └───────────────┘  │                │
│                              ▼                        ▼                │
│                 Hành lang tầng trệt ──────── Cửa tầng hầm (Khoá)       │
├────────────────────────────────────────────────────────────────────────┤
│                          TẦNG HẦM (BASEMENT)                           │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  LÒ THIÊU TẾ LỄ (ALTAR / FURNACE)                                │  │
│  │  - Nơi thả chuột vào thiêu đốt hiến tế.                          │  │
│  │  - Các dãy thùng rác (Trash Cans) chứa chuột ẩn nấp.             │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

### Các phòng tối thiểu cần có:
1. **Hiên trước (Front Porch):** Điểm khởi đầu (Player Spawn), có cửa chính dẫn vào sảnh khách.
2. **Sảnh khách (Living Room / Foyer):** Không gian mở rộng nối liền cầu thang lên tầng 2 và lối đi xuống bếp.
3. **Bếp (Kitchen):** Chứa Hộp cầu chì (Fusebox) tổng của ngôi nhà và 1 thùng rác.
4. **Hành lang tầng trệt (Hallway):** Nối sảnh khách, nhà tắm và cửa xuống tầng hầm.
5. **Nhà tắm (Bathroom):** Phòng nhỏ, ngóc ngách dễ nhặt pin hoặc chuột chạy trốn.
6. **2 Phòng ngủ tầng 2 (Bedrooms 1 & 2):** Ban đầu bị khóa cửa (`is_locked = true`), cần tìm đúng Chìa khóa (Keys) rải rác dưới tầng 1 để mở. Bên trong chứa chuột và vật phẩm phụ.
7. **Tầng hầm (Basement):** Khu vực u ám nhất, đặt **Bàn thờ / Lò thiêu tế lễ (Altar/Furnace)**. Chứa nhiều thùng rác chứa chuột bị nguyền rủa nhất.
8. *(Tùy chọn)* **Gác xép (Attic):** Dành cho bản mở rộng nếu team dựng kịp.

---

## 3. MỤC TIÊU CỐT LÕI & VÒNG LẶP CHƠI (CORE LOOP)

Thời lượng một ván: **6 – 10 phút**.

```diagram
┌────────────────────────────────────────────────────────────────────────┐
│                        SPAWN & KHỞI ĐỘNG VÁN                           │
│  - Người chơi cầm đèn pin tại hiên trước. Điện nhà đang tắt.          │
│  - Ghost Molly xuất hiện ở tầng 2, bắt đầu tuần tra (Wander).          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      TÌM FUSE & BẬT ĐIỆN NHÀ                           │
│  - Tìm Cầu chì (Fuse) lắp vào Fusebox ở bếp.                          │
│  - Đèn hành lang bật sáng, giúp mở rộng tầm nhìn, giảm phụ thuộc đèn. │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      TÌM KEY MỞ CỬA & BẮT CHUỘT                        │
│  - Tìm Key mở cửa tầng hầm và 2 phòng ngủ lầu 2.                      │
│  - Mở các thùng rác (Trash Cans) để chuột chạy ra, đuổi bắt chuột.    │
│  - Mỗi lần người chơi chỉ ôm được 1 con chuột trên tay.               │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      MANG CHUỘT VỀ ĐỐT TẠI ALTAR                       │
│  - Đem chuột xuống lò thiêu Altar ở tầng hầm, nhấn E để thiêu đốt.    │
│  - Mỗi con chuột bị đốt:                                               │
│    + `burnt_count += 1`.                                               │
│    + Ghost Molly hú lên dữ dội, tốc độ rượt đuổi tăng dần.            │
│    + Kích hoạt spawn thêm chuột từ các hang hốc (tối đa 20 con tổng).  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                  ┌─────────────────┴─────────────────┐
                  ▼                                   ▼
┌──────────────────────────────────┐ ┌──────────────────────────────────┐
│      ĐIỀU KIỆN THẮNG (WIN)       │ │       ĐIỀU KIỆN THUA (LOSS)      │
│  - Đốt thành công ĐỦ 9 CON CHUỘT │ │  - Người chơi bị Molly áp sát    │
│    tại Altar (`burnt_count >= 9`).│ │    bắt đủ 3 lần (Downed 3/3).   │
│  - Molly bị thiêu rụi hoàn toàn, │ │  - Màn hình tối sầm, linh hồn    │
│    cây AI dừng (`runner.stop()`).│ │    bị hiến tế (Game Over).       │
└──────────────────────────────────┘ └──────────────────────────────────┘
```

---

## 4. HỆ THỐNG VẬT PHẨM (ITEMS SPECIFICATION)

Dựa trên dữ liệu gốc của Devour Level 2 (Molly Farmhouse), danh mục vật phẩm được chọn lọc và đơn giản hóa cho bản clone:

| Vật phẩm | Trạng thái trong Game | Vị trí xuất hiện | Tác dụng Gameplay & Cơ chế |
|---|---|---|---|
| **Chuột (Cursed Rat)** | **BẮT BUỘC (CORE)** | Thùng rác tầng hầm, bếp, góc phòng ngủ (11 con ban đầu + 9 con spawn bổ sung) | Mục tiêu chính. Chuột chạy nhảy ngẫu nhiên trên NavMesh. Người chơi đến gần bấm E để bắt vào tay (chỉ giữ được 1 con một lúc). Mang tới Altar bấm E để thiêu đốt. |
| **Chìa khóa (Key)** | **BẮT BUỘC (CORE)** | 2–3 chìa rải ngẫu nhiên trên bàn/kệ | Mở các cửa phòng khóa: Chìa khóa Tầng hầm (Basement Key), Chìa khóa Phòng ngủ 1 (Bedroom 1 Key). Dùng 1 lần mở vĩnh viễn. |
| **Cầu chì (Fuse)** | **BẮT BUỘC (CORE)** | 1–2 cầu chì trong ngăn kéo hoặc phòng tắm | Cầm đặt vào Fusebox ở phòng Bếp để bật hệ thống đèn chiếu sáng hành lang. Khi có điện, người chơi dễ quan sát và đỡ tốn pin đèn pin. |
| **Pin đèn (Battery)** | **BẮT BUỘC (CORE)** | Rải rác 2–3 cục trên kệ sách/bàn | Khi nhặt, hồi phục ngay lập tức 100% năng lượng pin đèn UV. |
| **Hộp sơ cứu (FirstAid)** | **ĐƠN GIẢN HÓA** | 1 hộp duy nhất ở Nhà tắm | Nhặt để hồi sinh / xóa 1 lần bị bắt (nếu đã bị bắt 1 hoặc 2 lần thì trừ đi 1). |
| **Thức ăn (Food)** | **CẮT BỎ (DROPPED)** | Không đưa vào game | Thể lực (Stamina) đã có cơ chế tự động hồi phục sau 2 giây không chạy nhanh. Cắt bỏ để tránh làm rác túi đồ và phức tạp hóa tương tác. |

---

## 5. GHOST MOLLY & CÂY AI `Ghost_42115`

Ghost Molly sử dụng nguyên vẹn cây Behavior Tree đã đặc tả trong [`game/BT_PORT.md`](file:///home/hazeruno/IT/workspace/godot-behavior-tree/game/BT_PORT.md).

### Ánh xạ ngữ nghĩa trên Map Farmhouse:
1. **Tuần tra (Wander):** Molly bay lơ lửng tuần tra giữa tầng 1, tầng 2 và tầng hầm qua cầu thang NavMesh.
2. **Cảm tri (Perception):**
   - Nhìn thấy người chơi (FOV 75°, cự ly 20m).
   - Nghe tiếng bước chân chạy nhanh trên sàn gỗ kêu cót két (15m).
   - Bị đèn pin lia trúng (15m).
3. **Phản xạ Đèn pin UV (Nhánh 1 & Nhánh 2):**
   - Rọi đèn UV: Molly bị thiêu đốt làm chậm tụt tốc độ còn `0.1 m/s`, gào rú giật lùi (`AbilityIntData = 666`).
   - Rọi liên tục 1.5s: Molly bị trục xuất tạm thời (`AbilityIndex = 204`), tan biến trong 30s trước khi hồi sinh ở góc xa.
4. **Cơ chế Ưu tiên Vật phẩm Tế lễ (`RitualBook` trong cây BT):**
   - Biến `$RitualBook` trong cây BT gốc của Devour đại diện cho **Vật phẩm Tế lễ Thiêng liêng**.
   - Trên map Farmhouse, khi người chơi **đang bế chuột trên tay** hoặc **đang ở gần Altar lò thiêu**, Molly coi đó là mối đe dọa tế lễ trực tiếp -> Kích hoạt `PerformInterruption`, bỏ qua tuần tra để lao thẳng tới người chơi nhằm cướp lại hoặc bảo vệ chuột!
5. **Tăng độ khó theo tiến độ đốt chuột:**
   - Mỗi khi đốt 1 con chuột tại Altar, tốc độ truy đuổi của Molly tăng lũy tiến từ `1.5 m/s` lên tối đa `2.5 m/s` (khớp với mảng gốc `dodgeSpeeds = [1.25, 1.4, 1.55, 1.7, 1.85, 2.0, 2.15, 2.3, 2.5]`). Càng về những con chuột cuối, Molly càng hung bạo.

---

## 6. ĐIỀU KHIỂN & TƯƠNG TÁC (CONTROLS)

| Phím / Chuột | Hành động | Chi tiết cơ chế |
|---|---|---|
| **W, A, S, D** | Di chuyển người chơi | Đi bộ `3.5 m/s`. |
| **Shift (Giữ)** | Chạy nhanh (Sprint) | `6.0 m/s`, hao Stamina. Gây tiếng chân to trên sàn gỗ (nghe xa 15m). |
| **Ctrl (Giữ/Toggle)** | Ngồi khẽ (Crouch) | `1.8 m/s`, chiều cao camera 0.9m. Không phát ra tiếng động bước chân (`crouchHearingRadius = 0m`). |
| **F** | Đèn pin thường | Chiếu sáng cơ bản. |
| **Chuột Phải / Trái (Giữ)** | Rọi đèn UV tập trung (Fry) | Chùm sáng UV tím làm chậm và đốt Molly. Tiêu hao pin UV (tối đa 5s liên tục). |
| **E** | Tương tác đa năng | Nhặt Key/Fuse/Battery; mở nắp thùng rác; vồ bắt chuột; cắm Fuse vào Fusebox; ném chuột vào Altar lò thiêu. |

---

## 7. BỐ CỤC THƯ MỤC CHUẨN (FOLDER LAYOUT)

```
game/
├── DESIGN.md                  # Tài liệu thiết kế tổng thể Farmhouse (File này)
├── BT_PORT.md                 # Đặc tả chi tiết ánh xạ Behavior Tree Devour -> Addon
├── TASKS.md                   # Danh mục toàn bộ custom tasks GDScript & Actor API
├── TEST_PLAN.md               # Kế hoạch kiểm thử Headless E2E & các bất biến Farmhouse
├── README.md                  # Hướng dẫn build, chạy game và chạy test
├── assets/
│   ├── models/                # File GLB: ghost, player, rat, trash_can, altar, fuse, key, battery, farmhouse_kit
│   ├── blender/               # Script Python tự động tạo/xuất model Blender (*.py)
│   ├── textures/              # Texture gỗ mộc, kim loại rỉ sét, da chuột low-poly
│   └── audio/                 # SFX: molly_scream, rat_squeak, wood_footstep, furnace_burn, fuse_click
├── scenes/
│   ├── main.tscn              # Scene chính Farmhouse (2 tầng + tầng hầm)
│   ├── player.tscn            # Scene nhân vật người chơi FPS
│   ├── ghost.tscn             # Scene Ghost Molly tích hợp BTRunner
│   ├── rat.tscn               # Scene chuột chạy nhảy có va chạm/NavMesh
│   ├── trash_can.tscn         # Scene thùng rác có nắp mở ra chuột
│   ├── altar.tscn             # Scene lò thiêu tế lễ ở tầng hầm
│   ├── door.tscn              # Scene cửa gỗ (có cờ locked)
│   └── fusebox.tscn           # Scene hộp cầu chì bật điện
├── scripts/
│   ├── player_controller.gd   # Điều khiển người chơi, đèn pin, nhặt đồ
│   ├── ghost_actor.gd         # Triển khai Actor API kết nối Motor & BT
│   ├── game_manager.gd        # Quản lý 9 chuột = win, 3 grab = loss, spawn chuột
│   ├── rat.gd                 # Logic AI di chuyển ngẫu nhiên của chuột
│   ├── altar.gd               # Kiểm tra và thiêu đốt chuột (`burnt_count`)
│   ├── door.gd                # Kiểm tra chìa khóa và mở cửa
│   ├── fusebox.gd             # Bật đèn hành lang khi có cầu chì
│   ├── ui_hud.gd              # Hiển thị số chuột đã đốt (x/9), pin, stamina, mạng
│   └── bt_tasks/              # Toàn bộ 29 custom tasks GDScript đã định nghĩa
├── bt/
│   ├── ghost_main_tree.json   # Cây chính Ghost port từ Ghost_42115.json
│   └── subtrees/
│       ├── ghost_pursue.json  # Subtree rượt đuổi & tấn công
│       └── ghost_wander.json  # Subtree đi tuần
└── tests/
    └── test_game_e2e.gd       # Test suite chạy headless kiểm tra toàn bộ AI & Gameplay
```

---

## 8. DEFINITION OF DONE (DoD) CẬP NHẬT CHO FARMHOUSE

1. **Asset/Blender Agent:** Cung cấp đầy đủ model GLB: `ghost.glb` (Molly), `rat.glb` (chuột), `trash_can.glb` (thùng rác), `altar.glb` (lò thiêu tầng hầm), `fuse.glb`, `key.glb`, `battery.glb`, và bộ kit nhà gỗ 2 tầng + tầng hầm.
2. **Gameplay Code Agent:** Cài đặt logic nhặt chuột, mở thùng rác, ném chuột vào Altar đốt (`burnt_count`), cửa khóa cần Key, Fusebox lắp cầu chì bật đèn, GameManager đếm đủ 9 chuột -> Thắng; 3 lần bị bắt -> Thua.
3. **BT Behaviors Agent:** Giữ nguyên 100% cây `Ghost_42115` và 2 subtrees, map sự kiện chuột/Altar vào kênh nhận thức của Molly.
4. **QA Agent:** `game/tests/test_game_e2e.gd` kiểm tra đạt 100% toàn bộ các bất biến của cả Ghost AI và cơ chế Farmhouse mới.
