#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
InstallKeybdHook()
InstallMouseHook()
SendMode "Input"
SetWorkingDir A_ScriptDir

; =====================================================================
; Всі бінди редагуються в Binds.txt (файл поруч зі скриптом).
; Цей файл (BinderReplacer.ahk) чіпати не треба - тут тільки логіка.
; Якщо не спрацьовує відправка клавіш в грі - зміни SendMode вище
; на "Event" (рядок 3): SendMode "Event"
; =====================================================================

BindsFile := A_ScriptDir "\Binds.txt"

if !FileExist(BindsFile) {
    try {
        FileAppend(DefaultBindsTemplate(), BindsFile, "UTF-8")
    } catch as e {
        MsgBox("Не вдалося створити Binds.txt: " e.Message)
        ExitApp()
    }
    MsgBox("Файл Binds.txt не знайдено — створено новий.`n`nЩоб змінити бінди, натисніть ЛКМ на іконку біндера в треї (або налаштуйте файл вручну й натисніть ПКМ -> 'Перезавантажити бінди').`n`nЯкщо використовуєте біндер вперше, рекомендовано скористатись довідкою яка також доступна в треї.", "Binds.txt створено", "Icon!")
}

binds := ParseBinds(BindsFile)
lastUsed := Map()
imageGuis := Map()
hotkeyHandlers := Map()  ; key → handler, щоб правильно вмикати/вимикати
hoverBtns    := Map()    ; hwnd → {ctrl, normalBg, hoverBg, active}
suspendLabel := "⏹️ Призупинити біндер"
editorBtnSuspend := 0
bindBusy := false
stopBind := false
setMenuState := Map("gui", 0, "enabled", [])

PruneOrphanedCache(binds)

if (binds.Length = 0) {
    MsgBox("У Binds.txt не знайдено жодного валідного бінда. Перевір формат.")
    ExitApp()
}

; --- Кастомне трей-меню замість стандартного англійського ---
A_TrayMenu.Delete()
A_TrayMenu.Add(suspendLabel, ToggleSuspend)
A_TrayMenu.Add()
A_TrayMenu.Add("Довідка", OpenHelpWindow)
A_TrayMenu.Add("Перезавантажити бінди", ReloadBinds)
A_TrayMenu.Add()
A_TrayMenu.Add("❌ Закрити біндер", (*) => ExitApp())
A_TrayMenu.Add()
A_TrayMenu.Add("by @dasventur (Discord)", (*) => "")
A_TrayMenu.Disable("by @dasventur (Discord)")

OnMessage(0x404, TrayClick)
TrayClick(wParam, lParam, msg, hwnd) {
    if (lParam = 0x202) { ; WM_LBUTTONUP
        SetTimer(OpenBindEditor, -1)
    }
}

OnMessage(0x200, _BtnMouseMove)   ; WM_MOUSEMOVE
OnMessage(0x2A3, _BtnMouseLeave)  ; WM_MOUSELEAVE

ToggleSuspend(*) {
    global suspendLabel, editorBtnSuspend
    Suspend(-1)
    newLabel := A_IsSuspended ? "▶️ Відновити біндер" : "⏹️ Призупинити біндер"
    A_TrayMenu.Rename(suspendLabel, newLabel)
    suspendLabel := newLabel
    if (IsObject(editorBtnSuspend)) {
        try editorBtnSuspend.Text := newLabel
    }
}

; Перетворює клавішу активації типу "Ctrl+F1" чи "~Ctrl+Shift+Esc"
; на нативний синтаксис AHK-хоткея "^F1" / "~^+Esc". Якщо клавіша вже
; написана нативно (напр. "^F1" чи просто "F1", "[", "]") - лишає як є.
ResolveTriggerKey(rawKey) {
    prefix := ""
    key := rawKey
    if (SubStr(key, 1, 1) = "~") {
        prefix := "~"
        key := SubStr(key, 2)
    }

    if InStr(key, "+") && RegExMatch(key, "i)^(ctrl|control|alt|shift|win|windows|lwin|rwin)\+") {
        parts := StrSplit(key, "+")
        keyPart := Trim(parts[parts.Length])
        modPart := ""
        Loop parts.Length - 1
            modPart .= KeyComboModSymbol(parts[A_Index])
        return prefix modPart keyPart
    }
    return prefix key
}

ApplyKeyGroups(binds)

RegisterActionHandler(b) {
    return (*) => RunActionBind(b)
}

RegisterImageHandler(b) {
    return (*) => ToggleImageBind(b)
}

AnyGuiOpenOrBindRunning() {
    global imageGuis, setMenuState, bindBusy
    if bindBusy
        return true
    if (imageGuis.Count > 0)
        return true
    if IsObject(setMenuState["gui"])
        return true
    return false
}

IsEditorOrMenuOpen() {
    if WinActive("LSPD Binder | Редактор біндів")
        return true
    if WinActive("Додати новий бінд")
        return true
    if WinActive("Редагувати бінд")
        return true
    if WinActive("LSPD Binder | Довідка")
        return true
    if WinActive("Підтвердження видалення")
        return true
    return false
}

; --- Esc зупиняє поточний бінд або закриває меню/картинки ---
#HotIf AnyGuiOpenOrBindRunning()
Esc:: {
    global imageGuis, bindBusy, stopBind
    if bindBusy {
        stopBind := true
    }
    CloseSetMenu()
    for k, g in imageGuis {
        try g.Destroy()
    }
    imageGuis.Clear()
}
#HotIf

IsSetMenuOpen() {
    global setMenuState
    return IsObject(setMenuState["gui"])
}

#HotIf IsSetMenuOpen()
1::
2::
3::
4::
5::
6::
7::
8::
9::
0::
Numpad1::
Numpad2::
Numpad3::
Numpad4::
Numpad5::
Numpad6::
Numpad7::
Numpad8::
Numpad9::
Numpad0::
{
    keyStr := StrReplace(A_ThisHotkey, "Numpad", "")
    idx := Integer(keyStr)
    if (idx = 0)
        idx := 10
    RunSetMenuByIndex(idx)
}
#HotIf

ReloadBinds(*) {
    global BindsFile, editorGuiCtx

    newBinds := ParseBinds(BindsFile)
    ApplyBinds(newBinds)
    PruneOrphanedCache(newBinds)

    if IsSet(editorGuiCtx) && IsObject(editorGuiCtx) {
        try {
            editorGuiCtx["binds"] := newBinds
            EditorRefreshList(editorGuiCtx)
        }
    }

    TrayTip("Налаштування з Binds.txt застосовано.", "Бінди перезавантажено!")
}

ApplyBinds(newBinds) {
    global binds, imageGuis, hotkeyHandlers

    ; Вимикаємо старі хоткеї через збережений handler (інакше AHK v2 не знаходить
    ; потрібний variant і ігнорує виклик — старий closure лишається активним)
    HotIf (*) => !IsEditorOrMenuOpen()
    for resolvedKey, handler in hotkeyHandlers {
        try Hotkey(resolvedKey, handler, "Off")
    }
    HotIf
    hotkeyHandlers := Map()

    for k, g in imageGuis {
        try g.Destroy()
    }
    imageGuis.Clear()

    binds := newBinds
    ApplyKeyGroups(binds)
}

; Групує бінди за клавішею і реєструє хоткеї:
; якщо ключ один — запускає напряму,
; якщо кілька — відкриває меню вибору.
ApplyKeyGroups(bindList) {
    global hotkeyHandlers

    ; Будуємо Map: resolvedKey -> [список біндів]
    groups := Map()
    for b in bindList {
        rk := ResolveTriggerKey(b.key)
        if !groups.Has(rk)
            groups[rk] := []
        groups[rk].Push(b)
    }

    HotIf (*) => !IsEditorOrMenuOpen()
    for rk, grp in groups {
        ; Визначаємо, чи є хоча б один увімкнений бінд у групі
        anyEnabled := false
        for b in grp {
            if b.enabled {
                anyEnabled := true
                break
            }
        }

        if (grp.Length = 1) {
            b := grp[1]
            handler := (b.type = "action") ? RegisterActionHandler(b) : RegisterImageHandler(b)
            hotkeyHandlers[rk] := handler
            try Hotkey(rk, handler, b.enabled ? "On" : "Off")
        } else {
            ; Набір — один handler, що відкриває меню
            capturedGrp := grp
            handler := (*) => OpenSetMenu(capturedGrp)
            hotkeyHandlers[rk] := handler
            try Hotkey(rk, handler, anyEnabled ? "On" : "Off")
        }
    }
    HotIf
}

