import Foundation

/// English and Kurdish (Sorani) for the Mac and iPhone apps — the same idea as the
/// Android app's table. `Lang.t("next")` gives the text in the chosen language.
public enum Lang {
    public static var code: String {
        get { UserDefaults.standard.string(forKey: "uorrc.lang") ?? (Locale.current.language.languageCode?.identifier == "ckb" ? "ku" : "en") }
        set { UserDefaults.standard.set(newValue, forKey: "uorrc.lang") }
    }
    public static var isKurdish: Bool { code == "ku" }

    public static func t(_ key: String) -> String {
        (isKurdish ? ku[key] : en[key]) ?? en[key] ?? key
    }

    public static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    static let en: [String: String] = [
        // connection
        "connect": "Connect", "disconnect": "Disconnect", "notConnected": "Not connected",
        "computers": "Computers on this Wi-Fi", "looking": "Looking…", "pinOnComputer": "PIN shown on the computer",
        "sameWifi": "Both devices must be on the same Wi-Fi — the laptop hotspot works well.",
        // presenting
        "slideOf": "Slide %d / %d", "pageOf": "Page %d / %d", "notes": "Notes", "hideNotes": "Hide notes",
        "start": "▶ Start", "fromHere": "▶ From here", "end": "■ End", "black": "⬛ Black", "white": "⬜ White",
        "next": "NEXT ▶", "prev": "◀", "goto": "🔢 Go to slide", "slideNumber": "Slide number",
        "desktop": "🖥 Desktop", "backShow": "▶ PowerPoint", "clear": "🗑 Clear",
        // tools
        "size": "Size", "color": "Colour", "style": "Style", "magnify": "Magnify",
        "brightness": "Brightness", "dimAround": "Dim around", "thickness": "Thickness",
        "caption": "Caption", "fontSize": "Text size", "background": "Background",
        // keyboard
        "keyboard": "⌨️ Keyboard", "typeHere": "Type here — it goes to the computer",
        "hideKeyboard": "Hide keyboard",
        // class tools
        "whiteboard": "🧑‍🏫 Whiteboard", "photos": "🖼 Photos", "document": "📑 Document",
        "picker": "🎲 Picker", "quiz": "🗳️ Quiz", "camera": "📷 Camera", "gallery": "📸 Group photos",
        "newPage": "➕ New page", "save": "💾 Save", "close": "✕",
        "pickTitle": "🎲 Random picker", "pickNames": "Names — one per line, or type 1-30 for numbers",
        "pickNoRepeat": "Don't pick the same student twice", "pickWheel": "🎡 Spin a wheel instead of showing names",
        "pick": "🎲 Pick",
        "quizSaved": "Saved quizzes", "quizNew": "➕ New quiz", "quizQuick": "⚡ Quick question (A, B, C…)",
        "quizQuestion": "Question", "quizAnswers": "Answers — write them and tick the right one",
        "quizTime": "⏱ Time limit for this question", "quizNoTime": "No limit",
        "quizResults": "📊 Show results", "quizNext": "▶ Next question", "quizScores": "🏆 Scores",
        "quizReset": "♻️ Reset scores", "quizNote": "Students join the same Wi-Fi, scan the code on the projector, type their name and answer. Faster correct answers score more.",
        // camera
        "camLight": "⚡ Light", "camFreeze": "⏸ Freeze", "camLive": "▶ Live", "camMic": "🎤 Mic",
        "camPhoto": "📸 Photo caption", "camShow": "Show on projector", "camSaveOnly": "Save only",
        "camGroupHint": "e.g. Group 1",
        // settings
        "settings": "⚙️ Settings", "language": "Language", "english": "English", "kurdish": "کوردی",
        "sensitivity": "Touch sensitivity", "previews": "Show slide previews", "vibrate": "Vibrate on tap",
        "timer": "Timer", "cancel": "Cancel", "ok": "OK", "done": "Done"
    ]

