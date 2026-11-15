MOUTH SCRIPT - VOICE HELPER
===========================

Turns what you say on the mic into text in Garry's Mod
(at the bottom of your screen, and above your head for everyone else).

HOW TO USE
1. Double-click "START VOICE HELPER.bat".
   The first time, it installs what it needs and downloads the speech model
   (about 150 MB into the "models" folder). That takes a few minutes, once.
2. Leave the black window open and play Garry's Mod.
3. Hold your voice key (X by default) and talk.
4. Close the black window when you're done.

In game:  !listen_voice_off  turns voice-to-text off,  !listen_voice_on  turns it back on.

SETTINGS (config.json, made the first time it runs)
- "model": "base.en" is the default. If the words lag a lot, use "tiny.en" (faster, more mistakes).
            If your PC is fast, "small.en" is more accurate.
- "shout_sensitivity": how much louder than normal counts as shouting (adds ! ). Higher = harder to trigger.
- "shout_minimum_volume": shouting has to be at least this loud.
- "partial_every_seconds": how often the words update while you talk.
- "mic_device": leave as null to use your Windows default mic. To pick another one,
                put its number or name here (run:  py -m sounddevice  to see the list).
- "gmod_data_folder": only needed if the helper can't find Garry's Mod by itself.

NEEDS
Python 3.10 or newer (python.org, tick "Add Python to PATH" when installing).
Internet only for the first setup.
