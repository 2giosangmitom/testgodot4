# ĐÈN ĐƯỜNG CUỐI NGÕ — Kịch bản

> File này là nguồn duy nhất cho thoại và tin nhắn. `tools/story/story_to_json.py` đọc các dòng
> `- \`key\` **speaker** [fx]: text` và `- msg \`id\` **from** HH:MM (chN): text` để sinh `data/dialogue/*.json`.
> fx: `none` (mặc định) · `phone` · `radio` · `door` (nghe qua cửa) · `entity` (giọng thực thể) · `far`

## Bối cảnh & thần thoại

Hà Nội, hiện tại. **Nam** (20 tuổi, sinh viên năm hai, quê Nam Định) thuê phòng **P.204** trong một dãy trọ
ở cuối con ngõ ngoằn ngoèo sau cửa hàng **Tiện Lợi 24h Ánh Dương**, nơi cậu làm ca đêm.
Bạn cùng phòng là **Hùng** (quê Thái Bình, xởi lởi). Bạn cùng lớp **Linh** mê chuyện tâm linh phố cũ.

Cuối hẻm cụt có một **ngôi miếu nhỏ dưới gốc đa**, dân trong ngõ gọi là **miếu Ông Đèn**. Ngày xưa đây là
ngã ba bãi tha ma; người ta lập miếu và giữ một **ngọn đèn dầu cháy suốt đêm** để những thứ "đứng chờ
trong sương" không đi vào ngõ. Lệ cũ: *đèn miếu tắt thì phải có một người đứng trông thay*.

Khi phường dựng **cây đèn đường cao áp** cạnh miếu, người ta nghĩ đèn điện là đủ, bỏ bẵng đèn dầu.
Chỉ còn **Tuấn** — người làm ca đêm trước Nam, cũng là người thuê P.204 trước Nam — được bà chủ trọ cũ
nhờ châm dầu mỗi sáng tan ca. Đêm Tuấn quên (đúng đêm Nam chuyển đến), đèn miếu tắt. Từ đó Tuấn
**đứng dưới cây đèn đường**, cao lêu nghêu, không chớp mắt: **Kẻ Đứng Nhìn**. Anh ta đang nhìn
người kế tiếp: Nam.

Vì đèn miếu tắt, những thứ khác cũng lọt vào: **Kẻ Thế Thân** (mượn mặt và giọng người quen),
và về sau cả thành phố ban đêm lẫn vào **Đám Đông Vô Hồn**.

**Mục tiêu ẩn của người chơi:** giữ các "luật", để ý tin nhắn thật/giả, tìm lại đồ thờ, và
**gọi đúng tên Tuấn** khi thắp lại đèn miếu.

## Hệ thống `resolve` & hai kết thúc

`resolve` là điểm tích lũy khi người chơi tuân luật và quan tâm chi tiết. Bị bắt thì nạp lại checkpoint,
`resolve` cũng trở về giá trị lúc lưu. Ngưỡng Ending A: **resolve ≥ 6** **và** đã thắp đèn miếu.

| # | Chương | Hành động | +resolve | flag |
|---|---|---|---|---|
| 1 | Ch1 | Đọc tờ "Quy tắc ca đêm" | +1 | `read_rules` |
| 2 | Ch1 | Không nhìn Kẻ Đứng Nhìn quá lâu suốt ca (không bị đơ màn hình lần nào) | +1 | `ch1_no_stare` |
| 3 | Ch1 | Thắp nhang ở bàn thờ nhỏ trong ngõ trên đường về | +1 | `ch1_incense_alley` |
| 4 | Ch2 | Đọc tin nhắn của Hùng **trước khi** tiếng gõ cửa bắt đầu nói | +1 | `read_m_ch2_hung_01` |
| 5 | Ch2 | Tắt đèn phòng khi có tiếng gõ (giả như không có nhà) | +1 | `ch2_lights_off` |
| 6 | Ch2 | Không bao giờ nhìn thẳng "Linh" ở hành lang quá 2 giây | +1 | `ch2_ignored_linh` |
| 7 | Ch3 | Nghe hết chuyện của bác Tư | +1 | `ch3_bac_tu_story` |
| 8 | Ch3 | Không làm Đám Đông báo động lần nào | +1 | `ch3_silent` |
| 9 | Ch3 | Lấy được thẻ tên của Tuấn (tùy chọn) | +1 | `has_name_tag` |
| 10 | Ch4 | Thắp nhang + đặt ảnh lên bàn thờ miếu | +1 | `ch4_offering` |
| 11 | Ch4 | Gọi đúng tên "Tuấn" | +2 | `ch4_called_name` |