; =====================================================================
;                    ШАБЛОН Binds.txt ЗА ЗАМОВЧУВАННЯМ
; =====================================================================
DefaultBindsTemplate() {
    return "
    (
; ====================== КОНФІГ БІНДІВ =======================
; ============================================================
; KEY підтримує і комбінації: KEY Ctrl+V, KEY Alt+F4, KEY Shift+Tab
; Щоб переглянути довідку стосовно біндера, натисніть в треї
; на іконку біндера ПКМ, та оберіть "❓ Довідка".
; ============================================================

[F5] Представитись
(200)
KEY Enter
TEXT "/do На грудях висить бейдж: [LSPD | OPM | Zane Hellfire | 2500]."
KEY Enter

[Ctrl+F6] Приклад: комбінація як клавіша активації
(1000)
KEY Enter
TEXT "/me готовий до виконання наказу."
KEY Enter

[F6] Арешт OFF
(3000)
KEY F6
TEXT "/me Дістану КПК, заповню бланк арешту, передам слідчому."
KEY Enter
WAIT 500
KEY F6
TEXT "/do Бланк арешту заповнений, на столі у слідчого."
KEY Enter

[F7] Статті OFF
IMG "https://dasv.me/lspdq/codes.png"
(0,0)

[F8] Процесуальний кодекс
IMG "https://dasv.me/lspdq/procedural.png"
(50,50,180)

[F9] Статті Padre Navarro
IMG "https://i.ibb.co/d4z2yXhj/image.png"
(0,0,255,70)
    )"
}

; =====================================================================
;                          ПАРСЕР Binds.txt
; =====================================================================
ParseBinds(path) {
    text := FileRead(path, "UTF-8")
    rawLines := StrSplit(text, "`n", "`r")

    ; прибираємо коментарі й пусті рядки, зберігаючи порядок
    lines := []
    for line in rawLines {
        t := Trim(line)
        if (t = "" || SubStr(t, 1, 1) = ";")
            continue
        lines.Push(t)
    }

    binds := []
    i := 1
    n := lines.Length

    while (i <= n) {
        line := lines[i]
        if !RegExMatch(line, "^\[(.+?)\](.*)$", &m) {
            i++
            continue
        }
        key := m[1]
        name := Trim(m[2])
        enabled := true
        if RegExMatch(name, "i)\s+OFF$") {
            enabled := false
            name := Trim(SubStr(name, 1, StrLen(name) - 4))
        } else if (name = "OFF" || name = "off") {
            enabled := false
            name := ""
        }
        i++
        if (i > n)
            break

        ; --- бінд-картинка ---
        if RegExMatch(lines[i], '^IMG\s+"(.+)"$', &mImg) {
            url := mImg[1]
            i++
            x := 0, y := 0, opacity := 255, scale := 100
            if (i <= n) && RegExMatch(lines[i], "^\(\s*(-?\d*)\s*,\s*(-?\d*)\s*(?:,\s*(\d*)\s*(?:,\s*(\d+)\s*)?)?\)$", &mPos) {
                if (Trim(mPos[1]) != "")
                    x := Integer(mPos[1])
                if (Trim(mPos[2]) != "")
                    y := Integer(mPos[2])
                if (mPos.Count >= 3 && Trim(mPos[3]) != "")
                    opacity := Integer(mPos[3])
                if (mPos.Count >= 4 && Trim(mPos[4]) != "")
                    scale := Integer(mPos[4])
                i++
            }
            binds.Push({ type: "image", key: key, name: name, enabled: enabled, url: url, x: x, y: y, opacity: opacity, scale: scale })
            continue
        }

        ; --- бінд-дія (послідовність кроків) ---
        cooldown := 1000
        if (i <= n) && RegExMatch(lines[i], "^\(\s*(\d+)\s*\)$", &mCd) {
            cooldown := Integer(mCd[1])
            i++
        }

        steps := []
        while (i <= n) && !RegExMatch(lines[i], "^\[.+?\]") {
            stepLine := lines[i]
            if RegExMatch(stepLine, "i)^KEY\s+(.+)$", &mKey)
                steps.Push({ action: "key", value: Trim(mKey[1]) })
            else if RegExMatch(stepLine, 'i)^TEXT\s+"(.*)"$', &mTxt)
                steps.Push({ action: "text", value: mTxt[1] })
            else if RegExMatch(stepLine, "i)^WAIT\s+(\d+)$", &mWait)
                steps.Push({ action: "wait", value: Integer(mWait[1]) })
            i++
        }
        binds.Push({ type: "action", key: key, name: name, enabled: enabled, cooldown: cooldown, steps: steps })
    }
    return binds
}

; =====================================================================
;         ПАРСИНГ КОМБІНАЦІЙ КЛАВІШ ДЛЯ KEY-КРОКІВ (Ctrl+V, Alt+F4...)
; =====================================================================
; У Binds.txt можна писати "KEY Ctrl+V", "KEY Alt+F4", "KEY Shift+Tab",
; "KEY Ctrl+Shift+Esc" і т.д. Модифікатори: Ctrl/Control, Alt,
; Shift, Win/Windows. Регістр не важливий. Символи [ ] ; ' та подібні
; як фінальна клавіша в комбінації теж підтримуються (напр. "Ctrl+[").
KeyComboModSymbol(name) {
    switch StrLower(Trim(name)) {
        case "ctrl", "control": return "^"
        case "alt": return "!"
        case "shift": return "+"
        case "win", "windows", "lwin", "rwin": return "#"
    }
    return "" ; невідомий модифікатор - просто ігнорується
}

