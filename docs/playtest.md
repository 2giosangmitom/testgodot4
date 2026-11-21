# Kiểm tra bản chơi

## Tự động

Dùng Godot 4.7.2. Từ thư mục dự án:

```sh
godot --headless --editor --path . --import
godot --headless --path . -- --autoplay --ending=A
godot --headless --path . -- --autoplay --ending=B
```

Autoplay chạy từ menu tới credits và tự thoát, không ghi đè checkpoint hoặc đánh dấu đã xem kết thúc.
A chọn Tuấn và tích đủ điểm; B làm nghi thức nhưng chọn sai tên, không tích đủ điểm. Cả hai
nhánh đều do `GameState.compute_ending()` quyết định, không cưỡng ép tải ending theo tham số.
Autoplay mô phỏng thao tác/trigger, không thay thế chơi thử đường đi, ngắm và va chạm.

```sh
godot --headless --path . -s res://tests/run_tests.gd
godot --headless --path . -s res://gameplay/entities/test/run_logic_tests.gd
godot --headless --path . -s res://gameplay/minigames/test/run_logic_tests.gd
godot --headless --path . res://player/test_integration.tscn
XDG_DATA_HOME="$(mktemp -d /tmp/opencode/test-game-checkpoint-XXXXXX)" \
  godot --headless --path . -s res://tests/checkpoint_smoke.gd

for level in school store_alley dorm_shrine; do
  godot --headless --path . -s "res://levels/$level/test_level.gd" || break
done
```

## Chơi thử thật

- Chơi mới từ menu; bước tới cổng trường và hoàn thành cả hai lượt thanh toán, xếp hàng, lau sàn.
- Thử nhìn Gazer lâu trong Chương 1: phải có nhiễu nhưng không chết. Thử trả lời Mimic ở Chương 2:
  cảnh bị bắt phải đưa về checkpoint với số điểm và đồ vật cũ. Kiểm tra lại bằng nút **Tiếp tục**.
- Thử khóa cửa, tắt đèn khi có tiếng gõ, đi cầu thang lúc mất điện, và chui thật vào gầm bàn P.204.
- Tự đi qua nhóm chờ xe buýt tới tạp hóa; so sánh đi bộ với chạy/rọi đèn. Thử bỏ qua bảng tìm người.
- Thử đúng tên, sai tên và bỏ nghi thức. Sau Ending A, tự đi từ miếu về đầu ngõ.
- Nghe giọng Mimic Hùng/Linh và Tuấn; đối chiếu thoại, nhạc, chuông và tiếng giật mình bằng tai nghe.

Kiểm tra riêng renderer bằng `res://render/test_psx.tscn -- --preset=night --static=0.45`; đặt
`--rendering-method forward_plus --rendering-driver vulkan` hoặc `--rendering-method gl_compatibility`
trước đường dẫn scene. So sánh sương, vật liệu xuyên kính, dither và chữ HUD trên cả hai.

## Đóng gói

Cần export templates tương thích với bản Godot đang chạy; không tải nếu chưa được đồng ý.

```sh
mkdir -p build/linux build/windows
godot --headless --path . --export-release "Linux x86_64"
godot --headless --path . --export-release "Windows x86_64"
```