Thắp đèn mà resolve < 6 → đèn chập chờn rồi tắt → Ending B. Không thắp → Ending B.
Người chơi bất cẩn ở lần đầu thường ra B, và chơi lại (chọn chương sau khi xong) để lấy A.

## Checkpoint

`ch1_school` · `ch1_store` · `ch1_alley` · `ch2_store` · `ch2_dorm` · `ch2_breaker` · `ch3_street` · `ch3_gate` · `ch4_alley` · `ch4_shrine`

---

## CHƯƠNG 1: CA ĐÊM ĐẦU TIÊN

### 1.1 Giảng đường, 16:40 (school · day)
Cutscene mở đầu (camera cố định ngôi thứ ba): toàn cảnh sân trường nắng nhạt, tiếng ve. Cắt vào lớp.
Nam ngồi bàn thứ ba cạnh cửa sổ. Thầy Khải giảng nốt.

- `ch1_thay_01` **thay_giao**: Tuần sau nộp bản vẽ khảo sát khu phố cũ. Nhóm nào chọn khu nào thì ghi tên lên bảng.
- `ch1_thay_02` **thay_giao**: Thôi, hôm nay đến đây. Về cẩn thận, dạo này trời sương nhiều.

Người chơi điều khiển. Linh quay xuống.

- `ch1_linh_01` **linh**: Nam, nhóm mình chọn khu ngõ nhà cậu nhé? Tớ thấy trên bản đồ cũ cuối ngõ có một cái miếu.
- `ch1_nam_01` **nam**: Miếu Ông Đèn ấy à? Bỏ hoang lâu rồi. Tớ chỉ thấy cái cột đèn đường to tướng bên cạnh.
- `ch1_linh_02` **linh**: Bà tớ bảo miếu kiểu đấy ngày xưa phải giữ đèn sáng cả đêm. Đèn tắt là xui lắm.
- `ch1_nam_02` **nam**: Thôi đừng dọa. Tối nay tớ bắt đầu trực ca đêm đấy.
- `ch1_linh_03` **linh**: Ca đêm ở cái cửa hàng đầu ngõ á? Ừ, thế cậu cẩn thận. Có gì nhắn tớ.

Nhiệm vụ: **Ra cổng trường.** Trên hành lang, Hùng nhắn tin (điện thoại rung).

- msg `m_ch1_hung_01` **hung** 16:45 (ch1): Tối nay tao đá bóng với hội lớp, về muộn. Mày đi làm nhớ mang chìa khóa nhé.
- msg `m_ch1_me_01` **me** 16:50 (ch1): Con ơi đi làm đêm nhớ ăn uống đầy đủ. Có gì gọi mẹ.

Ở cổng, bác Tư ngồi trong chốt bảo vệ.

- `ch1_tu_01` **bac_bao_ve**: Cháu Nam đấy à. Nghe bảo cháu làm ca đêm ở cái cửa hàng đầu ngõ Đèn?
- `ch1_nam_03` **nam**: Vâng, hôm nay ca đầu tiên bác ạ.
- `ch1_tu_02` **bac_bao_ve**: Ừ. Bác dặn câu này: về khuya, thấy ai đứng dưới đèn đường thì đừng nhìn lâu. Cứ đi thẳng.
- `ch1_tu_03` **bac_bao_ve**: Người ta đứng đấy là việc của người ta. Mình nhìn lâu là thành việc của mình.

Fade. Thẻ chữ: **"22:00 — Tiện Lợi 24h Ánh Dương"**.

### 1.2 Cửa hàng, 22:00 → 04:30 (store_alley · night_store)
Checkpoint `ch1_store`. Chị Hạnh giao ca.

