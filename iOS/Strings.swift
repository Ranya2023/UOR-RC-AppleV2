import SwiftUI

/// English and Kurdish, like the Android app. Tap the flag button to switch.
final class L: ObservableObject {
    static let shared = L()
    @Published var ku: Bool = UserDefaults.standard.bool(forKey: "ku")

    func toggle() { ku.toggle(); UserDefaults.standard.set(ku, forKey: "ku") }

    func t(_ key: String) -> String { (ku ? kurdish[key] : english[key]) ?? english[key] ?? key }

    private let english: [String: String] = [
        "connect": "Connect", "disconnect": "Disconnect", "notConnected": "Not connected",
        "slide": "Slide", "notes": "Notes", "hideNotes": "Hide notes", "clear": "Clear",
        "start": "Start", "fromHere": "From here", "end": "End", "black": "Black", "white": "White",
        "next": "NEXT", "desktop": "Desktop", "backShow": "PowerPoint", "goto": "Go to slide",
        "keyboard": "Keyboard", "type": "Type here — it appears on the computer",
        "timer": "Timer", "countDown": "Count down", "countUp": "Count up", "minutes": "Minutes",
        "startTimer": "Start", "pause": "Pause", "reset": "Reset", "onProjector": "Show on projector",
        "settings": "Settings", "size": "Size", "color": "Colour", "style": "Style",
        "brightness": "Brightness", "dimAround": "Dim around", "magnify": "Magnify",
        "pencilOnly": "Draw with Apple Pencil only", "sensitivity": "Touch sensitivity",
        "whiteboard": "Whiteboard", "photos": "Photos", "document": "Document", "picker": "Picker",
        "quiz": "Quiz", "camera": "Camera", "gallery": "Group photos", "seeScreen": "See the screen",
        "files": "Files", "received": "Received from the computer", "language": "کوردی"
    ]

    private let kurdish: [String: String] = [
        "connect": "پەیوەستبوون", "disconnect": "پچڕاندن", "notConnected": "پەیوەست نییە",
        "slide": "سلاید", "notes": "تێبینی", "hideNotes": "شاردنەوەی تێبینی", "clear": "سڕینەوە",
        "start": "دەستپێکردن", "fromHere": "لێرەوە", "end": "کۆتایی", "black": "ڕەش", "white": "سپی",
        "next": "دواتر", "desktop": "دێسکتۆپ", "backShow": "پاوەرپۆینت", "goto": "بڕۆ بۆ سلاید",
        "keyboard": "تەختەکلیل", "type": "لێرە بنووسە — لەسەر کۆمپیوتەر دەردەکەوێت",
        "timer": "کاتژمێر", "countDown": "ژمێرانەوە بۆ خوارەوە", "countUp": "ژمێرانەوە بۆ سەرەوە",
        "minutes": "خولەک", "startTimer": "دەستپێکردن", "pause": "وەستان", "reset": "سفرکردنەوە",
        "onProjector": "پیشاندان لەسەر پرۆجێکتەر", "settings": "ڕێکخستن", "size": "قەبارە",
        "color": "ڕەنگ", "style": "شێواز", "brightness": "ڕووناکی", "dimAround": "تاریککردنی دەوروبەر",
        "magnify": "گەورەکردن", "pencilOnly": "تەنها بە پێنووسی ئەپڵ بنووسە",
        "sensitivity": "هەستیاریی دەستلێدان", "whiteboard": "تەختەی سپی", "photos": "وێنەکان",
        "document": "بەڵگەنامە", "picker": "هەڵبژاردن", "quiz": "تاقیکردنەوە", "camera": "کامێرا",
        "gallery": "وێنەی گرووپەکان", "seeScreen": "بینینی شاشە", "files": "فایلەکان",
        "received": "لە کۆمپیوتەرەوە وەرگیرا", "language": "English"
    ]
}
