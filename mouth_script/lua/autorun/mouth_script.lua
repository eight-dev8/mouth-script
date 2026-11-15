--[[
    Mouth Script
    Moves the playermodel's "Mouth" bodygroup when you talk on the mic or type in chat,
    types your chat out at the bottom of the screen, and (with the voice helper running)
    turns your mic speech into text above your head.

    If the Workshop addon "Casualties: Unknown'esque Player Self-Talk" (doggowisdom) is installed,
    the text copies its look (font, size, colour, typing sound). The addon itself starts DORMANT.

    Punctuation:
      .            ends the sentence, waits 1.5s, then the next sentence pops up
      .. ...       each dot appears one at a time, 1.5s apart; the mouth rests meanwhile
      ?            ends the sentence, that sentence types slower
      !            ends the sentence, the word with the ! goes bold
      ?! or !?     ends the sentence, that word goes bold and shakes, typing speed wobbles (panic)
      (text!)      the whole bracket is shouted: BOLD CAPS, slightly faster
      (text?)      the whole bracket is slower
      (text?!)     the whole bracket is shouted and panicked

    Commands (chat with ! or console without):
      talk_on / talk_off                - chat text at the bottom of the screen (default ON)
      talk_mic_on / talk_mic_off        - mic beeps + [Speaking...] box (default OFF, talk_mute also turns it off)
      talk_AI_on / talk_AI_off          - the self-talk addon's own lines (default OFF)
      listen_voice_on / listen_voice_off - mic speech turned into text (default ON, needs the voice helper)
      global_chat_on / global_chat_off  - everyone sees your chat at the bottom of their screen (default OFF)
      listen_self_on / listen_self_off  - see your own speech above your head even in first person (for testing
                                          with a camera; in third person it always shows)
      talk_list <numbers>               - mouth notches to pick from randomly
      talk_list_order <numbers>         - mouth notches to step through left to right
      line_save / line_load             - save / load your list for the playermodel you're using now
]]

-- Mouth message types (client -> server)
local MOUTH_STOP = 0 -- back to resting notch and forget (talk_list_order restarts from the first notch)
local MOUTH_TALK = 1 -- next talking notch
local MOUTH_REST = 2 -- back to resting notch for a moment (between words), keep the order going

local NET_MOUTH = "BodygroupVoiceSyncCommand"
local NET_GLOBAL = "MouthScriptGlobalChat"
local NET_SPEECH = "MouthScriptSpeech"
local MAX_TEXT = 300