- `ch1_hanh_01` **chi_quan_ly**: Em là Nam hả? Chị là Hạnh, quản lý. Ca đêm nhàn thôi, quét mã, xếp hàng, lau sàn.
- `ch1_hanh_02` **chi_quan_ly**: À, sau quầy có tờ quy tắc ca đêm. Đọc kỹ vào. Đừng hỏi chị sao lại có mấy cái quy tắc đấy.
- `ch1_hanh_03` **chi_quan_ly**: Thằng trước em nghỉ ngang không báo. Em đừng có như nó nhé. Chị về đây.

Vật thể đọc được: **tờ QUY TẮC CA ĐÊM** (dán sau quầy, nét chữ tay):
> 1. Sau 0 giờ, không ra khỏi cửa hàng vì bất cứ lý do gì.
> 2. Nếu có người đứng ngoài cửa kính mà không vào, đừng nhìn họ quá lâu. Cứ làm việc tiếp.
> 3. Đèn chớp tắt thì đừng ngẩng lên nhìn đèn.
> 4. Khách vào sau 2 giờ sáng: tính tiền bình thường, không hỏi han.
> 5. ~~Trước khi tan ca, mang dầu ra châm đèn miếu cuối ngõ.~~ *(gạch bằng bút đỏ)*

Nhiệm vụ (thứ tự tự do): **Tính tiền cho khách** (2 lượt) · **Xếp hàng lên kệ số 2** · **Lau sàn**.

Khách 1 (22:30, xe ôm mệt mỏi), quét 3 món:
- `ch1_khach_01` **khach**: Cho anh bao thuốc với chai nước. Ca đêm à em? Đêm ở đây buồn lắm.

Khách 2 (23:50), cô gái im lặng mua **7 lon cùng một loại**, không nói gì; lúc ra cô dừng ở cửa kính rất lâu
rồi mới đi. (Không thoại, chỉ tiếng chuông cửa.)

**00:30, Kẻ Đứng Nhìn xuất hiện**: một bóng người cao bất thường đứng ở vỉa hè đối diện, trong rìa sương,
mặc đồng phục cam như của Nam. Mỗi lần người chơi quay đi, nó gần thêm một chút (gazer · `outside_glass`).
Nếu nhìn lâu sẽ bị nhiễu, mất kiểm soát rồi giật mình bừng tỉnh (không chết ở Ch1, nhưng mất `ch1_no_stare`).
- `ch1_nam_04` **nam**: Ai đứng đấy giờ này nhỉ... Thôi, làm việc tiếp.

Đèn chớp tắt (hàng loạt), khi sáng lại nó đã đứng sát kính. Gõ kính 3 cái (`glass_tap`) rồi biến mất.
- `ch1_nam_05` **nam**: Không ngẩng lên. Không ngẩng lên...

**02:10, bà cụ** vào cửa hàng (khách sau 2 giờ: không hỏi han). Mua một bó nhang và một chai dầu lạc.
- `ch1_bacu_01` **ba_cu**: Cháu ở phòng hai linh bốn trong ngõ phải không?
- `ch1_bacu_02` **ba_cu**: Phòng ấy lâu rồi không ai trông đèn. Thằng trước cháu cũng hay mua dầu ở đây.
- `ch1_bacu_03` **ba_cu**: Đèn tắt thì phải có người đứng trông. Cháu nhớ lấy.

Lựa chọn (rule 4): **[Hỏi bà cụ]** / **[Im lặng tính tiền]**. Hỏi → bà quay đi, đèn chớp, bà đã biến mất,
tiền trên quầy là **tiền âm phủ** (không mất resolve, chỉ là cú hù). Im lặng → bà để lại một nén nhang trên quầy
(pickup `incense_single`, dùng ở 1.3).
- `ch1_nam_06` **nam**: Bà ơi, bà nói thế là sao ạ?

Đồng hồ trên điện thoại tua đến 04:30. Chị Hạnh nhắn:
- msg `m_ch1_hanh_01` **chi_quan_ly** 04:31 (ch1): Ca đầu ổn không em? 5h có bạn ca sáng tới. Về thì đi cửa sau cho gần.