    static let ku: [String: String] = [
        "connect": "پەیوەستبوون", "disconnect": "پچڕاندن", "notConnected": "پەیوەست نییە",
        "computers": "کۆمپیوتەرەکانی ئەم وای‌فایە", "looking": "گەڕان…", "pinOnComputer": "ئەو PIN ـەی لەسەر کۆمپیوتەر دەردەکەوێت",
        "sameWifi": "هەردوو ئامێر دەبێت لەسەر هەمان وای‌فای بن — هۆتسپۆتی لاپتۆپ باشە.",
        "slideOf": "سلاید %d / %d", "pageOf": "لاپەڕە %d / %d", "notes": "تێبینی", "hideNotes": "شاردنەوەی تێبینی",
        "start": "▶ دەستپێکردن", "fromHere": "▶ لێرەوە", "end": "■ کۆتایی", "black": "⬛ ڕەش", "white": "⬜ سپی",
        "next": "دواتر ▶", "prev": "◀", "goto": "🔢 چوون بۆ سلاید", "slideNumber": "ژمارەی سلاید",
        "desktop": "🖥 دێسکتۆپ", "backShow": "▶ پاوەرپۆینت", "clear": "🗑 سڕینەوە",
        "size": "قەبارە", "color": "ڕەنگ", "style": "شێواز", "magnify": "گەورەکردن",
        "brightness": "ڕووناکی", "dimAround": "تاریککردنی دەوروبەر", "thickness": "ئەستووری",
        "caption": "ناونیشان", "fontSize": "قەبارەی دەق", "background": "پاشبنەما",
        "keyboard": "⌨️ تەختەکلیل", "typeHere": "لێرە بنووسە — بۆ کۆمپیوتەر دەچێت",
        "hideKeyboard": "شاردنەوەی تەختەکلیل",
        "whiteboard": "🧑‍🏫 تەختەی سپی", "photos": "🖼 وێنەکان", "document": "📑 بەڵگەنامە",
        "picker": "🎲 هەڵبژاردن", "quiz": "🗳️ تاقیکردنەوە", "camera": "📷 کامێرا", "gallery": "📸 وێنەی گرووپەکان",
        "newPage": "➕ لاپەڕەی نوێ", "save": "💾 پاشەکەوت", "close": "✕",
        "pickTitle": "🎲 هەڵبژاردنی هەڕەمەکی", "pickNames": "ناوەکان — هەر ناوێک لە دێڕێک، یان بنووسە 1-30 بۆ ژمارە",
        "pickNoRepeat": "هەمان قوتابی دووجار هەڵمەبژێرە", "pickWheel": "🎡 لە جیاتی ناوەکان چەرخە بسووڕێنە",
        "pick": "🎲 هەڵبژێرە",
        "quizSaved": "تاقیکردنەوە پاشەکەوتکراوەکان", "quizNew": "➕ تاقیکردنەوەی نوێ", "quizQuick": "⚡ پرسیاری خێرا (A, B, C…)",
        "quizQuestion": "پرسیار", "quizAnswers": "وەڵامەکان — بینووسە و ڕاستەکە دیاری بکە",
        "quizTime": "⏱ سنووری کات بۆ ئەم پرسیارە", "quizNoTime": "بێ سنوور",
        "quizResults": "📊 پیشاندانی ئەنجام", "quizNext": "▶ پرسیاری دواتر", "quizScores": "🏆 خاڵەکان",
        "quizReset": "♻️ سفرکردنەوەی خاڵ", "quizNote": "قوتابیان بە هەمان وای‌فایەوە پەیوەست دەبن، کۆدەکەی سەر پرۆجێکتەر سکان دەکەن، ناویان دەنووسن و وەڵام دەدەنەوە. وەڵامی ڕاستی خێراتر خاڵی زیاتر وەردەگرێت.",
        "camLight": "⚡ ڕووناکی", "camFreeze": "⏸ ڕاگرتن", "camLive": "▶ ڕاستەوخۆ", "camMic": "🎤 مایک",
        "camPhoto": "📸 ناونیشانی وێنە", "camShow": "پیشاندان لەسەر پرۆجێکتەر", "camSaveOnly": "تەنها پاشەکەوت",
        "camGroupHint": "بۆ نموونە: گرووپی ١",
        "settings": "⚙️ ڕێکخستن", "language": "زمان", "english": "English", "kurdish": "کوردی",
        "sensitivity": "هەستیاریی دەستلێدان", "previews": "پیشاندانی وێنۆچکەی سلاید", "vibrate": "لەرزین لە دەستلێدان",
        "timer": "کاتژمێر", "cancel": "پاشگەزبوونەوە", "ok": "باشە", "done": "تەواو"
    ]
}