; Перетворює назву однієї клавіші у безпечний для Send() токен.
; Одиночні "звичайні" символи шлються напряму (v, [, ], ;),
; а іменовані клавіші (Enter, F1...) та спецсимволи Send (^ + ! # { })
; обов'язково загортаються у фігурні дужки, щоб не зламати синтаксис.
SendableKeyToken(key) {
    if (key = "{")
        return "{{}"
    if (key = "}")
        return "{}}"
    if (StrLen(key) = 1 && !InStr("^+!#", key))
        return key
    return "{" key "}"
}

; Перетворює весь текст кроку ("V" або "Ctrl+Shift+V") в готовий рядок
; для Send().
ParseKeyCombo(value) {
    parts := StrSplit(value, "+")
    if (parts.Length <= 1)
        return SendableKeyToken(Trim(value))

    keyPart := Trim(parts[parts.Length])
    modPart := ""
    Loop parts.Length - 1
        modPart .= KeyComboModSymbol(parts[A_Index])
    return modPart SendableKeyToken(keyPart)
}

; =====================================================================
;                       ВИКОНАННЯ БІНД-ДІЙ
; =====================================================================
SafeSleep(timeMs) {
    global stopBind
    end := A_TickCount + timeMs
    while (A_TickCount < end) {
        if stopBind
            return false
        Sleep(15)
    }
    return true
}

RunActionBind(b) {
    global lastUsed, bindBusy, stopBind
    now := A_TickCount
    key := b.key

    if lastUsed.Has(key) {
        elapsed := now - lastUsed[key]
        if (elapsed < b.cooldown) {
            remain := Round((b.cooldown - elapsed) / 1000, 1)
            ToolTip("КД: ще " remain " сек.")
            SetTimer(() => ToolTip(), -800)
            return
        }
    }

    ; захист від накладання: якщо вже виконується інший бінд-дія
    ; (наприклад, довгий з паузами WAIT), не даємо другому стартувати
    ; одночасно - інакше обидва одночасно чіпають A_Clipboard і можуть
    ; зіпсувати один одному вставлений текст.
    if bindBusy {
        ToolTip("Зачекай - виконується інший бінд...")
        SetTimer(() => ToolTip(), -800)
        return
    }

    lastUsed[key] := now
    bindBusy := true
    stopBind := false
    oldClip := ClipboardAll()
    needRestore := false

    try {
        for step in b.steps {
            if stopBind
                break
            if (step.action = "key") {
                Send(ParseKeyCombo(step.value))
                if !SafeSleep(30)
                    break
            } else if (step.action = "text") {
                A_Clipboard := step.value
                if ClipWait(1) {
                    Send("^v")
                    needRestore := true
                    if !SafeSleep(150)
                        break
                }
            } else if (step.action = "wait") {
                if !SafeSleep(step.value)
                    break
            }
        }
    } finally {
        if needRestore
            A_Clipboard := oldClip
        bindBusy := false
    }
}

; =====================================================================
;                  ВИЗНАЧЕННЯ ТИПУ ФАЙЛУ ЗА СИГНАТУРОЮ
; =====================================================================
DetectFileType(path) {
    try {
        f := FileOpen(path, "r")
        if !f
            return "unknown"
        buf := Buffer(12, 0)
        f.RawRead(buf, 12)
        f.Close()
    } catch {
        return "unknown"
    }

    b0 := NumGet(buf, 0, "UChar")
    b1 := NumGet(buf, 1, "UChar")
    b2 := NumGet(buf, 2, "UChar")
    b3 := NumGet(buf, 3, "UChar")

    if (b0 = 0x89 && b1 = 0x50 && b2 = 0x4E && b3 = 0x47)
        return "png"
    if (b0 = 0xFF && b1 = 0xD8)
        return "jpeg"
    if (b0 = 0x47 && b1 = 0x49 && b2 = 0x46)
        return "gif"
    if (b0 = 0x52 && b1 = 0x49 && b2 = 0x46 && b3 = 0x46)
        return "webp"
    if (b0 = 0x3C)
        return "html"
    return "unknown"
}

; =====================================================================
;              КЕШ КАРТИНОК: ІМ'Я ФАЙЛУ ЗАЛЕЖИТЬ ВІД URL
; =====================================================================
; Раніше кеш називався cache_<клавіша>.png - це значило, що зміна
; посилання в Binds.txt не оновлювала картинку (лишався старий кеш),
; а деякі клавіші (напр. "[" та "]") після очистки не-буквенних
; символів перетворювались на однакову назву файлу і могли
; конфліктувати. Тепер ім'я файлу залежить від самого URL - інший
; URL = інший файл, той самий URL = той самий файл (кеш працює).
CacheFileName(url) {
    h := 5381
    Loop Parse, url
        h := (h * 33 + Ord(A_LoopField)) & 0xFFFFFFFF
    return "cache_" Format("{:08X}", h) ".png"
}

; Прибирає файли кешу, які не належать жодному з поточних IMG-біндів
; (лишились від видалених/змінених біндів). Валідні картинки НЕ чіпає,
; тому не треба перекачувати все з нуля при кожному запуску.
PruneOrphanedCache(binds) {
    keep := Map()
    for b in binds {
        if (b.type = "image")
            keep[CacheFileName(b.url)] := true
    }
    Loop Files, A_ScriptDir "\cache_*.png" {
        if !keep.Has(A_LoopFileName)
            try FileDelete(A_LoopFileFullPath)
    }
}

; =====================================================================
;                       ВИКОНАННЯ БІНД-КАРТИНОК
; =====================================================================
ToggleImageBind(b) {
    global imageGuis
    key := b.key

    if imageGuis.Has(key) {
        try imageGuis[key].Destroy()
        imageGuis.Delete(key)
        return
    }

    localPath := A_ScriptDir "\" CacheFileName(b.url)

    ; якщо кеш вже є, але биткий (лишився зі старих спроб) - видаляємо і качаємо заново
    if FileExist(localPath) && !IsValidImage(localPath) {
        try FileDelete(localPath)
    }

    if !FileExist(localPath) {
        if !DownloadAndValidate(b.url, localPath, key)
            return
    }

    try {
        myGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20")
        myGui.MarginX := 0
        myGui.MarginY := 0
        myGui.BackColor := "000000"
        pic := myGui.Add("Picture", "x0 y0", localPath)

        if (b.HasProp("scale") && b.scale != 100) {
            pic.GetPos(,, &origW, &origH)
            pic.Move(,, Round(origW * b.scale / 100), Round(origH * b.scale / 100))
        }

        myGui.Show("x" b.x " y" b.y " AutoSize NA")

        transStr := "000000"
        if (b.opacity < 255)
            transStr .= " " b.opacity
        WinSetTransColor(transStr, myGui)

        imageGuis[key] := myGui
    } catch as e {
        ToolTip("Не вдалось показати картинку: " e.Message)
        SetTimer(() => ToolTip(), -3500)
        try FileDelete(localPath)
    }
}

; ===================================================================
;   Глобальний стан меню вибору набору
; ===================================================================

; Закриває меню вибору: знімає хоткеї, WM_ACTIVATE, GUI
CloseSetMenu() {
    global setMenuState
    OnMessage(0x0006, SetMenuDeactivate, 0)
    setMenuState["enabled"] := []
    if IsObject(setMenuState["gui"]) {
        try setMenuState["gui"].Destroy()
        setMenuState["gui"] := 0
    }
}

; WM_ACTIVATE handler — закриває меню при деактивації вікна
SetMenuDeactivate(wParam, lParam, msg, hwnd) {
    global setMenuState
    g := setMenuState["gui"]
    if IsObject(g) && (hwnd = g.Hwnd) && ((wParam & 0xFFFF) = 0)
        SetTimer(CloseSetMenu, -1)
}

; =====================================================================
;              МЕНЮ ВИБОРУ ДЛЯ НАБОРУ БІНДІВ (кілька на одній клавіші)
; =====================================================================
OpenSetMenu(grp) {
    global setMenuState

    ; Закриваємо попереднє меню, якщо відкрите
    CloseSetMenu()

    ; Фільтруємо лише увімкнені бінди (максимум 10)
    enabled := []
    for b in grp {
        if b.enabled {
            enabled.Push(b)
            if (enabled.Length = 10)
                break
        }
    }
    if (enabled.Length = 0)
        return

    ; Якщо лише один увімкнений — виконуємо одразу без меню
    if (enabled.Length = 1) {
        b := enabled[1]
        if (b.type = "action")
            RunActionBind(b)
        else
            ToggleImageBind(b)
        return
    }
    setMenuState["enabled"] := enabled

    menuGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Border +E0x20 +E0x08000000")
    menuGui.BackColor := "191919"

    btnW := 400
    btnH := 36
    padX := 12
    padY := 10
    gap  := 5

    ; Заголовок
    menuGui.SetFont("s9 c888888", "Segoe UI")
    menuGui.Add("Text", "x" padX " y" padY " w" btnW " Center", "Оберіть дію (Esc — скасувати)")
    yPos := padY + 22

    for idx, b in enabled {
        numLabel := "[" (idx = 10 ? 0 : idx) "]"
        name     := b.HasProp("name") && Trim(b.name) != "" ? b.name : b.key
        label    := numLabel " | " name
        btn := menuGui.Add("Text",
            "x" padX " y" yPos " w" btnW " h" btnH
            " Background222222 +0x200 Border",
            "  " label)
        btn.SetFont("s10 cAFAFAF", "Segoe UI")
        HoverBtn(btn, "222222", "1A4080")

        capturedB := b
        clickFn := MakeSetMenuClickHandler(capturedB)
        btn.OnEvent("Click", clickFn)

        yPos += btnH + gap
    }

    ; Розміщення: між центром екрану та низом
    menuW := btnW + padX * 2
    menuH := yPos + padY
    scrW  := SysGet(0)
    scrH  := SysGet(1)
    posX  := (scrW - menuW) // 2
    posY  := (scrH // 2 + scrH) // 2 - menuH // 2

    menuGui.Show("x" posX " y" posY " w" menuW " h" menuH " NA")
    WinSetTransparent(178, menuGui)  ; ~70% непрозорості (255 = повністю)
    setMenuState["gui"] := menuGui

    ; Esc закриває меню
    menuGui.OnEvent("Escape", (*) => CloseSetMenu())

    ; Закриваємо по деактивації вікна (WM_ACTIVATE)
    OnMessage(0x0006, SetMenuDeactivate)
}

MakeSetMenuClickHandler(b) {
    return (*) => RunSetMenuBind(b)
}

MakeSetMenuKeyHandler(idx) {
    return (*) => RunSetMenuByIndex(idx)
}

RunSetMenuBind(b) {
    CloseSetMenu()
    if b.type = "action"
        RunActionBind(b)
    else
        ToggleImageBind(b)
}

RunSetMenuByIndex(idx) {
    global setMenuState
    enabled := setMenuState["enabled"]
    if (idx <= enabled.Length) {
        b := enabled[idx]
        CloseSetMenu()
        if b.type = "action"
            RunActionBind(b)
        else
            ToggleImageBind(b)
    }
}
IsValidImage(path) {
    t := DetectFileType(path)
    return (t = "png" || t = "jpeg" || t = "gif" || t = "webp")
}

DownloadAndValidate(url, localPath, key) {
    ToolTip("Завантажую картинку...")
    try {
        Download(url, localPath)
    } catch as e {
        ToolTip("Помилка завантаження: " e.Message)
        SetTimer(() => ToolTip(), -2500)
        return false
    }
    ToolTip()

    if !FileExist(localPath) || FileGetSize(localPath) = 0 {
        ToolTip("Файл картинки порожній - перевір посилання в Binds.txt")
        SetTimer(() => ToolTip(), -3000)
        try FileDelete(localPath)
        return false
    }

    if !IsValidImage(localPath) {
        detected := DetectFileType(localPath)
        preview := ""
        try {
            f := FileOpen(localPath, "r")
            preview := f.Read(300)
            f.Close()
        }
        try FileDelete(localPath)
        MsgBox(
            "Посилання для [" key "] не віддає картинку напряму.`n"
            "Сервер повернув: " (detected = "html" ? "HTML-сторінку (можливо захист від гарячого лінкування)" : "невідомі дані") ".`n`n"
            "Початок відповіді:`n" preview,
            "Проблема з картинкою",
            "Icon!"
        )
        return false
    }
    return true
}

; Безпечний парсинг цілого числа з поля вводу - якщо там не число
; (наприклад випадково вписана літера), повертає значення за
; замовчуванням замість необробленого краху програми.
SafeInt(val, default) {
    val := Trim(val)
    if RegExMatch(val, "^-?\d+$")
        return Integer(val)
    return default
}

; =====================================================================
;               ЕФЕКТ НАВЕДЕННЯ ДЛЯ КНОПОК (Text-контроли)
; =====================================================================
; Реєструє контрол як кнопку з hover-підсвіткою.
; normalBg — колір у спокої, hoverBg — колір при наведенні.
HoverBtn(ctrl, normalBg := "333333", hoverBg := "1A3A6A") {
    global hoverBtns
    hoverBtns[ctrl.Hwnd] := Map("ctrl", ctrl, "normalBg", normalBg, "hoverBg", hoverBg, "active", false)
}

; Скидає підсвічування всіх кнопок крім виключення (або всіх, якщо exceptHwnd = 0)
_ResetAllHoverBtns(exceptHwnd := 0) {
    global hoverBtns
    for h, info in hoverBtns {
        if (h = exceptHwnd)
            continue
        if info["active"] {
            try info["ctrl"].Opt("Background" info["normalBg"])
            try DllCall("InvalidateRect", "Ptr", h, "Ptr", 0, "Int", 1)
            info["active"] := false
        }
    }
}

_BtnMouseMove(wParam, lParam, msg, hwnd) {
    global hoverBtns
    if !hoverBtns.Has(hwnd) {
        ; Курсор над іншим вікном — скидаємо всі активні кнопки
        _ResetAllHoverBtns()
        return
    }
    ; Скидаємо всі інші кнопки перед підсвічуванням поточної
    _ResetAllHoverBtns(hwnd)
    info := hoverBtns[hwnd]
    if !info["active"] {
        info["ctrl"].Opt("Background" info["hoverBg"])
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
        info["active"] := true
        ; Просимо WM_MOUSELEAVE, коли курсор покине контрол
        tme := Buffer(16, 0)
        NumPut("UInt", 16,   tme, 0)
        NumPut("UInt", 2,    tme, 4)   ; TME_LEAVE
        NumPut("Ptr",  hwnd, tme, 8)
        DllCall("TrackMouseEvent", "Ptr", tme)
    }
}

_BtnMouseLeave(wParam, lParam, msg, hwnd) {
    global hoverBtns
    if !hoverBtns.Has(hwnd)
        return
    info := hoverBtns[hwnd]
    try info["ctrl"].Opt("Background" info["normalBg"])
    try DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    info["active"] := false
}

; =====================================================================
;                       РЕДАКТОР БІНДІВ (GUI)
; =====================================================================

OpenBindEditor(*) {
    global BindsFile
    static editorGui := 0
    if (IsObject(editorGui)) {
        try {
            editorGui.Show()
            return
        }
    }

    editorBinds := ParseBinds(BindsFile)

    editorGui := Gui("+Resize", "LSPD Binder | Редактор біндів")
    SetDarkMode(editorGui.Hwnd)
    editorGui.BackColor := "191919"
    editorGui.SetFont("s10 cAFAFAF q5", "Segoe UI")
    editorGui.OnEvent("Close", (*) => (editorGui := 0, editorGuiCtx := 0))
    editorGui.OnEvent("Size", EditorGuiResize)

    iconPath := FileExist(A_ScriptDir "\icon.ico") ? A_ScriptDir "\icon.ico" : A_ScriptFullPath
    try editorGui.Add("Picture", "x16 y12 w44 h44", iconPath)

    editorGui.SetFont("s13 Bold cAFAFAF", "Segoe UI")
    editorGui.Add("Text", "x70 y10 w500", "Редактор біндів")

    global editorBtnSuspend
    editorBtnSuspend := editorGui.Add("Text", "x636 y450 w196 h32 Background333333 Center +0x200 Border", A_IsSuspended ? "▶️ Відновити біндер" : "⏹️ Призупинити біндер")
    editorBtnSuspend.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    editorBtnSuspend.OnEvent("Click", (*) => ToggleSuspend())

    editorGui.SetFont("s10 Norm cAFAFAF", "Segoe UI")
    editorGui.Add("Text", "x70 y36 w750", "Вибери бінд зі списку або додай новий")

    editorGui.SetFont("s10 cAFAFAF", "Segoe UI")
    lv := editorGui.Add("ListView", "x16 y66 w818 h367 -Multi +LV0x10 +Checked -Grid Background191919 cAFAFAF vBindList", ["Клавіша", "Назва", "Тип", "Опис"])

    ; Темна тема для ListView та заголовку
    DllCall("uxtheme\SetWindowTheme", "ptr", lv.Hwnd, "str", "DarkMode_ItemsView", "ptr", 0)

    ; Темна тема для заголовку (SysHeader32 — окремий контрол)
    hHeader := SendMessage(0x101F, 0, 0, lv.Hwnd) ; LVM_GETHEADER
    DllCall("uxtheme\SetWindowTheme", "ptr", hHeader, "str", "DarkMode_ItemsView", "ptr", 0)

    ; Лише потрібні розширені стилі (без LVS_EX_GRIDLINES)
    SendMessage(0x1036, 0xFFFFFFFF, 0x4 | 0x20 | 0x10000, lv.Hwnd) ; CHECKBOXES | FULLROWSELECT | DOUBLEBUFFER

    lv.ModifyCol(1, 65)
    lv.ModifyCol(2, 170)
    lv.ModifyCol(3, 70)
    lv.ModifyCol(4, 509)

    btnAdd  := editorGui.Add("Text", "x16 y450 w120 h32 Background333333 Center +0x200 Border", "➕ Додати")
    btnEdit := editorGui.Add("Text", "x146 y450 w120 h32 Background333333 Center +0x200 Border", "✏️ Редагувати")
    btnDel  := editorGui.Add("Text", "x276 y450 w120 h32 Background333333 Center +0x200 Border", "🗑️ Видалити")
    btnDup  := editorGui.Add("Text", "x406 y450 w120 h32 Background333333 Center +0x200 Border", "📋 Дублювати")
    btnHelp := editorGui.Add("Text", "x714 y20 w120 h32 Background333333 Center +0x200 Border", "❓ Довідка")
    for btn in [btnAdd, btnEdit, btnDel, btnDup, btnHelp]
        btn.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    for btn in [btnAdd, btnEdit, btnDel, btnDup, btnHelp, editorBtnSuspend]
        HoverBtn(btn)

    global editorGuiCtx
    ctx := Map()
    ctx["binds"]  := editorBinds
    ctx["lv"]     := lv
    ctx["gui"]    := editorGui
    ctx["file"]   := BindsFile
    editorGuiCtx  := ctx

    EditorRefreshList(ctx)

    lv.OnEvent("DoubleClick", (ctrl, row) => (row > 0 ? EditorOpenEdit(ctx, row) : 0))
    lv.OnEvent("ItemCheck", EditorItemCheck.Bind(ctx))
    lv.OnNotify(-109, EditorDragDrop.Bind(ctx))
    btnAdd.OnEvent("Click",  (*) => EditorOpenAdd(ctx))
    btnEdit.OnEvent("Click", (*) => EditorBtnEdit(ctx))
    btnDel.OnEvent("Click",  (*) => EditorBtnDel(ctx))
    btnDup.OnEvent("Click",  (*) => EditorBtnDup(ctx))
    btnHelp.OnEvent("Click", (*) => OpenHelpWindow())

    EditorGuiResize(thisGui, minMax, width, height) {
        if (minMax = -1)
            return
        lv.Move(,, width - 32, height - 133)
        btnAdd.Move(16,           height - 50)
        btnEdit.Move(146,         height - 50)
        btnDel.Move(276,          height - 50)
        btnDup.Move(406,          height - 50)
        btnHelp.Move(width - 136, 20)

        global editorBtnSuspend
        if (IsObject(editorBtnSuspend))
            editorBtnSuspend.Move(width - 212, height - 50)
    }

    editorGui.Show("w850 h500")
}

EditorRefreshList(ctx) {
    lv := ctx["lv"]
    lv.Delete()
    for b in ctx["binds"] {
        name := b.HasProp("name") ? b.name : ""
        if (b.type = "action") {
            desc := ""
            for s in b.steps {
                if (s.action = "text")
                    desc .= s.value " | "
                else if (s.action = "key")
                    desc .= "[" s.value "] "
                else if (s.action = "wait")
                    desc .= "WAIT(" s.value "ms) "
            }
            desc := RTrim(desc, " |")
            lv.Add(b.enabled ? "Check" : "", b.key, name, "Дія", desc)
        } else {
            lv.Add(b.enabled ? "Check" : "", b.key, name, "Картинка", b.url)
        }
    }
}

EditorItemCheck(ctx, ctrl, item, checked) {
    EditorPushHistory(ctx)
    ctx["binds"][item].enabled := checked
    EditorSaveQuiet(ctx)
}

EditorParseSteps(rawText, &outCooldown, &outSteps) {
    outCooldown := 1000
    outSteps := []
    for ln in StrSplit(rawText, "`n", "`r") {
        t := Trim(ln)
        if (t = "")
            continue
        if RegExMatch(t, "^\(\s*(\d+)\s*\)$", &m)
            outCooldown := Integer(m[1])
        else if RegExMatch(t, "i)^KEY\s+(.+)$", &m)
            outSteps.Push({ action: "key", value: Trim(m[1]) })
        else if RegExMatch(t, 'i)^TEXT\s+"(.*)"$', &m)
            outSteps.Push({ action: "text", value: m[1] })
        else if RegExMatch(t, "i)^WAIT\s+(\d+)$", &m)
            outSteps.Push({ action: "wait", value: Integer(m[1]) })
    }
}

EditorStepsToText(b) {
    t := ""
    if (b.cooldown != 1000)
        t .= "(" b.cooldown ")`n"
    for s in b.steps {
        if (s.action = "key")
            t .= "KEY " s.value "`n"
        else if (s.action = "text")
            t .= "TEXT `"" s.value "`"`n"
        else if (s.action = "wait")
            t .= "WAIT " s.value "`n"
    }
    return t
}

EditorBtnEdit(ctx) {
    row := ctx["lv"].GetNext(0)
    if (row = 0) {
        return
    }
    EditorOpenEdit(ctx, row)
}

global UndoStack := []
global RedoStack := []
global SkipDeleteConfirm := false

EditorPushHistory(ctx) {
    global UndoStack, RedoStack
    cloneArr := []
    for b in ctx["binds"]
        cloneArr.Push(CloneBind(b))
    UndoStack.Push(cloneArr)
    if (UndoStack.Length > 50)
        UndoStack.RemoveAt(1)
    RedoStack := []
}

EditorUndo(ctx) {
    global UndoStack, RedoStack
    if (UndoStack.Length == 0)
        return
    currentArr := []
    for b in ctx["binds"]
        currentArr.Push(CloneBind(b))
    RedoStack.Push(currentArr)

    prevState := UndoStack.Pop()
    ctx["binds"] := prevState
    EditorRefreshList(ctx)
    EditorSaveQuiet(ctx)
}

EditorRedo(ctx) {
    global UndoStack, RedoStack
    if (RedoStack.Length == 0)
        return
    currentArr := []
    for b in ctx["binds"]
        currentArr.Push(CloneBind(b))
    UndoStack.Push(currentArr)

    nextState := RedoStack.Pop()
    ctx["binds"] := nextState
    EditorRefreshList(ctx)
    EditorSaveQuiet(ctx)
}

EditorBtnDel(ctx) {
    global SkipDeleteConfirm
    row := ctx["lv"].GetNext(0)
    if (row = 0) {
        return
    }
    key := ctx["binds"][row].key

    if (!SkipDeleteConfirm) {
        msgGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Border +Owner" ctx["gui"].Hwnd, "Підтвердження видалення")
        SetDarkMode(msgGui.Hwnd)
        msgGui.BackColor := "191919"
        msgGui.SetFont("s10 cAFAFAF", "Segoe UI")
        msgGui.Add("Text", "x15 y15 w250 Center", "Видалити бінд [" key "]?")
        cb := msgGui.Add("Checkbox", "x15 y45 w250 cAFAFAF", "Запам'ятати мій вибір")
        btnYes := msgGui.Add("Text", "x20 y75 w100 h28 Background333333 Center +0x200 Border", "Так")
        btnNo := msgGui.Add("Text", "x160 y75 w100 h28 Background333333 Center +0x200 Border", "Ні")
        HoverBtn(btnYes)
        HoverBtn(btnNo)
        res := ""
        btnYes.OnEvent("Click", (*) => (res := "Yes", SkipDeleteConfirm := cb.Value, msgGui.Destroy()))
        btnNo.OnEvent("Click", (*) => (res := "No", msgGui.Destroy()))
        msgGui.Show("w280 h115")
        WinWaitClose(msgGui.Hwnd)
        if (res != "Yes")
            return
    }

    EditorPushHistory(ctx)
    ctx["binds"].RemoveAt(row)
    EditorRefreshList(ctx)
    EditorSaveQuiet(ctx)
}

global CopiedBind := 0

CloneBind(b) {
    nb := b.Clone()
    if (nb.type = "action" && nb.HasProp("steps")) {
        nb.steps := []
        for s in b.steps
            nb.steps.Push(s.Clone())
    }
    return nb
}

EditorBtnDup(ctx) {
    row := ctx["lv"].GetNext(0)
    if (row = 0)
        return
    EditorPushHistory(ctx)
    b := ctx["binds"][row]
    newBind := CloneBind(b)
    ctx["binds"].InsertAt(row + 1, newBind)
    EditorRefreshList(ctx)
    EditorSaveQuiet(ctx)
    ctx["lv"].Modify(0, "-Select")
    ctx["lv"].Modify(row + 1, "Select Vis Focus")
}

EditorBtnCopy(ctx) {
    global CopiedBind
    row := ctx["lv"].GetNext(0)
    if (row = 0)
        return
    b := ctx["binds"][row]
    CopiedBind := CloneBind(b)
}

EditorBtnPaste(ctx) {
    global CopiedBind
    if !IsObject(CopiedBind)
        return
    EditorPushHistory(ctx)
    newBind := CloneBind(CopiedBind)

    row := ctx["lv"].GetNext(0)
    if (row > 0) {
        ctx["binds"].InsertAt(row + 1, newBind)
        targetRow := row + 1
    } else {
        ctx["binds"].Push(newBind)
        targetRow := ctx["binds"].Length
    }
    EditorRefreshList(ctx)
    EditorSaveQuiet(ctx)
    ctx["lv"].Modify(0, "-Select")
    ctx["lv"].Modify(targetRow, "Select Vis Focus")
}

EditorDragDrop(ctx, ctrl, lParam) {
    lv := ctx["lv"]
    dragRow := lv.GetNext(0, "Focused")
    if (dragRow = 0)
        return

    rowText := " ☰  " lv.GetText(dragRow, 1) " — " lv.GetText(dragRow, 2) "  "
    if (StrLen(rowText) > 40)
        rowText := SubStr(rowText, 1, 40) "..."

    ghost := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20")
    ghost.BackColor := "191919"
    ghost.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    ghost.Add("Text", "x0 y4", rowText)
    WinSetTransparent(210, ghost)

    LVM_SETINSERTMARK := 0x10A6
    lvim := Buffer(16, 0)
    NumPut("UInt", 16, lvim, 0)

    POINT := Buffer(8)
    LVHITTESTINFO := Buffer(24, 0)

    While GetKeyState("LButton", "P") {
        Sleep(10)
        DllCall("GetCursorPos", "Ptr", POINT)
        mX := NumGet(POINT, 0, "Int")
        mY := NumGet(POINT, 4, "Int")

        try ghost.Show("x" (mX + 15) " y" (mY + 15) " NA AutoSize")

        DllCall("ScreenToClient", "Ptr", lv.Hwnd, "Ptr", POINT)
        cX := NumGet(POINT, 0, "Int")
        cY := NumGet(POINT, 4, "Int")

        NumPut("Int", cX, LVHITTESTINFO, 0)
        NumPut("Int", cY, LVHITTESTINFO, 4)

        target := SendMessage(0x1012, 0, LVHITTESTINFO.Ptr, lv.Hwnd)
        if (target >= 0) {
            NumPut("UInt", 0, lvim, 4)
            NumPut("Int", target, lvim, 8)
        } else if (cY > 0) {
            NumPut("UInt", 1, lvim, 4)
            NumPut("Int", ctx["binds"].Length - 1, lvim, 8)
        } else {
            NumPut("UInt", 0, lvim, 4)
            NumPut("Int", 0, lvim, 8)
        }
        SendMessage(LVM_SETINSERTMARK, 0, lvim.Ptr, lv.Hwnd)
    }

    NumPut("Int", -1, lvim, 8)
    SendMessage(LVM_SETINSERTMARK, 0, lvim.Ptr, lv.Hwnd)
    try ghost.Destroy()

    DllCall("GetCursorPos", "Ptr", POINT)
    DllCall("ScreenToClient", "Ptr", lv.Hwnd, "Ptr", POINT)
    cY := NumGet(POINT, 4, "Int")

    NumPut("Int", NumGet(POINT, 0, "Int"), LVHITTESTINFO, 0)
    NumPut("Int", cY, LVHITTESTINFO, 4)
    target := SendMessage(0x1012, 0, LVHITTESTINFO.Ptr, lv.Hwnd)

    finalTarget := 0
    if (target >= 0) {
        finalTarget := target + 1
    } else if (cY > 0) {
        finalTarget := ctx["binds"].Length + 1
    } else {
        finalTarget := 1
    }

    if (finalTarget > 0 && finalTarget != dragRow && finalTarget != dragRow + 1) {
        EditorPushHistory(ctx)
        if (finalTarget > ctx["binds"].Length)
            finalTarget := ctx["binds"].Length + 1
        temp := ctx["binds"][dragRow]
        ctx["binds"].RemoveAt(dragRow)
        if (dragRow < finalTarget)
            finalTarget--
        ctx["binds"].InsertAt(finalTarget, temp)
        EditorRefreshList(ctx)
        lv.Modify(finalTarget, "Select Focus")
        EditorSaveQuiet(ctx)
    }
}
EditorSaveQuiet(ctx) {
    out := ""
    for b in ctx["binds"] {
        namePart := (b.HasProp("name") && Trim(b.name) != "") ? " " Trim(b.name) : ""
        offPart := b.enabled ? "" : " OFF"
        out .= "[" b.key "]" namePart offPart "`n"
        if (b.type = "action") {
            if (b.cooldown != 1000)
                out .= "(" b.cooldown ")`n"
            for s in b.steps {
                if (s.action = "key")
                    out .= "KEY " s.value "`n"
                else if (s.action = "text")
                    out .= "TEXT `"" s.value "`"`n"
                else if (s.action = "wait")
                    out .= "WAIT " s.value "`n"
            }
        } else {
            out .= "IMG `"" b.url "`"`n"
            opStr := "(" b.x "," b.y
            if (b.HasProp("scale") && b.scale != 100)
                opStr .= "," b.opacity "," b.scale
            else if (b.opacity != 255)
                opStr .= "," b.opacity
            opStr .= ")"
            out .= opStr "`n"
        }
        out .= "`n"
    }
    try {
        FileDelete(ctx["file"])
        FileAppend(out, ctx["file"], "UTF-8")
        ApplyBinds(ctx["binds"])
    } catch as e {
        MsgBox("Помилка збереження: " e.Message, "Помилка", "Icon!")
    }
}

EditorEditActionOk(ctx, bindIdx, win, nameEdit, keyEdit, nativeCb, stepsBox, *) {
    newKey := (nativeCb.Value ? "~" : "") keyEdit.Value
    if (newKey = "" || newKey = "~") {
        MsgBox("Клавіша не може бути порожньою!", "Помилка", "Icon!")
        return
    }
    EditorParseSteps(stepsBox.Value, &cd, &steps)
    if (steps.Length = 0) {
        MsgBox("Бінд має містити хоча б один крок!", "Помилка", "Icon!")
        return
    }
    EditorPushHistory(ctx)
    ctx["binds"][bindIdx] := { type: "action", name: Trim(nameEdit.Value), key: newKey, enabled: ctx["binds"][bindIdx].enabled, cooldown: cd, steps: steps }
    EditorRefreshList(ctx)
    EditorSaveQuiet(ctx)
    win.Destroy()
}

EditorEditImageOk(ctx, bindIdx, win, nameEdit, keyEdit, nativeCb, urlEdit, xEdit, yEdit, opEdit, scEdit, *) {
    newKey := (nativeCb.Value ? "~" : "") keyEdit.Value
    if (newKey = "" || newKey = "~") {
        MsgBox("Клавіша не може бути порожньою!", "Помилка", "Icon!")
        return
    }
    newUrl := Trim(urlEdit.Value)
    if (newUrl = "") {
        MsgBox("URL не може бути порожнім!", "Помилка", "Icon!")
        return
    }
    nx  := SafeInt(xEdit.Value, 0)
    ny  := SafeInt(yEdit.Value, 0)
    nop := SafeInt(opEdit.Value, 255)
    nsc := SafeInt(scEdit.Value, 100)
    EditorPushHistory(ctx)
    ctx["binds"][bindIdx] := { type: "image", name: Trim(nameEdit.Value), key: newKey, enabled: ctx["binds"][bindIdx].enabled, url: newUrl, x: nx, y: ny, opacity: nop, scale: nsc }
    EditorRefreshList(ctx)
    EditorSaveQuiet(ctx)
    win.Destroy()
}

EditorOpenEdit(ctx, bindIdx) {
    b := ctx["binds"][bindIdx]
    win := Gui("+Owner" ctx["gui"].Hwnd " +ToolWindow", "Редагувати бінд [" b.key "]")
    SetDarkMode(win.Hwnd)
    win.BackColor := "191919"
    win.SetFont("s10 cAFAFAF", "Segoe UI")
    win.Add("Text", "x12 y12 cAFAFAF", "Назва бінду:")
    nameEdit := win.Add("Edit", "x12 y30 w150 Background333333 cAFAFAF", b.HasProp("name") ? b.name : "")

    win.Add("Text", "x172 y12 cAFAFAF", "Клавіша активац.:")
    cleanKey := b.key
    isNative := 0
    if SubStr(cleanKey, 1, 1) = "~" {
        isNative := 1
        cleanKey := SubStr(cleanKey, 2)
    }
    keyEdit := win.Add("Edit", "x172 y30 w100 Background333333 cAFAFAF", cleanKey)
    nativeCb := win.Add("Checkbox", "x285 y33 cAFAFAF Checked" isNative, "Не перехоплювати")

    if (b.type = "action") {
        win.Add("Text", "x12 y60 cAFAFAF", "Кроки (KEY, підтримує Ctrl+V / TEXT `"...`" / WAIT мс / (кд_мс)):")
        stepsBox := win.Add("Edit", "x12 y78 w500 h200 +Multi Background333333 cAFAFAF", EditorStepsToText(b))
        btnOk     := win.Add("Text", "x12 y290 w100 h28 Background333333 Center +0x200 Border", "✔ Зберегти")
        btnCancel := win.Add("Text", "x122 y290 w100 h28 Background333333 Center +0x200 Border", "❌ Скасувати")
        btnCancel.OnEvent("Click", (*) => win.Destroy())
        btnOk.OnEvent("Click", EditorEditActionOk.Bind(ctx, bindIdx, win, nameEdit, keyEdit, nativeCb, stepsBox))
        HoverBtn(btnOk)
        HoverBtn(btnCancel)
    } else {
        win.Add("Text", "x12 y60 cAFAFAF", "Посилання на зображення:")
        urlEdit := win.Add("Edit", "x12 y78 w500 Background333333 cAFAFAF", b.url)
        win.Add("Text", "x12 y108 cAFAFAF", "X відступ:")
        xEdit := win.Add("Edit", "x12 y126 w60 Background333333 cAFAFAF", b.x)
        win.Add("Text", "x92 y108 cAFAFAF", "Y відступ:")
        yEdit := win.Add("Edit", "x92 y126 w60 Background333333 cAFAFAF", b.y)
        win.Add("Text", "x172 y108 cAFAFAF", "Прозорість:")
        opEdit := win.Add("Edit", "x172 y126 w60 Background333333 cAFAFAF", b.opacity)
        win.Add("Text", "x252 y108 cAFAFAF", "Масштаб(%):")
        scEdit := win.Add("Edit", "x252 y126 w60 Background333333 cAFAFAF", b.HasProp("scale") ? b.scale : 100)
        btnOk     := win.Add("Text", "x12 y166 w100 h28 Background333333 Center +0x200 Border", "✔ Зберегти")
        btnCancel := win.Add("Text", "x122 y166 w100 h28 Background333333 Center +0x200 Border", "❌ Скасувати")
        btnCancel.OnEvent("Click", (*) => win.Destroy())
        btnOk.OnEvent("Click", EditorEditImageOk.Bind(ctx, bindIdx, win, nameEdit, keyEdit, nativeCb, urlEdit, xEdit, yEdit, opEdit, scEdit))
        HoverBtn(btnOk)
        HoverBtn(btnCancel)
    }
    win.Show("AutoSize")
}

EditorOpenAdd(ctx) {
    win := Gui("+Owner" ctx["gui"].Hwnd " +ToolWindow", "Додати новий бінд")
    SetDarkMode(win.Hwnd)
    win.BackColor := "191919"
    win.SetFont("s10 cAFAFAF", "Segoe UI")
    win.Add("Text", "x12 y12 cAFAFAF", "Назва бінду:")
    nameEdit := win.Add("Edit", "x12 y30 w150 Background333333 cAFAFAF", "")

    win.Add("Text", "x172 y12 cAFAFAF", "Клавіша активац.:")
    keyEdit := win.Add("Edit", "x172 y30 w100 Background333333 cAFAFAF", "F10")
    nativeCb := win.Add("Checkbox", "x285 y33 cAFAFAF Checked0", "Не перехоплювати")
    win.Add("Text", "x12 y62 cAFAFAF", "Тип бінду:")
    typeDD := win.Add("DropDownList", "x12 y80 w150 Background333333 cAFAFAF", ["Дія (текст/клавіші)", "Картинка (IMG)"])
    typeDD.Value := 1

    win.Add("Text", "x12 y114 vLblSteps cAFAFAF", "Кроки (KEY, підтримує Ctrl+V / TEXT `"...`" / WAIT мс / (кд_мс)):")
    stepsBox := win.Add("Edit", "x12 y132 w500 h160 +Multi vStepsBox Background333333 cAFAFAF", "(1000)`nKEY T`nTEXT `"/me текст тут`"`nKEY Enter")

    lblUrl := win.Add("Text",  "x12 y114 vLblUrl cAFAFAF",  "Посилання на зображення:")
    urlEdit := win.Add("Edit", "x12 y132 w500 vUrlEdit Background333333 cAFAFAF", "https://")
    lblX   := win.Add("Text",  "x12 y162 vLblX cAFAFAF",  "X відступ:")
    xEdit  := win.Add("Edit",  "x12 y180 w60 vXEdit Background333333 cAFAFAF",  "0")
    lblY   := win.Add("Text",  "x92 y162 vLblY cAFAFAF",  "Y відступ:")
    yEdit  := win.Add("Edit",  "x92 y180 w60 vYEdit Background333333 cAFAFAF", "0")
    lblOp  := win.Add("Text",  "x172 y162 vLblOp cAFAFAF",  "Прозорість:")
    opEdit := win.Add("Edit",  "x172 y180 w60 vOpEdit Background333333 cAFAFAF", "255")
    lblSc  := win.Add("Text",  "x252 y162 vLblSc cAFAFAF",  "Масштаб(%):")
    scEdit := win.Add("Edit",  "x252 y180 w60 vScEdit Background333333 cAFAFAF", "100")

    for ctrl in [lblUrl, urlEdit, lblX, xEdit, lblY, yEdit, lblOp, opEdit, lblSc, scEdit]
        ctrl.Visible := false

    imgCtrls := [lblUrl, urlEdit, lblX, xEdit, lblY, yEdit, lblOp, opEdit, lblSc, scEdit]
    typeDD.OnEvent("Change", EditorAddTypeChange.Bind(win, stepsBox, imgCtrls))

    btnOk     := win.Add("Text", "x12 y306 w100 h28 Background333333 Center +0x200 Border", "✔ Зберегти")
    btnCancel := win.Add("Text", "x122 y306 w100 h28 Background333333 Center +0x200 Border", "❌ Скасувати")
    btnCancel.OnEvent("Click", (*) => win.Destroy())
    btnOk.OnEvent("Click", EditorAddOk.Bind(ctx, win, nameEdit, keyEdit, nativeCb, typeDD, stepsBox, urlEdit, xEdit, yEdit, opEdit, scEdit))
    HoverBtn(btnOk)
    HoverBtn(btnCancel)
    win.Show("AutoSize")
}

EditorAddTypeChange(win, stepsBox, imgCtrls, ctrl, *) {
    isImg := (ctrl.Value = 2)
    stepsBox.Visible := !isImg
    win["LblSteps"].Visible := !isImg
    for c in imgCtrls
        c.Visible := isImg
}

EditorAddOk(ctx, win, nameEdit, keyEdit, nativeCb, typeDD, stepsBox, urlEdit, xEdit, yEdit, opEdit, scEdit, *) {
    newKey := Trim(keyEdit.Value)
    if nativeCb.Value
        newKey := "~" newKey
    if (newKey = "" || newKey = "~") {
        MsgBox("Клавіша не може бути порожньою!", "Помилка", "Icon!")
        return
    }
    EditorPushHistory(ctx)
    if (typeDD.Value = 1) {
        EditorParseSteps(stepsBox.Value, &cd, &steps)
        ctx["binds"].Push({ type: "action", name: Trim(nameEdit.Value), key: newKey, enabled: true, cooldown: cd, steps: steps })
    } else {
        newUrl := Trim(urlEdit.Value)
        if (newUrl = "" || newUrl = "https://") {
            MsgBox("URL не може бути порожнім!", "Помилка", "Icon!")
            return
        }
        nx  := SafeInt(xEdit.Value, 0)
        ny  := SafeInt(yEdit.Value, 0)
        nop := SafeInt(opEdit.Value, 255)
        nsc := SafeInt(scEdit.Value, 100)
        ctx["binds"].Push({ type: "image", name: Trim(nameEdit.Value), key: newKey, enabled: true, url: newUrl, x: nx, y: ny, opacity: nop, scale: nsc })
    }
    EditorRefreshList(ctx)
    EditorSaveQuiet(ctx)
    win.Destroy()
}

; =====================================================================
;                         ВІКНО ДОВІДКИ
; =====================================================================
OpenHelpWindow(*) {
    static helpGui := 0
    if (IsObject(helpGui)) {
        try {
            helpGui.Show()
            return
        }
    }

    helpGui := Gui("+Resize", "LSPD Binder | Довідка")
    SetDarkMode(helpGui.Hwnd)
    helpGui.BackColor := "191919"
    helpGui.OnEvent("Close", (*) => (helpGui := 0))

    page1Ctrls := []
    page2Ctrls := []
    page3Ctrls := []
    curPage := 1

    ; --- Заголовок (Завжди видимий) ---
    helpGui.SetFont("s15 Bold cAFAFAF q5", "Segoe UI")
    helpGui.Add("Text", "x20 y16 w680", "Довідка LSPD Binder")
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    helpGui.Add("Text", "x20 y44 w680", "Всі бінди зберігаються у файлі Binds.txt поруч із програмою. Файл можна редагувати вручну або через редактор біндів.")
    helpGui.Add("Text", "x20 y68 w680 h1 0x10")

    ; ================= СТОРІНКА 1 =================
    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page1Ctrls.Push(helpGui.Add("Text", "x20 y76", "🎹  Де взяти назви клавіш"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page1Ctrls.Push(helpGui.Add("Text", "x20 y96 w680", "Натисни на посилання — відкриється офіційний список AutoHotkey v2:"))
    page1Ctrls.Push(helpGui.Add("Link", "x20 y112 w680 cAFAFAF", "<a href=" Chr(34) "https://www.autohotkey.com/docs/v2/KeyList.htm" Chr(34) ">https://www.autohotkey.com/docs/v2/KeyList.htm</a>"))
    page1Ctrls.Push(helpGui.Add("Text", "x20 y132 w680", "Приклади назв:   F1..F12   Enter   Tab   Escape   Space   Backspace   Delete`nInsert   Home   End   Left   Right   Up   Down`nNumpad0..Numpad9   NumpadEnter   NumpadDot`nLButton   RButton   MButton   A..Z   0..9"))

    page1Ctrls.Push(helpGui.Add("Text", "x20 y200 w680 h1 0x10"))

    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page1Ctrls.Push(helpGui.Add("Text", "x20 y208", "⚡  Бінд-Дія — послідовність кроків"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page1Ctrls.Push(helpGui.Add("Text", "x20 y228 w340", "Формат запису в Binds.txt:"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Courier New")
    page1Ctrls.Push(helpGui.Add("Text", "x20 y244 w340", "[клавіша] Назва (опц.)`n(кд_мс)            `; кд за замовч. 1000 мс`nKEY назва_клавіші  `; скрипт тисне клавішу`nTEXT " Chr(34) "текст" Chr(34) "      `; вставляє текст`nWAIT мілісекунди   `; пауза між кроками"))

    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page1Ctrls.Push(helpGui.Add("Text", "x380 y228 w320", "Приклад (складний):"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Courier New")
    page1Ctrls.Push(helpGui.Add("Text", "x380 y244 w320", "[F7]`n(3000)`nKEY Enter`nTEXT " Chr(34) "/me арештовує підозрюваного" Chr(34) "`nKEY Enter`nWAIT 500`nKEY U`nTEXT " Chr(34) "Оформлюю протокол, зачекайте" Chr(34) "`nKEY Enter"))

    page1Ctrls.Push(helpGui.Add("Text", "x20 y396 w680 h1 0x10"))

    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page1Ctrls.Push(helpGui.Add("Text", "x20 y404", "⌨️➕  Комбінації клавіш"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page1Ctrls.Push(helpGui.Add("Text", "x20 y424 w680",
    (
        "Працює і в KEY-кроках, і як клавіша АКТИВАЦІЇ бінда: [Ctrl+F6] Назва, KEY Ctrl+V, KEY Alt+F4.`n"
        "Модифікатори: Ctrl (або Control), Alt, Shift, Win (або Windows) - регістр не важливий.`n"
        "Клавіші [ ] `; також можна використовувати як частину комбінації (напр. KEY Ctrl+[)."
    )))

    ; ================= СТОРІНКА 2 =================
    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y76", "🖼️  Бінд-Картинка — зображення поверх гри"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y96 w340", "Формат запису в Binds.txt:"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Courier New")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y112 w340", "[клавіша] Назва (опц.)`nIMG " Chr(34) "пряме посилання на картинку" Chr(34) "`n(x, y)            `; позиція на екрані`n(x, y, opacity, scale)   `; прозорість (0-255) та масштаб %"))

    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x380 y96 w320", "Параметри:"))
    page2Ctrls.Push(helpGui.Add("Text", "x380 y112 w320", "x, y — відступ у пікселях від лівого`nверхнього кута екрана.`nopacity — прозорість (255=повна, 0=невид).`nscale — масштаб (100=оригінал, 50=половина).`nПовторне натискання ховає картинку.`nКлавіша Esc закриває всі картинки одразу."))

    page2Ctrls.Push(helpGui.Add("Text", "x20 y210 w680 h1 0x10"))

    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y220", "⚠️  Важливо про фон картинки"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y240 w680", "Скрипт робить ЧОРНИЙ (#000000) колір прозорим — він буде невидимий поверх гри.`nЯкщо фон білий або інший — він залишиться видимим."))

    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y290", "📋  Декілька біндів на одну клавішу"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y310 w680", "Якщо призначити кілька біндів на одну клавішу, при її натисканні з'явиться зручне меню вибору.`nБінди активуються відповідними цифрами на клавіатурі від 1 до 9, а 10-й бінд — цифрою 0.`nМаксимальна кількість біндів на одну клавішу — 10. Решта відображатись не буде."))

    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y380", "🛑  Екстрена зупинка бінда"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y400 w680", "Якщо бінд-дія (наприклад, довга відігровка з паузами) вже виконується, натискання клавіші Esc моментально зупинить її роботу.`nEsc також закриває всі відкриті меню вибору та картинки."))

    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y470", "⌨️  Про перехоплення клавіш"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page2Ctrls.Push(helpGui.Add("Text", "x20 y490 w680", "✅ Галочка «Не перехоплювати» (або ~ перед клавішею): бінд спрацює, і гра ТЕЖ отримає цю клавішу.`n❌ Без галочки «Не перехоплювати» (без ~): бінд спрацює, але гра НЕ отримає натискання цієї клавіші."))

    ; ================= СТОРІНКА 3 =================
    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page3Ctrls.Push(helpGui.Add("Text", "x20 y76", "🛠️  Вбудований редактор біндів"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page3Ctrls.Push(helpGui.Add("Text", "x20 y96 w680", "Програма має зручний графічний редактор для налаштування біндів.`nКоли відкрито будь-яке вікно редактора, ваші ігрові бінди тимчасово вимикаються, щоб не заважати вільно друкувати та редагувати текст (без конфліктів із гарячими клавішами)."))

    helpGui.SetFont("s10 Bold cAFAFAF", "Segoe UI")
    page3Ctrls.Push(helpGui.Add("Text", "x20 y150", "Гарячі клавіші редактора:"))
    helpGui.SetFont("s9 Norm cAFAFAF", "Segoe UI")
    page3Ctrls.Push(helpGui.Add("Text", "x20 y170 w680", "• Ctrl+C та Ctrl+V (або кнопка Дублювати) — швидке копіювання та вставлення вибраного бінду.`n• Del — видалення бінду. У віконці підтвердження можна поставити галочку «Запам'ятати мій вибір».`n• Ctrl+Z та Ctrl+Y — скасування (Undo) та повторення (Redo) дій. Зберігає до 50 останніх змін."))

    ; ================= НАВІГАЦІЯ =================
    helpGui.SetFont("s9 Bold cAFAFAF", "Segoe UI")
    btnClose := helpGui.Add("Text", "x20 y540 w120 h30 vHelpBtnClose Background333333 Center +0x200 Border", "❌ Закрити")

    lblPage := helpGui.Add("Text", "x220 y545 w280 Center c888888 vHelpLblPage Background191919", "Сторінка 1 з 3")

    btnPrev := helpGui.Add("Text", "x440 y540 w120 h30 vHelpBtnPrev Background333333 Center +0x200 Border", "← Назад")
    btnNext := helpGui.Add("Text", "x580 y540 w120 h30 vHelpBtnNext Background333333 Center +0x200 Border", "Вперед →")

    btnClose.OnEvent("Click", (*) => helpGui.Destroy())
    HoverBtn(btnClose)
    HoverBtn(btnPrev)
    HoverBtn(btnNext)

    UpdatePage(pageNum) {
        curPage := pageNum
        lblPage.Value := "Сторінка " pageNum " з 3"
        for c in page1Ctrls
            c.Visible := (pageNum = 1)
        for c in page2Ctrls
            c.Visible := (pageNum = 2)
        for c in page3Ctrls
            c.Visible := (pageNum = 3)

        btnPrev.Visible := (pageNum > 1)
        btnNext.Visible := (pageNum < 3)
        DllCall("InvalidateRect", "Ptr", helpGui.Hwnd, "Ptr", 0, "Int", 1)
    }

    btnPrev.OnEvent("Click", (*) => UpdatePage(curPage - 1))
    btnNext.OnEvent("Click", (*) => UpdatePage(curPage + 1))

    UpdatePage(1) ; Initial state

    helpGui.OnEvent("Size", HelpGuiResize)
    HelpGuiResize(thisGui, minMax, width, height) {
        if (minMax = -1)
            return
        try thisGui["HelpBtnClose"].Move(20, height - 50)
        try thisGui["HelpLblPage"].Move(width // 2 - 140, height - 45)
        try thisGui["HelpBtnPrev"].Move(width - 280, height - 50)
        try thisGui["HelpBtnNext"].Move(width - 140, height - 50)
    }

    helpGui.Show("w720 h610")
}

SetDarkMode(hwnd) {
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 19, "int*", 1, "int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 20, "int*", 1, "int", 4)
    try DllCall("uxtheme\135", "Int", 2)
    try DllCall("uxtheme\135", "Int", 1)
}

#HotIf WinActive("LSPD Binder | Редактор біндів")
^z:: {
    global editorGuiCtx
    if IsSet(editorGuiCtx) && IsObject(editorGuiCtx)
        EditorUndo(editorGuiCtx)
}
^y:: {
    global editorGuiCtx
    if IsSet(editorGuiCtx) && IsObject(editorGuiCtx)
        EditorRedo(editorGuiCtx)
}
^c:: {
    global editorGuiCtx
    if IsSet(editorGuiCtx) && IsObject(editorGuiCtx)
        EditorBtnCopy(editorGuiCtx)
}
^v:: {
    global editorGuiCtx
    if IsSet(editorGuiCtx) && IsObject(editorGuiCtx)
        EditorBtnPaste(editorGuiCtx)
}
Del:: {
    global editorGuiCtx
    if IsSet(editorGuiCtx) && IsObject(editorGuiCtx)
        EditorBtnDel(editorGuiCtx)
}
#HotIf