### 1.3 Con ngõ, 05:00 (store_alley · alley pre-dawn)
Checkpoint `ch1_alley`. Đi cửa sau qua kho, ra ngõ. Sương dày, đèn tường chập chờn, dây điện chằng chịt.
Bàn thờ nhỏ trong hốc tường: nếu có nén nhang, interact → `match_strike`, thắp (+1 `ch1_incense_alley`).
Cuối ngõ, qua làn sương, thấy quầng đèn natri cam của cây đèn đường. Dưới đèn có bóng người đứng.
Khi tới gần thì đèn tắt phụt rồi bật lại, không còn ai.
- `ch1_nam_07` **nam**: Mình mệt quá rồi. Về ngủ thôi.

Đi tới cổng trọ, chuyển cảnh, lên phòng, nằm ngủ (go_to_sleep). Thẻ: **"Hết chương 1"**.

---

## CHƯƠNG 2: NGƯỜI GÕ CỬA

### 2.1 Cửa hàng, 17:00 (store_alley · day/dusk)
Checkpoint `ch2_store`. Ca chiều ngắn. Chị Hạnh:
- `ch2_hanh_01` **chi_quan_ly**: Hôm qua có gì lạ không em? ...Thôi, không có thì tốt.
- `ch2_hanh_02` **chi_quan_ly**: Vào kho dọn giúp chị cái ngăn kéo cũ, đồ của thằng Tuấn để lại ấy. Vứt được thì vứt.

Nhiệm vụ: **Xếp hàng** · **Dọn ngăn kéo trong kho**. Trong ngăn kéo: **thẻ nhân viên** "TRẦN VĂN TUẤN — CA ĐÊM", ảnh thẻ mờ.
Mặt trong ảnh **chính là người đứng ngoài kính** đêm qua.
- `ch2_nam_01` **nam**: Tuấn... Người này... đêm qua đứng ngoài kia.
- `ch2_hanh_03` **chi_quan_ly**: Tuấn hả? Nó ở ngay trong ngõ, dãy trọ của em đấy. Tự dưng nghỉ, gọi không nghe máy.

Linh ghé mua đồ:
- `ch2_linh_01` **linh**: Ơ Nam! Tớ đi ngang qua. Tối nay tớ qua trọ trả cậu quyển vở nhé, tầm mười một giờ.
- `ch2_nam_02` **nam**: Ừ, nhưng khuya thế có sao không?
- `ch2_linh_02` **linh**: Không sao, nhà tớ ngay phố bên mà. Thôi tớ đi đây.

Khách quét mã (1 lượt). Rồi tan ca, về qua ngõ lúc chạng vạng (không có thực thể, chỉ không khí).

- msg `m_ch2_hung_01` **hung** 18:20 (ch2): Mày ơi tao phải về quê gấp, bà tao ốm nặng. Chắc 3-4 hôm nữa mới lên. Tối khóa cửa cẩn thận nhé, chìa tao cầm theo rồi.

### 2.2 Phòng trọ P.204, 21:00 → 03:00 (dorm_shrine · night)
Checkpoint `ch2_dorm`. Dưới tầng trệt, bảng tin của chủ trọ (readable):
> THÔNG BÁO: Phòng 205 không cho thuê. Ai biết tin anh Tuấn (người thuê cũ P.204) báo chủ nhà giúp. Đồ đạc anh Tuấn để trên gác phòng 204, đề nghị không tự ý vứt.

Trên gác xép P.204 có một túi đồ cũ: áo đồng phục cam, một **tấm ảnh cũ** chụp miếu Ông Đèn khi còn sáng đèn,
có Tuấn và một bà cụ (chính là bà cụ ở cửa hàng). Interact → flag `seen_photo_room`.

Nhiệm vụ: **Nấu mì** · **Khóa cửa** · **Tắt đèn đi ngủ**.

- msg `m_ch2_linh_01` **linh** 22:05 (ch2): Nam ơi tớ xin lỗi, mẹ tớ không cho đi khuya. Mai tớ đưa vở trên lớp nhé. Đừng mở cửa cho ai đấy hihi.

**23:40, gõ cửa.** Ba tiếng gõ bình thường, rồi giọng "Hùng" (fx `door`):
- `ch2_mimic_hung_01` **hung** [door]: Nam ơi! Mở cửa, tao Hùng đây. Tao quên chìa khóa.
- `ch2_nam_03` **nam**: (Hùng? Nó bảo về quê cơ mà...)
- `ch2_mimic_hung_02` **hung** [door]: Nam. Tao biết mày ở trong đấy. Đèn còn sáng kìa.
- `ch2_mimic_hung_03` **hung** [door]: Mở cửa đi. Ngoài này lạnh lắm. Lạnh lắm Nam ạ.

