# Mouth Script voice helper
#
# Listens to your mic while Garry's Mod says you're using voice chat,
# turns your speech into text with Whisper (offline, on your own PC),
# and hands the text back to the game through small files in
# garrysmod/data/mouth_script/.
#
# Shouting adds "!" (bold word), shouting a question adds "?!" (panic).
#
# Start it with "START VOICE HELPER.bat". Settings are in config.json
# (made the first time it runs).

import json
import os
import queue
import statistics
import sys
import time
import traceback
from collections import deque

HERE = os.path.dirname(os.path.abspath(sys.argv[0]))
CONFIG_PATH = os.path.join(HERE, "config.json")
MODELS_DIR = os.path.join(HERE, "models")
LOG_PATH = os.path.join(HERE, "helper_log.txt")

SAMPLE_RATE = 16000
BLOCK_SECONDS = 0.1
PREROLL_BLOCKS = 6          # keep 0.6s from before you pressed the key
RELEASE_WAIT = 0.35         # keep listening this long after you let go
MAX_UTTERANCE_SECONDS = 28  # Whisper works on up to 30 seconds at once

DEFAULT_CONFIG = {
    "model": "base.en",
    "language": "en",
    "partial_every_seconds": 0.8,
    "shout_sensitivity": 1.8,
    "shout_minimum_volume": 0.06,
    "quiet_limit": 0.004,
    "mic_device": None,
    "cpu_threads": 0,
    "gmod_data_folder": ""
}

# Things Whisper likes to "hear" in silence
HALLUCINATIONS = {
    "you", "thank you", "thank you.", "thanks for watching", "thanks for watching!",
    "thank you for watching", "thank you for watching.", "bye", "bye.", ".", "..."
}


def log(message, to_file=True):
    # What people say is only shown in this window, never saved to the log file.
    line = "[Mouth Script] " + message
    try:
        print(line, flush=True)
    except Exception:
        pass
    if not to_file:
        return
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(time.strftime("%H:%M:%S ") + line + "\n")
    except Exception:
        pass


def disable_quick_edit():
    # Clicking inside a Windows console window normally FREEZES the program
    # until you press a key ("QuickEdit"). Turn that off for this window.
    if os.name != "nt":
        return
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-10)
        mode = ctypes.c_uint32()
        if kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            mode.value &= ~0x0040  # quick edit off
            mode.value |= 0x0080   # extended flags
            kernel32.SetConsoleMode(handle, mode)
    except Exception:
        pass