if SERVER then
    util.AddNetworkString(NET_MOUTH)
    util.AddNetworkString(NET_GLOBAL)
    util.AddNetworkString(NET_SPEECH)

    local playerTalkData = {}
    local nextGlobalAllowed = {}
    local nextSpeechAllowed = {}

    -- Puts the mouth back to its resting notch (only if the model hasn't changed)
    local function RestoreMouth(ply, data)
        if not IsValid(ply) or not data or ply:GetModel() ~= data.model then return end

        local mouthBG = ply:FindBodygroupByName("Mouth")
        if mouthBG and mouthBG ~= -1 then
            ply:SetBodygroup(mouthBG, data.original)
        end
    end

    local function ResetTalkData(ply, restore)
        local data = playerTalkData[ply]
        if not data then return end

        if restore then
            RestoreMouth(ply, data)
        end

        playerTalkData[ply] = nil
    end

    -- Clean up on death, respawn and disconnect so the mouth never gets stuck
    hook.Add("PlayerDeath", "BodygroupTalkCleanupDeath", function(ply)
        ResetTalkData(ply, true)
    end)

    hook.Add("PlayerSpawn", "BodygroupTalkCleanupSpawn", function(ply)
        ResetTalkData(ply, false)
    end)

    hook.Add("PlayerDisconnected", "BodygroupTalkCleanupDisconnect", function(ply)
        playerTalkData[ply] = nil
        nextGlobalAllowed[ply] = nil
        nextSpeechAllowed[ply] = nil
    end)

    -- Hide !commands from everyone's chat, then run them on the sender's client
    local chatCommands = {
        ["!talk_on"] = "talk_on",
        ["!talk_off"] = "talk_off",
        ["!talk_mic_on"] = "talk_mic_on",
        ["!talk_mic_off"] = "talk_mic_off",
        ["!talk_mute"] = "talk_mute",
        ["!talk_ai_on"] = "talk_AI_on",
        ["!talk_ai_off"] = "talk_AI_off",
        ["!listen_voice_on"] = "listen_voice_on",
        ["!listen_voice_off"] = "listen_voice_off",
        ["!global_chat_on"] = "global_chat_on",
        ["!global_chat_off"] = "global_chat_off",
        ["!listen_self_on"] = "listen_self_on",
        ["!listen_self_off"] = "listen_self_off",
        ["!talk_list"] = "talk_list",
        ["!talk_list_order"] = "talk_list_order",
        ["!line_save"] = "line_save",
        ["!line_load"] = "line_load"
    }

    hook.Add("PlayerSay", "BodygroupTalkHideCommands", function(ply, text)
        local args = string.Explode(" ", string.Trim(text))
        local cmd = string.lower(args[1] or "")
        local conCmd = chatCommands[cmd]
        if not conCmd then return end

        -- Only pass whole numbers through, so nothing else can sneak into the console command
        local numbers = {}
        for i = 2, #args do
            local num = tonumber(args[i])
            if num then
                table.insert(numbers, tostring(math.floor(num)))
            end
        end

        local full = conCmd
        if #numbers > 0 then
            full = full .. " " .. table.concat(numbers, " ")
        end

        ply:ConCommand(full)
        return ""
    end)

    -- Global chat: pass the message on to everyone
    net.Receive(NET_GLOBAL, function(len, ply)
        if not IsValid(ply) then return end

        local now = CurTime()
        if (nextGlobalAllowed[ply] or 0) > now then return end
        nextGlobalAllowed[ply] = now + 0.5

        local text = string.sub(net.ReadString(), 1, MAX_TEXT)
        if string.Trim(text) == "" then return end

        net.Start(NET_GLOBAL)
        net.WriteEntity(ply)
        net.WriteString(text)
        net.Broadcast()
    end)

    -- Speech text: pass it on so others can show it above the speaker's head
    net.Receive(NET_SPEECH, function(len, ply)
        if not IsValid(ply) then return end

        local id = net.ReadUInt(32)
        local final = net.ReadBool()
        local text = string.sub(net.ReadString(), 1, MAX_TEXT)

        local now = CurTime()
        if not final then
            if (nextSpeechAllowed[ply] or 0) > now then return end
            nextSpeechAllowed[ply] = now + 0.15
        end

        net.Start(NET_SPEECH)
        net.WriteEntity(ply)
        net.WriteUInt(id, 32)
        net.WriteBool(final)
        net.WriteString(text)
        net.SendOmit(ply)
    end)

    net.Receive(NET_MOUTH, function(len, ply)
        if not IsValid(ply) then return end

        local mode = net.ReadUInt(2)
        local commandList = net.ReadTable()
        local isOrdered = net.ReadBool()

        -- A stop message is always accepted, even from a dead player
        if mode == MOUTH_STOP then
            ResetTalkData(ply, true)
            return
        end

        if mode == MOUTH_REST then
            RestoreMouth(ply, playerTalkData[ply])
            return
        end

        if not ply:Alive() then return end

        local mouthBG = ply:FindBodygroupByName("Mouth")
        if not mouthBG or mouthBG == -1 then
            ResetTalkData(ply, false)
            return
        end

        -- If the playermodel changed mid-talk, start fresh with the new model's resting notch
        if playerTalkData[ply] and playerTalkData[ply].model ~= ply:GetModel() then
            playerTalkData[ply] = nil
        end

        if not playerTalkData[ply] then
            playerTalkData[ply] = {
                original = ply:GetBodygroup(mouthBG),
                model = ply:GetModel(),
                list = {},
                ordered = false,
                stepIndex = 1,
                lastChoice = nil
            }
        end

        local data = playerTalkData[ply]
        data.ordered = isOrdered

        local maxNotches = ply:GetBodygroupCount(mouthBG) - 1

        if commandList and #commandList > 0 then
            local validList = {}
            for _, notch in ipairs(commandList) do
                if isnumber(notch) and notch >= 0 and notch <= maxNotches then
                    table.insert(validList, notch)
                end
            end
            if #validList > 0 then
                data.list = validList
            end
        end

        local activeList = data.list
        if #activeList == 0 then
            activeList = {}
            for _, notch in ipairs({2, 4}) do
                if notch <= maxNotches then
                    table.insert(activeList, notch)
                end
            end
            if #activeList == 0 then return end
        end

        local choice
        if data.ordered then
            local idx = data.stepIndex
            if idx > #activeList or idx < 1 then
                idx = 1
            end
            choice = activeList[idx]
            data.stepIndex = (idx % #activeList) + 1
        else
            choice = activeList[math.random(#activeList)]
            if #activeList > 1 and choice == data.lastChoice then
                for _, candidate in ipairs(activeList) do
                    if candidate ~= data.lastChoice then
                        choice = candidate
                        break
                    end
                end
            end
        end

        data.lastChoice = choice
        ply:SetBodygroup(mouthBG, choice)
    end)
end

if CLIENT then
    ---------------------------------------------------------------------------
    -- Settings you can tweak
    ---------------------------------------------------------------------------
    local LETTER_TIME = 0.05        -- seconds per letter (the self-talk addon's speed: 20 letters a second)
    local QUESTION_SLOW = 1.6       -- ? sentences: each letter takes this many times longer
    local SHOUT_FAST = 0.85         -- (shouted!) brackets: each letter takes this many times as long (smaller = faster)
    local PANIC_MIN = 0.75          -- ?! panic: letter speed wobbles randomly between these two
    local PANIC_MAX = 1.3
    local SHAKE_PIXELS = 1.6        -- ?! panic: how far the letters jitter
    local DOT_PAUSE = 1.5           -- seconds each dot waits
    local MAX_DOTS = 10             -- longest pause counts this many dots at most
    local LINGER_TIME = 3           -- seconds the last chat sentence stays on screen
    local CHAT_FADE_TIME = 0.4      -- seconds a chat line takes to fade out
    local SHOUT_CAPS = true         -- (shouted!) brackets turn into CAPITALS
    local BOLD_SIZE = 1.1           -- bold words are this much bigger
    local LETTERS_PER_MOUTH = 3     -- mouth changes shape every this many letters
    local MIN_MOUTH_GAP = 0.07      -- never send mouth changes faster than this
    local MAX_BOTTOM_LINES = 3      -- how many lines can stack at the bottom of the screen

    local SPEECH_LETTER_TIME = 0.025 -- speech text types out this fast as the words come in
    local SPEECH_LINGER = 3          -- seconds finished speech stays up
    local SPEECH_FADE = 1.5          -- seconds finished speech takes to fade away
    local SPEECH_TIMEOUT = 10        -- give up on speech that stops updating for this long
    local HEAD_TEXT_DISTANCE = 1200  -- speech above heads is visible up to this far
    local HEAD_TEXT_SCALE = 0.8      -- speech above heads is this much smaller

    local MOUTH_SWAP_DELAY = 0.22   -- mic / addon lines: mouth changes every this many seconds
    local BEEP_SOUND = "ui/buttonclickrelease.wav"
    local BEEP_INTERVAL = 0.11

    local DEFAULT_FONT_FAMILY = "Arial"
    local DEFAULT_FONT_SIZE = 28
    local DEFAULT_FONT_WEIGHT = 800
    local DEFAULT_TEXT_COLOR = Color(251, 218, 114)
    local DEFAULT_TALK_SOUND = "buttons/blip1.wav"
    local TEXT_COLOR_PRESETS = {
        Default = Color(251, 218, 114),
        Milky = Color(144, 210, 255),
        Experiment = Color(255, 196, 142)
    }

    local SCREEN_FONTS = { normal = "MouthScript_Normal", bold = "MouthScript_Bold" }
    local HEAD_FONTS = { normal = "MouthScript_HeadNormal", bold = "MouthScript_HeadBold" }
    local FONT_NAME = "MouthScript_Name"

    -- Files shared with the voice helper (garrysmod/data/mouth_script/)
    local DATA_DIR = "mouth_script"
    local VOICE_STATE_FILE = DATA_DIR .. "/voice_state.txt"
    local VOICE_OUT_FILE = DATA_DIR .. "/voice_out.txt"
    local HELPER_ALIVE_FILE = DATA_DIR .. "/helper_alive.txt"

    file.CreateDir(DATA_DIR)

    ---------------------------------------------------------------------------
    -- State
    ---------------------------------------------------------------------------
    local currentCustomList = {}
    local isOrderedMode = false
    local chatBoxEnabled = true      -- talk_on / talk_off
    local micVoiceBoxEnabled = false -- talk_mic_on / talk_mic_off
    local aiEnabled = false          -- talk_AI_on / talk_AI_off
    local listenVoiceEnabled = true  -- listen_voice_on / listen_voice_off
    local globalChatEnabled = false  -- global_chat_on / global_chat_off
    local listenSelfEnabled = false  -- listen_self_on / listen_self_off

    local wasTalking = false
    local nextMouthSwap = 0
    local nextMicBeep = 0
    local isMicSpeakingNow = false
    local micDotsCount = 1

    local BottomLines = {}  -- lines stacked at the bottom of the screen (oldest first)
    local HeadLines = {}    -- [player] = speech line shown above their head
    local OwnChat = nil     -- your chat line (it moves your mouth)
    local OwnSpeech = nil   -- your speech line (shown at the bottom for you)

    local mouthOpen = false
    local lettersSinceSwap = 0
    local lastMouthSend = 0
    local nextLetterSound = 0
    local precachedSounds = {}

    local lastVoiceState = nil
    local lastHelperRaw = nil
    local lastHelperId = nil
    local speechCounter = 0

    ---------------------------------------------------------------------------
    -- Small helpers
    ---------------------------------------------------------------------------
    local function CvarString(name, default)
        local cv = GetConVar(name)
        if cv then return cv:GetString() end
        return default
    end

    local function CvarFloat(name, default)
        local cv = GetConVar(name)
        if cv then return cv:GetFloat() end
        return default
    end

    local function IsEndMark(c)
        return c == "." or c == "?" or c == "!"
    end

    local function IsDigit(c)
        return c ~= nil and string.match(c, "^%d$") ~= nil
    end

    local function SendMouth(mode)
        net.Start(NET_MOUTH)
        net.WriteUInt(mode, 2)
        net.WriteTable(currentCustomList)
        net.WriteBool(isOrderedMode)
        net.SendToServer()
        lastMouthSend = CurTime()
    end

    local function MouthStop()
        SendMouth(MOUTH_STOP)
        mouthOpen = false
        lettersSinceSwap = 0
    end

    local function OwnChatBusy()
        return OwnChat ~= nil and not OwnChat.done and OwnChat.state ~= "linger"
    end

    ---------------------------------------------------------------------------
    -- Self-talk addon bridge
    -- The addon keeps everything private. We reach it through its own HUDPaint
    -- hook ("PST_HUD"): its state table, its text colour and its typing sound.
    ---------------------------------------------------------------------------
    local SelfTalk = nil

    local function FindSelfTalk()
        if SelfTalk then return SelfTalk end
        if not debug or not debug.getupvalue then return nil end

        local hudHooks = hook.GetTable().HUDPaint
        local drawFunc = hudHooks and hudHooks["PST_HUD"]
        if not isfunction(drawFunc) then return nil end

        local found = {}
        for i = 1, 255 do
            local name, value = debug.getupvalue(drawFunc, i)
            if name == nil then break end
            if name == "PST" and istable(value) then found.pst = value end
            if name == "GetSelfTalkTextColor" and isfunction(value) then found.getColor = value end
            if name == "GetTalkSound" and isfunction(value) then found.getSound = value end
        end

        if found.pst then
            SelfTalk = found
        end
        return SelfTalk
    end

    -- Dormant mode: the addon won't start a line while nextPhraseTime is in the future.
    -- It's also kept quiet while any of our lines are on screen.
    local function ApplySelfTalkMode()
        local st = FindSelfTalk()
        if not st then return end
        local pst = st.pst

        if not aiEnabled or #BottomLines > 0 then
            pst.nextPhraseTime = math.huge
        elseif pst.nextPhraseTime == math.huge then
            pst.nextPhraseTime = 0
        end
    end

    local function HideSelfTalkLine()
        local st = FindSelfTalk()
        if not st then return end
        st.pst.activePhrase = ""
        st.pst.currentPriority = 0
    end

    -- True while the addon is typing one of its own lines (only happens with talk_AI_on)
    local function SelfTalkIsTyping()
        local st = FindSelfTalk()
        if not st then return false end
        local pst = st.pst

        local cvar = GetConVar("pst_enabled")
        if cvar and not cvar:GetBool() then return false end
        if not pst.activePhrase or pst.activePhrase == "" then return false end

        local speed = pst.typeSpeed or 20
        if speed <= 0 then return false end

        return (CurTime() - (pst.typeStart or 0)) < (#pst.activePhrase / speed)
    end

    local function GetTextColor()
        local st = FindSelfTalk()
        if st and st.getColor then
            local ok, color = pcall(st.getColor)
            if ok and color then return color end
        end

        local preset = TEXT_COLOR_PRESETS[CvarString("pst_text_color_preset", "Default")]
        if preset then return preset end

        if GetConVar("pst_text_color_r") then
            return Color(
                math.Clamp(math.floor(CvarFloat("pst_text_color_r", 251)), 0, 255),
                math.Clamp(math.floor(CvarFloat("pst_text_color_g", 218)), 0, 255),
                math.Clamp(math.floor(CvarFloat("pst_text_color_b", 114)), 0, 255)
            )
        end

        return DEFAULT_TEXT_COLOR
    end

    local function GetTalkSound()
        local st = FindSelfTalk()
        if st and st.getSound then
            local ok, snd = pcall(st.getSound)
            if ok and isstring(snd) and snd ~= "" then return snd end
        end
        return DEFAULT_TALK_SOUND
    end

    ---------------------------------------------------------------------------
    -- Fonts (same settings as the self-talk addon, plus bold and above-head ones)
    ---------------------------------------------------------------------------
    local lastFontKey = ""

    local function UpdateFonts()
        local family = string.Trim(CvarString("pst_font_family", DEFAULT_FONT_FAMILY) or "")
        if family == "" or #family > 31 then family = DEFAULT_FONT_FAMILY end
        local size = math.Clamp(math.floor(CvarFloat("pst_font_size", DEFAULT_FONT_SIZE)), 8, 96)
        local weight = math.Clamp(math.floor(CvarFloat("pst_font_weight", DEFAULT_FONT_WEIGHT)), 100, 1000)

        local key = family .. "|" .. size .. "|" .. weight
        if key == lastFontKey then return key end

        local headSize = math.max(8, math.floor(size * HEAD_TEXT_SCALE + 0.5))

        surface.CreateFont(SCREEN_FONTS.normal, {
            font = family, size = size, weight = weight, antialias = true, outline = true
        })
        surface.CreateFont(SCREEN_FONTS.bold, {
            font = family, size = math.floor(size * BOLD_SIZE + 0.5), weight = 1000, antialias = true, outline = true
        })
        surface.CreateFont(HEAD_FONTS.normal, {
            font = family, size = headSize, weight = weight, antialias = true, outline = true
        })
        surface.CreateFont(HEAD_FONTS.bold, {
            font = family, size = math.floor(headSize * BOLD_SIZE + 0.5), weight = 1000, antialias = true, outline = true
        })
        surface.CreateFont(FONT_NAME, {
            font = family, size = math.max(8, math.floor(size * 0.6 + 0.5)), weight = 800, antialias = true, outline = true
        })

        lastFontKey = key
        return key
    end

    ---------------------------------------------------------------------------
    -- Reading text
    ---------------------------------------------------------------------------
    local function SplitChars(text)
        local out = {}
        if utf8 and utf8.codes then
            local ok = pcall(function()
                for _, code in utf8.codes(text) do
                    out[#out + 1] = utf8.char(code)
                end
            end)
            if ok then return out end
            out = {}
        end
        for i = 1, #text do
            out[#out + 1] = string.sub(text, i, i)
        end
        return out
    end

    local function NewChar(c)
        return { c = c, bold = false, shake = false, wobble = false, mul = 1, group = false, pauseDot = false }
    end

    -- (text!) (text?) (text?!) -> styles the whole inside and removes the brackets.
    -- Brackets without one of those at the end are left as normal text.
    local function ApplyBrackets(chars)
        local out = {}
        local i = 1

        while i <= #chars do
            local c = chars[i]
            local closeAt = nil
            local kind = nil

            if c == "(" then
                for j = i + 1, #chars do
                    if chars[j] == ")" then closeAt = j break end
                    if chars[j] == "(" then break end
                end
            end

            if closeAt then
                local k = closeAt - 1
                while k > i and chars[k] == " " do k = k - 1 end

                local hasQ, hasE = false, false
                while k > i and IsEndMark(chars[k]) do
                    if chars[k] == "?" then hasQ = true end
                    if chars[k] == "!" then hasE = true end
                    k = k - 1
                end

                if hasQ and hasE then
                    kind = "panic"
                elseif hasE then
                    kind = "shout"
                elseif hasQ then
                    kind = "question"
                end
            end

            if kind then
                for j = i + 1, closeAt - 1 do
                    local ch = NewChar(chars[j])
                    ch.group = true

                    if kind == "shout" or kind == "panic" then
                        ch.bold = true
                        ch.mul = SHOUT_FAST
                        if SHOUT_CAPS then ch.c = string.upper(ch.c) end
                    end
                    if kind == "panic" then
                        ch.shake = true
                        ch.wobble = true
                    end
                    if kind == "question" then
                        ch.mul = QUESTION_SLOW
                    end

                    out[#out + 1] = ch
                end
                i = closeAt + 1
            else
                out[#out + 1] = NewChar(c)
                i = i + 1
            end
        end

        return out
    end

    -- Splits into sentences, finds dot pauses and styles ? ! ?! endings
    local function BuildSentences(chars)
        local sentences = {}
        local cur = { chars = {} }
        local n = #chars
        local i = 1

        local function Finish(endPause)
            while #cur.chars > 0 and cur.chars[#cur.chars].c == " " do
                cur.chars[#cur.chars] = nil
            end
            if #cur.chars > 0 then
                cur.endPause = endPause
                sentences[#sentences + 1] = cur
            end
            cur = { chars = {} }
        end

        while i <= n do
            local ch = chars[i]
            local c = ch.c
            local prev = chars[i - 1]
            local nextCh = chars[i + 1]
            local isDecimal = c == "." and IsDigit(prev and prev.c) and IsDigit(nextCh and nextCh.c)

            if IsEndMark(c) and not isDecimal then
                local runStart = #cur.chars + 1
                local dots, hasQ, hasE = 0, false, false
                local runIsGroup = ch.group
                local j = i

                while j <= n and IsEndMark(chars[j].c) do
                    local cc = chars[j].c
                    if cc == "." then dots = dots + 1 end
                    if cc == "?" then hasQ = true end
                    if cc == "!" then hasE = true end
                    cur.chars[#cur.chars + 1] = chars[j]
                    j = j + 1
                end

                -- Two or more dots: each dot appears on its own, 1.5s apart
                if dots >= 2 then
                    local counted = 0
                    for r = runStart, #cur.chars do
                        if cur.chars[r].c == "." and counted < MAX_DOTS then
                            cur.chars[r].pauseDot = true
                            counted = counted + 1
                        end
                    end
                end

                local isEnd = hasQ or hasE or dots == 1

                if isEnd then
                    if not runIsGroup then
                        if hasE then
                            -- only the last word (and its punctuation) gets the style
                            local k = runStart - 1
                            while k >= 1 and cur.chars[k].c ~= " " do
                                local wc = cur.chars[k]
                                if not wc.group then
                                    wc.bold = true
                                    if hasQ then
                                        wc.shake = true
                                        wc.wobble = true
                                    end
                                end
                                k = k - 1
                            end
                            for r = runStart, #cur.chars do
                                cur.chars[r].bold = true
                                if hasQ then cur.chars[r].shake = true end
                            end
                        elseif hasQ then
                            -- the whole sentence types slower
                            for _, sc in ipairs(cur.chars) do
                                if not sc.group then sc.mul = QUESTION_SLOW end
                            end
                        end
                    end

                    Finish(DOT_PAUSE)

                    while j <= n and chars[j].c == " " do j = j + 1 end
                end

                i = j
            else
                if not (c == " " and #cur.chars == 0) then
                    cur.chars[#cur.chars + 1] = ch
                end
                i = i + 1
            end
        end

        Finish(0)

        -- how long each letter takes
        for _, s in ipairs(sentences) do
            for _, sc in ipairs(s.chars) do
                if sc.pauseDot then
                    sc.dt = DOT_PAUSE
                else
                    local mul = sc.mul
                    if sc.wobble then
                        mul = mul * (PANIC_MIN + math.random() * (PANIC_MAX - PANIC_MIN))
                    end
                    sc.dt = LETTER_TIME * mul
                end
            end
        end

        return sentences
    end

    local function ParseText(text)
        return BuildSentences(ApplyBrackets(SplitChars(text)))
    end

    ---------------------------------------------------------------------------
    -- Laying out a sentence (word wrap, centred, bottom at 0)
    ---------------------------------------------------------------------------
    local function LayoutSentence(s, fonts, maxW)
        for _, ch in ipairs(s.chars) do
            ch.font = ch.bold and fonts.bold or fonts.normal
            surface.SetFont(ch.font)
            ch.w, ch.h = surface.GetTextSize(ch.c)
        end

        surface.SetFont(fonts.normal)
        local _, normalH = surface.GetTextSize("Ag")

        local lines = {}
        local line = { first = 1, last = 0, width = 0, height = normalH }
        local i = 1
        local count = #s.chars

        while i <= count do
            local j = i
            local wordW = 0
            while j <= count and s.chars[j].c ~= " " do
                wordW = wordW + s.chars[j].w
                j = j + 1
            end

            if line.last >= line.first and line.width + wordW > maxW then
                lines[#lines + 1] = line
                line = { first = i, last = i - 1, width = 0, height = normalH }
            end

            local stop = math.min(j, count) -- include the space after the word
            for k = i, stop do
                local ch = s.chars[k]
                ch.x = line.width
                ch.lineIndex = #lines + 1
                line.width = line.width + ch.w
                line.height = math.max(line.height, ch.h)
                line.last = k
            end

            i = stop + 1
        end
        lines[#lines + 1] = line

        local totalH = 0
        local widest = 0
        for _, l in ipairs(lines) do
            local lastCh = s.chars[l.last]
            l.drawWidth = l.width
            if lastCh and lastCh.c == " " then l.drawWidth = l.width - lastCh.w end
            widest = math.max(widest, l.drawWidth)
            totalH = totalH + l.height
        end

        local y = -totalH
        for _, l in ipairs(lines) do
            l.top = y
            l.left = -l.drawWidth / 2
            y = y + l.height
        end

        for _, ch in ipairs(s.chars) do
            local l = lines[ch.lineIndex]
            ch.rx = l.left + ch.x
            ch.ry = l.top + l.height - ch.h -- bottoms line up
        end

        -- group letters into runs that can be drawn in one go
        s.runs = {}
        local run = nil
        for k, ch in ipairs(s.chars) do
            local canJoin = run and not ch.shake and not run.shake
                and run.font == ch.font and run.lineIndex == ch.lineIndex

            if canJoin then
                run.last = k
            else
                run = { first = k, last = k, font = ch.font, lineIndex = ch.lineIndex, shake = ch.shake, rx = ch.rx, ry = ch.ry }
                s.runs[#s.runs + 1] = run
            end
        end

        s.blockH = totalH
        s.blockW = widest
    end

    local function EnsureLayout(s, fonts, maxW)
        local key = lastFontKey .. "|" .. fonts.normal .. "|" .. math.floor(maxW)
        if s.layoutKey ~= key then
            LayoutSentence(s, fonts, maxW)
            s.layoutKey = key
        end
    end

    ---------------------------------------------------------------------------
    -- Chat lines (typed out with pauses)
    ---------------------------------------------------------------------------
    local function PlayLetterSound()
        local cv = GetConVar("pst_sounds_enabled")
        if cv and not cv:GetBool() then return end
        if CurTime() < nextLetterSound then return end

        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local snd = GetTalkSound()
        if not precachedSounds[snd] then
            util.PrecacheSound(snd)
            precachedSounds[snd] = true
        end

        ply:EmitSound(snd, 70, 110, math.Clamp(CvarFloat("pst_sound_volume", 0.6), 0, 1), CHAN_STATIC)
        nextLetterSound = CurTime() + 0.03
    end

    local function OnLetter(line, ch)
        local c = ch.c

        if c ~= " " and line.sound and chatBoxEnabled then
            PlayLetterSound()
        end

        if not line.ownsMouth then return end

        if ch.pauseDot then
            MouthStop()
            return
        end

        if c == " " then
            if mouthOpen then
                SendMouth(MOUTH_REST)
                mouthOpen = false
            end
            lettersSinceSwap = 0
            return
        end

        if string.match(c, "^%p$") then return end -- punctuation doesn't move the mouth

        lettersSinceSwap = lettersSinceSwap + 1
        if (not mouthOpen or lettersSinceSwap >= LETTERS_PER_MOUTH) and CurTime() - lastMouthSend >= MIN_MOUTH_GAP then
            SendMouth(MOUTH_TALK)
            mouthOpen = true
            lettersSinceSwap = 0
        end
    end

    local function NewChatLine(text, opts)
        local sentences = ParseText(text)
        if #sentences == 0 then return nil end

        opts = opts or {}
        return {
            kind = "chat",
            sentences = sentences,
            index = 1,
            typed = 0,
            state = "typing",
            nextChar = CurTime(),
            waitUntil = 0,
            ownsMouth = opts.ownsMouth,
            sound = opts.sound,
            name = opts.name,
            nameColor = opts.nameColor,
            done = false
        }
    end

    local function UpdateChatLine(line, now)
        local s = line.sentences[line.index]
        if not s then
            line.done = true
            return
        end

        if line.state == "typing" then
            while now >= line.nextChar and line.typed < #s.chars do
                line.typed = line.typed + 1
                local ch = s.chars[line.typed]
                line.nextChar = line.nextChar + ch.dt
                OnLetter(line, ch)
            end

            -- wait for the last letter's time (a dot's 1.5s) before moving on
            if line.typed >= #s.chars and now >= line.nextChar then
                if line.ownsMouth then MouthStop() end

                if line.index < #line.sentences then
                    line.state = "between"
                    line.waitUntil = now + s.endPause
                else
                    line.state = "linger"
                    line.fadeTime = CHAT_FADE_TIME
                    line.waitUntil = now + LINGER_TIME
                end
            end

        elseif line.state == "between" then
            if now >= line.waitUntil then
                line.index = line.index + 1
                line.typed = 0
                line.state = "typing"
                line.nextChar = now
            end

        elseif line.state == "linger" then
            if now >= line.waitUntil then
                line.done = true
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Speech lines (text arrives while you talk; the newest sentence is shown)
    ---------------------------------------------------------------------------
    local function NewSpeechLine(opts)
        opts = opts or {}
        return {
            kind = "speech",
            sentences = {},
            index = 0,
            typed = 0,
            state = "live",
            nextChar = CurTime(),
            final = false,
            lastUpdate = CurTime(),
            name = opts.name,
            nameColor = opts.nameColor,
            done = false
        }
    end

    local function SetSpeechText(line, text, final)
        local sentences = ParseText(text or "")
        local oldCount = #line.sentences

        line.sentences = sentences
        line.final = final
        line.lastUpdate = CurTime()

        if #sentences == 0 then
            line.index = 0
            line.typed = 0
            return
        end

        if #sentences > oldCount then
            line.typed = 0 -- a new sentence started: it replaces the old one
        end
        line.index = #sentences
        line.typed = math.min(line.typed, #sentences[line.index].chars)

        if line.nextChar < CurTime() then
            line.nextChar = CurTime()
        end
    end

    -- Typing sound for speech above someone's head: it comes from them, so people nearby hear it
    local function PlaySpeechSound(line, now)
        local ent = line.soundEnt
        if not IsValid(ent) or now < (line.nextSound or 0) then return end

        local cv = GetConVar("pst_sounds_enabled")
        if cv and not cv:GetBool() then return end

        local snd = GetTalkSound()
        if not precachedSounds[snd] then
            util.PrecacheSound(snd)
            precachedSounds[snd] = true
        end

        ent:EmitSound(snd, 70, 110, math.Clamp(CvarFloat("pst_sound_volume", 0.6), 0, 1), CHAN_STATIC)
        line.nextSound = now + 0.03
    end

    local function UpdateSpeechLine(line, now)
        local s = line.sentences[line.index]

        if s and line.typed < #s.chars then
            while now >= line.nextChar and line.typed < #s.chars do
                line.typed = line.typed + 1
                line.nextChar = line.nextChar + SPEECH_LETTER_TIME
                if s.chars[line.typed].c ~= " " then
                    PlaySpeechSound(line, now)
                end
            end
            if line.nextChar < now - 0.2 then line.nextChar = now end
            return
        end

        if not line.final and now - line.lastUpdate > SPEECH_TIMEOUT then
            line.final = true
        end

        if line.final then
            if line.state ~= "linger" then
                line.state = "linger"
                line.fadeTime = SPEECH_FADE
                line.waitUntil = now + SPEECH_LINGER + SPEECH_FADE
            elseif now >= line.waitUntil then
                line.done = true
            end
        end
    end

    local function UpdateLine(line, now)
        if line.kind == "speech" then
            UpdateSpeechLine(line, now)
        else
            UpdateChatLine(line, now)
        end
    end

    ---------------------------------------------------------------------------
    -- Drawing a line (returns how tall it was, for stacking)
    ---------------------------------------------------------------------------
    local function LineAlpha(line)
        if line.state == "linger" and line.fadeTime and line.fadeTime > 0 then
            local left = line.waitUntil - CurTime()
            if left < line.fadeTime then
                return math.Clamp(left / line.fadeTime, 0, 1)
            end
        end
        return 1
    end

    local function DrawLine(line, cx, bottomY, fonts, maxW, alphaMul)
        local s = line.sentences[line.index]
        if not s or line.typed <= 0 then return 0 end

        EnsureLayout(s, fonts, maxW)

        local alpha = LineAlpha(line) * (alphaMul or 1) * 255
        if alpha <= 1 then return s.blockH end

        local base = GetTextColor()
        local color = Color(base.r, base.g, base.b, alpha)
        local outline = Color(0, 0, 0, alpha)
        local now = CurTime()

        for _, run in ipairs(s.runs) do
            if run.first > line.typed then break end

            local last = math.min(run.last, line.typed)
            local parts = {}
            for k = run.first, last do
                parts[#parts + 1] = s.chars[k].c
            end
            local text = table.concat(parts)

            local x, y = cx + run.rx, bottomY + run.ry
            if run.shake then
                x = x + math.sin(now * 40 + run.first * 2.3) * SHAKE_PIXELS
                y = y + math.cos(now * 33 + run.first * 1.9) * SHAKE_PIXELS
            end

            if string.Trim(text) ~= "" then
                draw.SimpleTextOutlined(text, run.font, x, y, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 2, outline)
            end
        end

        local height = s.blockH

        if line.name then
            local nc = line.nameColor or Color(200, 200, 200)
            surface.SetFont(FONT_NAME)
            local _, nameH = surface.GetTextSize(line.name)
            draw.SimpleTextOutlined(line.name, FONT_NAME, cx, bottomY - s.blockH - 2,
                Color(nc.r, nc.g, nc.b, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, outline)
            height = height + nameH + 2
        end

        return height
    end

    ---------------------------------------------------------------------------
    -- Bottom-of-screen stack
    ---------------------------------------------------------------------------
    local function RemoveBottomLine(line)
        for i = #BottomLines, 1, -1 do
            if BottomLines[i] == line then
                table.remove(BottomLines, i)
            end
        end
        if line and line.ownsMouth and not line.done and line.state ~= "linger" then
            MouthStop()
        end
        if line == OwnChat then OwnChat = nil end
        if line == OwnSpeech then OwnSpeech = nil end
    end

    local function AddBottomLine(line)
        BottomLines[#BottomLines + 1] = line
        while #BottomLines > MAX_BOTTOM_LINES do
            RemoveBottomLine(BottomLines[1])
        end
        HideSelfTalkLine()
        ApplySelfTalkMode()
    end

    local function StartOwnChat(text)
        local line = NewChatLine(text, { ownsMouth = true, sound = true })
        if not line then return end

        if OwnChat then RemoveBottomLine(OwnChat) end
        OwnChat = line
        mouthOpen = false
        lettersSinceSwap = 0
        AddBottomLine(line)
    end

    ---------------------------------------------------------------------------
    -- Voice helper bridge (files in garrysmod/data/mouth_script/)
    ---------------------------------------------------------------------------
    local function WriteVoiceState(state)
        if state == lastVoiceState then return end
        file.Write(VOICE_STATE_FILE, state)
        lastVoiceState = state
    end

    local function HelperIsRunning()
        local raw = file.Read(HELPER_ALIVE_FILE, "DATA")
        local t = tonumber(raw or "")
        return t ~= nil and math.abs(os.time() - t) < 8
    end

    local function SendSpeech(id, final, text)
        net.Start(NET_SPEECH)
        net.WriteUInt(id % 4294967296, 32)
        net.WriteBool(final)
        net.WriteString(string.sub(text, 1, MAX_TEXT))
        net.SendToServer()
    end

    local function ReadHelperOutput()
        local raw = file.Read(VOICE_OUT_FILE, "DATA")
        if not raw or raw == "" or raw == lastHelperRaw then return end
        lastHelperRaw = raw

        local data = util.JSONToTable(raw)
        if not istable(data) or not isstring(data.text) then return end

        -- ignore old leftovers from a previous session
        local t = tonumber(data.t)
        if t and math.abs(os.time() - t) > 15 then return end

        local text = string.Trim(data.text)
        local final = data.final == true
        local id = tostring(data.id)

        if id ~= lastHelperId or not OwnSpeech then
            lastHelperId = id
            speechCounter = speechCounter + 1

            if OwnSpeech then RemoveBottomLine(OwnSpeech) end
            OwnSpeech = NewSpeechLine()
            AddBottomLine(OwnSpeech)

            -- the same speech above your own head (seen in third person / with listen_self_on)
            local me = LocalPlayer()
            if IsValid(me) then
                local headLine = NewSpeechLine()
                headLine.soundEnt = me
                HeadLines[me] = headLine
            end
        end

        if text == "" and not final then return end

        SetSpeechText(OwnSpeech, text, final)

        local myHead = HeadLines[LocalPlayer()]
        if myHead then SetSpeechText(myHead, text, final) end
        SendSpeech(speechCounter, final, text)
    end

    ---------------------------------------------------------------------------
    -- Network: other players' global chat and speech
    ---------------------------------------------------------------------------
    net.Receive(NET_GLOBAL, function()
        local sender = net.ReadEntity()
        local text = net.ReadString()
        if not IsValid(sender) or sender == LocalPlayer() then return end

        local line = NewChatLine(text, {
            sound = true,
            name = sender:Nick(),
            nameColor = team.GetColor(sender:Team())
        })
        if line then AddBottomLine(line) end
    end)

    net.Receive(NET_SPEECH, function()
        local sender = net.ReadEntity()
        local id = net.ReadUInt(32)
        local final = net.ReadBool()
        local text = net.ReadString()
        if not IsValid(sender) or sender == LocalPlayer() then return end

        local line = HeadLines[sender]
        if not line or line.speechId ~= id then
            line = NewSpeechLine()
            line.speechId = id
            line.soundEnt = sender
            HeadLines[sender] = line
        end

        SetSpeechText(line, text, final)
    end)

    ---------------------------------------------------------------------------
    -- Updating and drawing everything
    ---------------------------------------------------------------------------
    hook.Add("Think", "MouthScriptLines", function()
        local now = CurTime()
        local ply = LocalPlayer()

        -- your chat stops if you die
        if OwnChat and IsValid(ply) and not ply:Alive() and not OwnChat.done then
            RemoveBottomLine(OwnChat)
            OwnChat = nil
        end

        for i = #BottomLines, 1, -1 do
            local line = BottomLines[i]
            UpdateLine(line, now)
            if line.done then
                table.remove(BottomLines, i)
                if line == OwnChat then OwnChat = nil end
                if line == OwnSpeech then OwnSpeech = nil end
            end
        end

        for who, line in pairs(HeadLines) do
            if not IsValid(who) then
                HeadLines[who] = nil
            else
                UpdateLine(line, now)
                if line.done then HeadLines[who] = nil end
            end
        end
    end)

    hook.Add("HUDPaint", "MouthScriptDrawLines", function()
        UpdateFonts()

        -- bottom of the screen
        if chatBoxEnabled and #BottomLines > 0 then
            surface.SetFont(SCREEN_FONTS.normal)
            local _, normalH = surface.GetTextSize("Ag")
            local y = ScrH() - 200 + normalH
            local maxW = ScrW() * 0.7

            for i = #BottomLines, 1, -1 do
                local h = DrawLine(BottomLines[i], ScrW() / 2, y, SCREEN_FONTS, maxW, 1)
                if h > 0 then y = y - h - 8 end
            end
        end

        -- above other players' heads
        local me = LocalPlayer()
        if not IsValid(me) then return end
        local eye = EyePos() -- where the view is right now (works with cameras too)
        local showOwnHead = listenSelfEnabled or me:ShouldDrawLocalPlayer()

        for who, line in pairs(HeadLines) do
            local canShow = who ~= me or showOwnHead
            if canShow and IsValid(who) and who:Alive() and not who:IsDormant() then
                local headPos = who:GetPos() + Vector(0, 0, who:OBBMaxs().z + 14)
                local dist = eye:Distance(headPos)

                if dist < HEAD_TEXT_DISTANCE then
                    local tr = util.TraceLine({ start = eye, endpos = headPos, filter = { me, who }, mask = MASK_OPAQUE })
                    if who == me then tr.Hit = false end
                    local screen = headPos:ToScreen()

                    if not tr.Hit and screen.visible then
                        local fade = 1 - math.Clamp((dist - HEAD_TEXT_DISTANCE * 0.7) / (HEAD_TEXT_DISTANCE * 0.3), 0, 1)
                        DrawLine(line, screen.x, screen.y, HEAD_FONTS, 420, fade)
                    end
                end
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Saved lists, one per playermodel (garrysmod/data/bodygroup_talk_saves.json)
    ---------------------------------------------------------------------------
    local SAVE_FILE = "bodygroup_talk_saves.json"

    local function ReadSaves()
        local raw = file.Read(SAVE_FILE, "DATA")
        if not raw or raw == "" then return {} end
        local saves = util.JSONToTable(raw)
        if istable(saves) then return saves end
        return {}
    end

    local function WriteSaves(saves)
        file.Write(SAVE_FILE, util.TableToJSON(saves, true))
    end

    local function CurrentCharacter()
        local ply = LocalPlayer()
        if not IsValid(ply) then return nil end
        local model = string.lower(ply:GetModel() or "")
        if model == "" then return nil end
        return model, string.StripExtension(string.GetFileFromFilename(model))
    end

    ---------------------------------------------------------------------------
    -- Commands
    ---------------------------------------------------------------------------
    local GREEN = Color(0, 255, 120)
    local ORANGE = Color(255, 170, 0)
    local BLUE = Color(0, 200, 255)

    local function Say(color, message)
        chat.AddText(color, "[Mouth Script] ", Color(235, 235, 235), message)
    end

    local function ProcessTalkCommand(text)
        local args = string.Explode(" ", string.Trim(text))
        local cmd = string.lower(args[1] or "")
        cmd = string.gsub(cmd, "^!", "")

        if cmd == "talk_on" then
            chatBoxEnabled = true
            Say(GREEN, "Chat messages will show at the bottom of the screen.")
            return true

        elseif cmd == "talk_off" then
            chatBoxEnabled = false
            Say(ORANGE, "Chat messages won't show at the bottom of the screen (your mouth still moves).")
            return true

        elseif cmd == "talk_mic_on" then
            micVoiceBoxEnabled = true
            Say(GREEN, "Mic beeps & [Speaking...] box ENABLED.")
            return true

        elseif cmd == "talk_mic_off" or cmd == "talk_mute" then
            micVoiceBoxEnabled = false
            Say(ORANGE, "Mic beeps & [Speaking...] box MUTED.")
            return true

        elseif cmd == "talk_ai_on" or cmd == "talk_ai_off" then
            if not FindSelfTalk() then
                Say(ORANGE, "The Casualties: Unknown self-talk addon isn't installed.")
                return true
            end

            aiEnabled = (cmd == "talk_ai_on")
            ApplySelfTalkMode()

            if aiEnabled then
                Say(GREEN, "Self-talk addon ON: it talks on its own again.")
            else
                Say(ORANGE, "Self-talk addon OFF: only your messages show now.")
            end
            return true

        elseif cmd == "listen_voice_on" then
            listenVoiceEnabled = true
            if HelperIsRunning() then
                Say(GREEN, "Voice-to-text ON. Hold your voice key and talk.")
            else
                Say(ORANGE, "Voice-to-text ON, but the voice helper isn't running. Start \"START VOICE HELPER.bat\" in addons/mouth_script/voice_helper.")
            end
            return true

        elseif cmd == "listen_voice_off" then
            listenVoiceEnabled = false
            WriteVoiceState("off")
            Say(ORANGE, "Voice-to-text OFF.")
            return true

        elseif cmd == "listen_self_on" then
            listenSelfEnabled = true
            Say(GREEN, "You'll see your own speech above your head (handy with a camera).")
            return true

        elseif cmd == "listen_self_off" then
            listenSelfEnabled = false
            Say(ORANGE, "Your own speech only shows above your head in third person now.")
            return true

        elseif cmd == "global_chat_on" then
            globalChatEnabled = true
            Say(GREEN, "Global chat ON: everyone sees your messages at the bottom of their screen.")
            return true

        elseif cmd == "global_chat_off" then
            globalChatEnabled = false
            Say(ORANGE, "Global chat OFF: only you see your messages at the bottom of the screen.")
            return true

        elseif cmd == "talk_list" or cmd == "talk_list_order" then
            currentCustomList = {}
            for i = 2, #args do
                local num = tonumber(args[i])
                if num then
                    table.insert(currentCustomList, math.floor(num))
                end
            end

            if cmd == "talk_list_order" then
                isOrderedMode = true
                Say(BLUE, "Sequential order set (" .. #currentCustomList .. " notches, left-to-right)!")
            else
                isOrderedMode = false
                Say(GREEN, "Random list set (" .. #currentCustomList .. " notches)!")
            end
            return true

        elseif cmd == "line_save" then
            local model, shortName = CurrentCharacter()
            if not model then return true end

            if #currentCustomList == 0 then
                Say(ORANGE, "Nothing to save yet. Set a list first with talk_list or talk_list_order.")
                return true
            end

            local saves = ReadSaves()
            saves[model] = { list = currentCustomList, ordered = isOrderedMode }
            WriteSaves(saves)

            Say(GREEN, "Saved your " .. (isOrderedMode and "order" or "random list") .. " (" .. table.concat(currentCustomList, " ") .. ") for " .. shortName .. ".")
            return true

        elseif cmd == "line_load" then
            local model, shortName = CurrentCharacter()
            if not model then return true end

            local save = ReadSaves()[model]
            if not istable(save) or not istable(save.list) or #save.list == 0 then
                Say(ORANGE, "No save for " .. shortName .. " yet. Set a list, then type line_save.")
                return true
            end

            currentCustomList = {}
            for _, num in ipairs(save.list) do
                if tonumber(num) then
                    table.insert(currentCustomList, math.floor(tonumber(num)))
                end
            end
            isOrderedMode = save.ordered == true

            Say(BLUE, "Loaded your " .. (isOrderedMode and "order" or "random list") .. " (" .. table.concat(currentCustomList, " ") .. ") for " .. shortName .. ".")
            return true
        end

        return false
    end

    hook.Add("OnPlayerChat", "SyncMouthWithSelfTalkAddon", function(ply, text, teamChat, isDead)
        if ply ~= LocalPlayer() then return end

        -- Backup in case the server hook isn't running
        if string.sub(text, 1, 1) == "!" and ProcessTalkCommand(text) then
            return true
        end

        if isDead or not ply:Alive() then return end

        StartOwnChat(text)

        if globalChatEnabled then
            net.Start(NET_GLOBAL)
            net.WriteString(string.sub(text, 1, MAX_TEXT))
            net.SendToServer()
        end
    end)

    local function AddConsoleCommand(name)
        concommand.Add(name, function(ply, cmd, args)
            ProcessTalkCommand(name .. " " .. table.concat(args, " "))
        end)
    end

    AddConsoleCommand("talk_on")
    AddConsoleCommand("talk_off")
    AddConsoleCommand("talk_mic_on")
    AddConsoleCommand("talk_mic_off")
    AddConsoleCommand("talk_mute")
    AddConsoleCommand("talk_AI_on")
    AddConsoleCommand("talk_AI_off")
    AddConsoleCommand("listen_voice_on")
    AddConsoleCommand("listen_voice_off")
    AddConsoleCommand("global_chat_on")
    AddConsoleCommand("global_chat_off")
    AddConsoleCommand("listen_self_on")
    AddConsoleCommand("listen_self_off")
    AddConsoleCommand("talk_list")
    AddConsoleCommand("talk_list_order")
    AddConsoleCommand("line_save")
    AddConsoleCommand("line_load")

    ---------------------------------------------------------------------------
    -- Mic [Speaking...] box
    ---------------------------------------------------------------------------
    local helperRunningCached = true
    local nextHelperCheck = 0

    hook.Add("HUDPaint", "DrawMicVoiceIndicator", function()
        -- warn when you talk but the voice helper isn't running
        if listenVoiceEnabled and isMicSpeakingNow and not helperRunningCached then
            draw.SimpleTextOutlined("Voice-to-text: the voice helper isn't running (START VOICE HELPER.bat)",
                "Trebuchet18", ScrW() / 2, ScrH() - 160, Color(255, 170, 0), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0))
        end

        if not micVoiceBoxEnabled or not isMicSpeakingNow then return end

        local dots = string.rep(".", micDotsCount)
        local displayText = "[Speaking" .. dots .. "]"

        surface.SetFont("Trebuchet24")
        local textW, textH = surface.GetTextSize(displayText)
        local boxW = math.max(textW + 40, 180)
        local boxH = textH + 20
        local boxX = (ScrW() / 2) - (boxW / 2)
        local boxY = ScrH() - 140

        draw.RoundedBox(6, boxX, boxY, boxW, boxH, Color(15, 15, 18, 220))
        surface.SetDrawColor(180, 180, 190, 90)
        surface.DrawOutlinedRect(boxX, boxY, boxW, boxH, 1)
        draw.SimpleText(displayText, "Trebuchet24", ScrW() / 2, boxY + (boxH / 2), Color(245, 245, 245, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)

    ---------------------------------------------------------------------------
    -- Main check (every 0.05s): mic talking, the addon's own lines, the voice helper
    ---------------------------------------------------------------------------
    local nextHelperRead = 0

    timer.Create("BodygroupVoiceClientCheck", 0.05, 0, function()
        -- Keeps the addon dormant (also catches it if it loads after this script)
        ApplySelfTalkMode()

        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local speaking = ply:IsSpeaking()
        local micTalking = speaking and ply:VoiceVolume() > 0.05
        local isTalking = (micTalking or SelfTalkIsTyping()) and ply:Alive()

        isMicSpeakingNow = micTalking

        if CurTime() >= nextHelperCheck then
            helperRunningCached = HelperIsRunning()
            nextHelperCheck = CurTime() + 2
        end

        -- tell the voice helper when to listen
        if listenVoiceEnabled then
            WriteVoiceState(speaking and "1" or "0")

            if CurTime() >= nextHelperRead then
                ReadHelperOutput()
                nextHelperRead = CurTime() + 0.1
            end
        else
            WriteVoiceState("off")
        end

        if micTalking and micVoiceBoxEnabled then
            if CurTime() >= nextMicBeep then
                surface.PlaySound(BEEP_SOUND)
                micDotsCount = (micDotsCount % 3) + 1
                nextMicBeep = CurTime() + BEEP_INTERVAL
            end
        else
            micDotsCount = 1
        end

        -- While your chat line is being typed, it moves the mouth itself
        if OwnChatBusy() then
            wasTalking = false
            nextMouthSwap = 0
            return
        end

        if isTalking then
            if CurTime() >= nextMouthSwap then
                SendMouth(MOUTH_TALK)
                nextMouthSwap = CurTime() + MOUTH_SWAP_DELAY
                wasTalking = true
            end
        elseif wasTalking then
            SendMouth(MOUTH_STOP)
            wasTalking = false
            nextMouthSwap = 0
        end
    end)

    hook.Add("ShutDown", "MouthScriptVoiceStateOff", function()
        file.Write(VOICE_STATE_FILE, "off")
    end)
end
