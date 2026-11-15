# Mouth Script (Garry's Mod)

Makes your playermodel's **Mouth** bodygroup move when you talk, types your chat out at the bottom of the screen, and (optionally) turns your mic speech into text above your head.

Also on the Steam Workshop: [search "Mouth Script" in the Garry's Mod Workshop](https://steamcommunity.com/workshop/browse/?appid=4000&searchtext=Mouth+Script)

## Install (drag and drop)

1. Click the green **Code** button at the top of this page, then **Download ZIP**.
2. Open the ZIP.
3. Drag the **`mouth_script`** folder into your Garry's Mod **addons** folder:
   `C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons`
   (In Steam: right-click Garry's Mod → Manage → Browse local files → garrysmod → addons.)
4. Start Garry's Mod. Done.

(If you subscribed on the Workshop you don't need this folder too. Use one or the other.)

## Voice-to-text (optional)

1. Install [Python 3.10 or newer](https://www.python.org/downloads/) and tick **"Add Python to PATH"**.
2. Drag the **`Mouth Script Voice Helper`** folder anywhere you like (for example your Desktop).
3. Double-click **`START VOICE HELPER.bat`**. The first time it installs what it needs and downloads the speech model (about 150 MB).
4. When it says **Ready!**, leave the window open, hold your voice key in game and talk.

It runs offline on your own PC. Nothing you say is sent anywhere or saved.

## Punctuation

| Type | What happens |
|---|---|
| `.` | Ends the sentence. 1.5 s later the next one pops up. |
| `..` or `...` | A pause. Each dot appears on its own, 1.5 s apart. |
| `?` | That sentence types slower. |
| `!` | The word with the `!` goes bold. |
| `?!` or `!?` | Panic: that word goes bold and shakes. |
| `(text!)` | The whole bracket is shouted: BOLD CAPITALS. |
| `(text?)` | The whole bracket types slower. |
| `(text?!)` | The whole bracket is shouted and panicked. |

## Commands

Type them in chat with a `!` in front, or in the console without it.

| Command | What it does |
|---|---|
| `talk_on` / `talk_off` | Chat text at the bottom of the screen (on by default) |
| `global_chat_on` / `global_chat_off` | Everyone sees your chat at the bottom of their screen (off by default) |
| `listen_voice_on` / `listen_voice_off` | Voice-to-text (on by default, needs the voice helper) |
| `listen_self_on` / `listen_self_off` | See your own speech above your head in first person |
| `talk_mic_on` / `talk_mic_off` | Beeps and a [Speaking...] box while using the mic |
| `talk_list 1 2 3` | Mouth shapes (bodygroup numbers) to pick from at random |
| `talk_list_order 1 2 3` | Mouth shapes to step through in order |
| `line_save` / `line_load` | Save / load your mouth list for the playermodel you're using |
| `talk_AI_on` / `talk_AI_off` | Lets the Casualties: Unknown self-talk addon say its own lines again |

## Works with

[Casualties: Unknown'esque Player Self-Talk](https://steamcommunity.com/sharedfiles/filedetails/?id=3732869563) by doggowisdom. If you have it, your text uses its font, colour and typing sound. Not required.