Một tin nhắn mới từ "Hùng" hiện lên, sai giờ, sai chính tả:
- msg `m_ch2_fake_01` **hung** 23:41 (ch2): mo cua cho tao di. tao dung ngoai cua roi
Ngay sau đó là tin thật:
- msg `m_ch2_hung_02` **hung** 23:42 (ch2): Ơ tao đang ở viện với bà mà, ai nhắn từ máy tao thế?? Mày đừng mở cửa nhé Nam

Lựa chọn có giới hạn thời gian (Mimic hỏi): **[Trả lời]** / **[Im lặng]** → trả lời = phá cửa = chết.
- `ch2_mimic_hung_04` **hung** [door]: Sao mày không trả lời tao?
- `ch2_mimic_hung_05` **hung** [entity]: Mày... không... trả lời... tao...
Tay nắm cửa lạch cạch, tiếng gõ chậm và nặng dần, rồi bước chân đi xa. Mimic bỏ cuộc → `survived`.
Gợi ý cho người chơi: tắt đèn (+1).

**02:10, mất điện.** Quạt dừng, tối om. Phải xuống tầng trệt bật lại cầu dao.
- `ch2_nam_04` **nam**: Lại mất điện. Cầu dao ở dưới tầng trệt...
Checkpoint `ch2_breaker`. Hành lang tầng 2: "Linh" đứng ở cuối hành lang gần đầu cầu thang, quay lưng,
cổ nghiêng, tay buông quá gối, **không có bóng** dưới bóng đèn duy nhất. (mimic · `corridor`)
- `ch2_mimic_linh_01` **linh** [entity]: Nam ơi... tớ mang vở trả cậu này...
- `ch2_mimic_linh_02` **linh** [entity]: Sao cậu không nhìn tớ?
Phải đi qua (bám sát lan can), xuống cầu thang, bật cầu dao. Đèn bật, "Linh" biến mất. Quay về phòng, khóa cửa.
Trong nhà vệ sinh, gương phản chiếu Nam **chậm nửa nhịp** (scare nhẹ).
- `ch2_nam_05` **nam**: Mình cần biết chuyện gì đang xảy ra ở cái ngõ này.
Ngủ. Thẻ: **"Hết chương 2"**.

---

## CHƯƠNG 3: PHỐ KHÔNG NGƯỜI

### 3.1 Phòng trọ, 16:00 (dorm_shrine · day, ngắn)
Nam ngủ li bì tới chiều. Tin nhắn:
- msg `m_ch3_hanh_01` **chi_quan_ly** 15:10 (ch3): Tối nay cửa hàng đóng cửa sửa điện nhé em, nghỉ một hôm.
- msg `m_ch3_linh_01` **linh** 15:30 (ch3): Tớ hỏi bà rồi! Miếu Ông Đèn muốn thắp lại phải có dầu lạc, nhang, với ảnh của người trông đèn cũ. Và phải gọi đúng tên người ta. 22h tớ đợi cậu ở cổng trường, tớ đưa sổ ghi chép của bà.
- msg `m_ch3_hung_01` **hung** 15:45 (ch3): Bà tao đỡ rồi. Mày ổn không? Tối qua tao nằm mơ thấy mày đứng dưới cột đèn đầu ngõ, sợ vãi.
Lấy tấm ảnh trên gác (nếu chưa có) → `has_photo`. Fade sang đêm.

### 3.2 Phố & cổng trường, 22:00 (school · ch3_night, sương 6–10 m)
Checkpoint `ch3_street`. Con phố trước cổng trường **không một chiếc xe**. Những nhóm người đứng như tượng sáp:
chờ xe buýt ở trạm, hai cô quét rác giữa đường, ba người ngồi ở quán trà đá đã đóng. Tất cả bất động (crowd).
Lại gần 5 m: tất cả đầu cùng quay theo. Chạy/đánh rơi đồ/rọi đèn pin: chúng đuổi theo dáng chạy cứng đờ.
- `ch3_nam_01` **nam**: Đường gì mà vắng thế này... Họ đứng im như tượng.
- `ch3_nam_02` **nam**: Đi chậm thôi. Đừng chạy. Đừng để họ nghe thấy.