def load_config():
    config = dict(DEFAULT_CONFIG)
    if os.path.isfile(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                config.update(json.load(f))
        except Exception as error:
            log("config.json couldn't be read (" + str(error) + "), using defaults.")
    else:
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(DEFAULT_CONFIG, f, indent=4)
    return config


def find_data_folder(config):
    custom = config.get("gmod_data_folder") or ""
    if custom and os.path.isdir(custom):
        return custom

    # voice_helper -> mouth_script -> addons -> garrysmod
    guess = os.path.normpath(os.path.join(HERE, "..", "..", "..", "data"))
    if os.path.isdir(guess):
        return guess

    # look through every Steam library on this PC
    for library in steam_libraries():
        data = os.path.join(library, "steamapps", "common", "GarrysMod", "garrysmod", "data")
        if os.path.isdir(data):
            return data

    return None


def steam_libraries():
    roots = []
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as key:
            path, _kind = winreg.QueryValueEx(key, "SteamPath")
            roots.append(os.path.normpath(path))
    except Exception:
        pass
    roots.append(r"C:\Program Files (x86)\Steam")
    roots.append(r"C:\Program Files\Steam")

    libraries = []
    for root in roots:
        if root not in libraries:
            libraries.append(root)
        vdf = os.path.join(root, "steamapps", "libraryfolders.vdf")
        try:
            with open(vdf, "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.strip().split('"')
                    if len(parts) >= 4 and parts[1] == "path":
                        library = os.path.normpath(parts[3].replace("\\\\", "\\"))
                        if library not in libraries:
                            libraries.append(library)
        except OSError:
            pass
    return libraries


class GameBridge:
    def setup(self, data_folder):
        self.folder = os.path.join(data_folder, "mouth_script")
        os.makedirs(self.folder, exist_ok=True)
        self.state_path = os.path.join(self.folder, "voice_state.txt")
        self.out_path = os.path.join(self.folder, "voice_out.txt")
        self.alive_path = os.path.join(self.folder, "helper_alive.txt")
        self.next_alive = 0
        return self

    def read_state(self):
        try:
            with open(self.state_path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except OSError:
            return "0"

    def write_file(self, path, text):
        temp = path + ".tmp"
        with open(temp, "w", encoding="utf-8") as f:
            f.write(text)
        for _ in range(20):
            try:
                os.replace(temp, path)
                return
            except PermissionError:
                time.sleep(0.01)  # the game is reading it right now

    def write_text(self, utterance_id, seq, final, text):
        data = {"id": utterance_id, "seq": seq, "final": final, "text": text, "t": int(time.time())}
        self.write_file(self.out_path, json.dumps(data))

    def heartbeat(self):
        now = time.time()
        if now >= self.next_alive:
            self.write_file(self.alive_path, str(int(now)))
            self.next_alive = now + 2


class Listener:
    def setup(self, config, bridge, model):
        import numpy as np
        self.np = np
        self.config = config
        self.bridge = bridge
        self.model = model
        self.audio_queue = queue.Queue()
        self.preroll = deque(maxlen=PREROLL_BLOCKS)
        self.loudness_history = deque(maxlen=40)
        self.reset()
        return self

    def reset(self):
        self.active = False
        self.blocks = []
        self.utterance_id = 0
        self.seq = 0
        self.last_partial = 0
        self.last_text = ""
        self.released_at = None

    def on_audio(self, indata, frames, time_info, status):
        self.audio_queue.put(indata[:, 0].copy())

    def drain(self):
        new_blocks = []
        while True:
            try:
                new_blocks.append(self.audio_queue.get_nowait())
            except queue.Empty:
                return new_blocks

    def audio(self):
        if not self.blocks:
            return self.np.zeros(0, dtype=self.np.float32)
        return self.np.concatenate(self.blocks)

    def loudness(self, samples):
        if len(samples) == 0:
            return 0.0
        return float(self.np.sqrt(self.np.mean(samples * samples)))

    def is_shout(self, volume):
        minimum = float(self.config["shout_minimum_volume"])
        if len(self.loudness_history) >= 3:
            normal = statistics.median(self.loudness_history)
            return volume >= max(minimum, normal * float(self.config["shout_sensitivity"]))
        return volume >= minimum * 2

    def add_shouting(self, text, shout):
        text = text.strip()
        if not shout or not text:
            return text
        if text.endswith("?!") or text.endswith("!?"):
            return text
        if text.endswith("?"):
            return text + "!"
        if text.endswith("..."):
            return text
        if text[-1] in ".!":
            return text[:-1] + "!"
        return text + "!"

    def transcribe(self, samples, final):
        segments, _info = self.model.transcribe(
            samples,
            language=self.config.get("language") or None,
            beam_size=3 if final else 1,
            vad_filter=True,
            condition_on_previous_text=False
        )

        parts = []
        for segment in segments:
            text = segment.text.strip()
            if not text:
                continue
            start = max(0, int(segment.start * SAMPLE_RATE))
            end = min(len(samples), int(segment.end * SAMPLE_RATE))
            volume = self.loudness(samples[start:end])
            parts.append(self.add_shouting(text, self.is_shout(volume)))
            if final and volume > 0:
                self.loudness_history.append(volume)

        text = " ".join(parts).strip()
        while "  " in text:
            text = text.replace("  ", " ")
        return text[:300]

    def looks_fake(self, text, samples):
        if not text:
            return True
        if self.loudness(samples) < float(self.config["quiet_limit"]):
            return True
        seconds = len(samples) / SAMPLE_RATE
        return seconds < 3 and text.lower().strip() in HALLUCINATIONS

    def start(self):
        log("Listening...", to_file=False)
        self.active = True
        self.blocks = list(self.preroll)
        self.preroll.clear()
        self.utterance_id = int(time.time() * 1000)
        self.seq = 0
        self.last_partial = time.time()
        self.last_text = ""
        self.released_at = None

    def send(self, text, final):
        self.seq += 1
        self.bridge.write_text(self.utterance_id, self.seq, final, text)

    def finish(self):
        samples = self.audio()
        text = ""
        if len(samples) >= SAMPLE_RATE * 0.3:
            try:
                text = self.transcribe(samples, final=True)
            except Exception as error:
                log("Couldn't turn that into text: " + str(error))
        if self.looks_fake(text, samples):
            text = ""
        if text or self.last_text:
            self.send(text, True)
        if text:
            log("Said: " + text, to_file=False)
        else:
            log("(didn't catch any words)", to_file=False)
        self.reset()

    def partial(self):
        samples = self.audio()
        self.last_partial = time.time()
        if len(samples) < SAMPLE_RATE * 0.6:
            return
        try:
            text = self.transcribe(samples, final=False)
        except Exception as error:
            log("Couldn't turn that into text: " + str(error))
            return
        if self.looks_fake(text, samples):
            return
        if text != self.last_text:
            self.last_text = text
            self.send(text, False)

    def run(self):
        import sounddevice as sd

        device = self.config.get("mic_device")
        stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype="float32",
            blocksize=int(SAMPLE_RATE * BLOCK_SECONDS),
            device=device,
            callback=self.on_audio
        )

        every = float(self.config["partial_every_seconds"])
        log("Ready! Hold your voice key in Garry's Mod and talk. Close this window to stop.")

        with stream:
            while True:
                try:
                    self.step(every)
                except Exception:
                    log("Error (kept running):\n" + traceback.format_exc())
                    self.reset()
                    time.sleep(0.5)

    def step(self, every):
        self.bridge.heartbeat()
        new_blocks = self.drain()
        state = self.bridge.read_state()
        speaking = state == "1"
        now = time.time()

        if not self.active:
            self.preroll.extend(new_blocks)
            if speaking:
                self.start()
            else:
                time.sleep(0.05 if state != "off" else 0.25)
            return

        self.blocks.extend(new_blocks)
        seconds = sum(len(b) for b in self.blocks) / SAMPLE_RATE

        if speaking:
            self.released_at = None
        elif self.released_at is None:
            self.released_at = now

        if self.released_at is not None and now - self.released_at >= RELEASE_WAIT:
            self.finish()
        elif seconds >= MAX_UTTERANCE_SECONDS:
            self.finish()
            if speaking:
                self.start()
        elif speaking and now - self.last_partial >= every:
            self.partial()
        else:
            time.sleep(0.03)


def main():
    os.chdir(HERE)
    disable_quick_edit()
    log("Mouth Script voice helper")
    config = load_config()

    data_folder = find_data_folder(config)
    if not data_folder:
        log("Couldn't find Garry's Mod's data folder.")
        log("Open config.json and put the folder in \"gmod_data_folder\", for example:")
        log(r"C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\data")
        input("Press Enter to close.")
        return
    log("Talking to Garry's Mod through: " + data_folder)
    bridge = GameBridge().setup(data_folder)

    try:
        from faster_whisper import WhisperModel
    except ImportError:
        log("faster-whisper isn't installed. Run \"START VOICE HELPER.bat\" instead of this file.")
        input("Press Enter to close.")
        return

    model_name = config.get("model") or "base.en"
    log("Loading the speech model (" + model_name + ")... the first time it downloads it, so this can take a few minutes.")
    os.makedirs(MODELS_DIR, exist_ok=True)
    model = WhisperModel(
        model_name,
        device="cpu",
        compute_type="int8",
        cpu_threads=int(config.get("cpu_threads") or 0),
        download_root=MODELS_DIR
    )

    listener = Listener().setup(config, bridge, model)
    try:
        listener.run()
    except KeyboardInterrupt:
        pass
    except Exception as error:
        log("Something went wrong: " + str(error) + "\n" + traceback.format_exc())
        log("If it's about the microphone, set \"mic_device\" in config.json (see README.txt).")
        input("Press Enter to close.")


main()
