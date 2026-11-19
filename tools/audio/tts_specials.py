#!/usr/bin/env python3
"""TTS source takes for non-dialogue audio (rao_dem vendor calls, entity whisper material).
Writes tools/audio/src/tts_<name>.ogg (22050 Hz mono, high quality) that synth.py consumes, so the
synth step does not need the VieNeu venv. Re-run only to re-roll the takes:

    ~/Workspace/tools/VieNeu-TTS/.venv/bin/python -I tools/audio/tts_specials.py [--force]
"""
import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fx_chain as fxc  # noqa: E402
from tts_build import load_vieneu  # noqa: E402

SRC = HERE / "src"
TAKES = {
    # night vendor (rao đêm): two voices, two phrasings each
    "rao_tuyen_1": ("Phạm Tuyên", "Bánh mì nóng giòn đây... ai bánh mì nóng giòn đây..."),
    "rao_tuyen_2": ("Phạm Tuyên", "Bánh mì nóng... bánh mì đây..."),
    "rao_vinh_1": ("Xuân Vĩnh", "Bánh mì nóng giòn đây... ai bánh mì nóng giòn đây..."),
    "rao_vinh_2": ("Xuân Vĩnh", "Ai bánh mì nóng giòn... bánh mì đây..."),
    # whisper material (turned into breath-noise + reversed + pitched in synth.py)
    "wh_1": ("Hải Đăng", "Trông đèn... trông đèn... đến lượt ai trông đèn..."),
    "wh_2": ("Ngọc Huyền", "Đừng nhìn lâu... đừng nhìn... nó đang nhìn lại..."),
    "wh_3": ("Mai Anh", "Nam ơi... mở cửa... ngoài này lạnh lắm..."),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    SRC.mkdir(exist_ok=True)
    todo = {k: v for k, v in TAKES.items() if a.force or not (SRC / f"tts_{k}.ogg").exists()}
    if not todo:
        print("all takes present")
        return
    tts = load_vieneu()
    for k, (voice, text) in todo.items():
        audio = tts.infer(text, voice=voice)
        y = fxc.resample(audio.astype("float32"), 48000, 22050)
        y = fxc.trim_silence(y, 22050)
        y = fxc.peak_normalize(y, -1.0)
        fxc.save_ogg(y, 22050, SRC / f"tts_{k}.ogg", q=6)
        print(k, voice, f"{len(y) / 22050:.2f}s")


if __name__ == "__main__":
    main()