Nhiệm vụ: **Tìm Linh ở cổng trường**. Cổng không có Linh. Tin nhắn:
- msg `m_ch3_linh_02` **linh** 22:07 (ch3): Tớ đứng ở cổng rồi mà không thấy cậu đâu? Cổng vắng tanh, chỉ có cái đèn đường nhấp nháy...
- `ch3_nam_03` **nam**: Mình cũng đang đứng ở cổng mà...

Bác Tư vẫn ngồi trong chốt (có bóng đổ, thật). Checkpoint `ch3_gate`.
- `ch3_tu_01` **bac_bao_ve**: Nam đấy à? Đêm nay đừng ra đường. Cả phố đi vào sương hết rồi.
- `ch3_tu_02` **bac_bao_ve**: Cháu hỏi miếu Ông Đèn hả... Ngày bác còn trẻ, đêm nào bà Sáu cũng châm đèn. Bà mất, thằng Tuấn trọ trong ngõ nhận châm thay.
- `ch3_tu_03` **bac_bao_ve**: Rồi một đêm nó quên. Đèn tắt. Sáng ra người ta thấy nó đứng dưới cột đèn đường, mắt mở trừng trừng. Rồi nó biến mất.
- `ch3_tu_04` **bac_bao_ve**: Đèn tắt thì phải có người đứng trông. Lệ nó thế. Giờ nó đứng trông, nhưng nó cũng đang tìm người thay.
- `ch3_tu_05` **bac_bao_ve**: Đây, chai dầu lạc bác vẫn để dành. Nhang thì ở tạp hóa bà Sáu bên kia đường, cửa không khóa đâu.
(Bỏ đi giữa chừng → không có `ch3_bac_tu_story`. Nhận `has_oil`.)

Nhiệm vụ: **Lấy nhang ở tạp hóa** (bên kia đường, phải đi qua nhóm chờ xe buýt) · **(tùy chọn) Tìm thẻ tên của Tuấn**
(bảng "Tìm người mất tích" trong sân trường, giữa nhóm học sinh ngồi bất động) → `has_name_tag`.
- `ch3_nam_04` **nam**: Trần Văn Tuấn. Khóa trên mình hai năm... Mất tích từ tháng trước.
Khi có đủ dầu và nhang (ảnh đã có từ phòng), đám đông ở cổng **đồng loạt quay về phía con ngõ**, như nhường đường.
- `ch3_nam_05` **nam**: Họ đang nhìn về phía ngõ nhà mình.
Fade. Thẻ: **"Hết chương 3"**.

---

## CHƯƠNG 4: ĐÈN ĐƯỜNG CUỐI NGÕ

### 4.1 Con ngõ, 03:00 (store_alley · ch4_night, sương dread)
Checkpoint `ch4_alley`. Cửa hàng tối om, cửa kính phản chiếu Nam, nhưng trong phản chiếu **có ai đứng sau lưng**.
Đi vào ngõ. Kẻ Đứng Nhìn (Tuấn) ở chế độ `hunt`: mỗi khúc quanh nó đã đứng trước trong sương.
Không nhìn lâu, tiếp tục đi. Đèn tường lần lượt tắt sau lưng người chơi.
- `ch4_tuan_01` **???** [entity]: Ca đêm... dài lắm... đúng không...
- `ch4_tuan_02` **???** [entity]: Đến lượt... ai trông đèn...

### 4.2 Miếu Ông Đèn (dorm_shrine · ch4_night)
Checkpoint `ch4_shrine`. Hẻm cụt, gốc đa, miếu đổ nát. Cây đèn đường cao áp nhấp nháy màu cam.
Tuấn đứng ngay dưới đèn, cao lêu nghêu, nhìn Nam không chớp.

Nghi thức (interact tại bàn thờ, mỗi bước có hiệu ứng):
1. **Thắp nhang** vào bát hương (`match_strike`).
2. **Đặt ảnh** lên bàn thờ → +1 `ch4_offering` nếu đã thắp nhang.
3. **Châm dầu** vào đèn.
4. **Gọi tên người trông đèn**: lựa chọn `[Tuấn]` / `[Bà Sáu]` / `[Ông Đèn]` / `[Im lặng]` → đúng "Tuấn" +2 `ch4_called_name`
   (có thẻ tên hoặc đã nghe bác Tư thì biết; tên cũng có trên thẻ nhân viên ở Ch2).
5. **Thắp đèn** (`match_strike`).
- `ch4_nam_01` **nam**: Anh Tuấn. Em thắp lại đèn cho anh rồi. Anh về đi.

#### ENDING A: "Bình minh" (resolve ≥ 6)
Ngọn đèn dầu cháy đều. Cây đèn đường tắt phụt. Camera cố định góc thấp: Tuấn nhỏ dần lại về chiều cao người thường,
gương mặt giãn ra.
- `endA_tuan_01` **???** [far]: Cảm ơn em. Từ giờ... để đèn trông.
- `endA_tuan_02` **???** [far]: Nhớ châm dầu... mỗi sáng tan ca nhé.
Tuấn bước vào sương và tan đi. Sương rút, trời hửng (preset dawn). Nam đi bộ ra đầu ngõ; tiếng xe máy, tiếng rao.
Hùng dắt xe vào ngõ, có bóng đổ dưới nắng sớm.
- `endA_hung_01` **hung**: Ê! Mày làm gì ngoài này sớm thế? Mặt mày như người mất ngủ ba đêm.
- `endA_nam_01` **nam**: Ừ... ca đêm dài lắm. Mà xong rồi.
- `endA_hung_02` **hung**: Đi ăn phở không? Tao bao.
Toàn cảnh con ngõ buổi sáng, ngọn đèn dầu nhỏ vẫn cháy trong miếu. **ĐÈN ĐƯỜNG CUỐI NGÕ** · credits (`music_ending_a`).

#### ENDING B: "Ca trực vĩnh viễn" (resolve < 6 hoặc không thắp)
Ngọn đèn dầu chập chờn rồi tắt. Tuấn bước ngang qua Nam, rất chậm.
- `endB_tuan_01` **???** [entity]: Đèn tắt... thì phải có người đứng trông.
- `endB_tuan_02` **???** [entity]: Đến lượt em.
Nam không cử động được (khóa input, nhiễu tăng). Chuyển sang ngôi thứ ba: Nam bước đến đứng dưới cây đèn đường,
dáng dài ra, mắt không chớp. Thẻ chữ: **"Ba tháng sau"**.
Cửa hàng Tiện Lợi 24h Ánh Dương, 00:30. Một nhân viên ca đêm mới (nhìn từ trong ra) quét mã. Ngoài cửa kính,
trong rìa sương, có người mặc đồng phục cam đứng nhìn vào. Là Nam.
- `endB_new_01` **khach**: Ai đứng đấy giờ này nhỉ... Thôi, làm việc tiếp.
Cắt đen. credits (`music_ending_b`).

---

## Tin nhắn phụ (không khí)
- msg `m_ch1_spam_01` **radio** 19:02 (ch1): [QC] Gói cước ĐÊM VUI: lướt mạng không giới hạn từ 0h đến 6h chỉ 5.000đ!
- msg `m_ch2_me_01` **me** 20:15 (ch2): Mẹ gửi ít giò chả lên theo xe khách, mai con ra bến lấy nhé.
- msg `m_ch4_unknown_01` **???** 03:03 (ch4): đèn tắt rồi nam ơi

## Ghi chú hướng dẫn diễn xuất (TTS)
- Nam: giọng trẻ, mệt, nói nhỏ (Hải Đăng). Thoại trong ngoặc là độc thoại nội tâm (vẫn đọc).
- Hùng: xởi lởi, giọng Bắc. Bản Mimic dùng cùng voice, đi qua fx `door`/`entity`.
- Linh: nhanh nhảu (Mai Anh). Bác Tư: chậm, khàn (Phạm Tuyên). Bà cụ: thì thầm (Ngọc Huyền).
- `???` (Tuấn): dùng voice Nam (Hải Đăng) đẩy fx `entity` để gợi cảm giác "Nam tương lai".
