import SwiftUI

/// 🗳️ The teacher's side of the quiz: saved quizzes, questions with written
/// answers, an optional countdown, and the controls while a question is live.
struct QuizSheet: View {
    @ObservedObject var link: Link
    @Environment(\.dismiss) private var dismiss
    @State private var quizzes: [SavedQuiz] = SavedQuiz.load()
    @State private var editing: SavedQuiz?
    @State private var quick = false

    var body: some View {
        NavigationStack {
            List {
                Section("Saved quizzes") {
                    if quizzes.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                    ForEach(quizzes) { q in
                        HStack {
                            Button {
                                link.runQuiz = q
                                link.runIndex = 0
                                link.sendQuestion(0)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("▶  " + q.name)
                                    Text("\(q.questions.count) question\(q.questions.count == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("✏️") { editing = q }.buttonStyle(.borderless)
                        }
                    }
                    .onDelete { idx in
                        quizzes.remove(atOffsets: idx)
                        SavedQuiz.save(quizzes)
                    }
                }
                Section {
                    Button("➕ New quiz") { editing = SavedQuiz(name: "My quiz", questions: []) }
                    Button("⚡ Quick question (A, B, C…)") { quick = true }
                }
                Section {
                    Text("Students join the same Wi-Fi as the computer, scan the code on the projector, type their name and answer. Faster correct answers score more.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("🗳️ Quiz")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $editing) { q in
                QuizEditor(quiz: q) { saved in
                    if let i = quizzes.firstIndex(where: { $0.id == saved.id }) { quizzes[i] = saved } else { quizzes.append(saved) }
                    SavedQuiz.save(quizzes)
                }
            }
            .sheet(isPresented: $quick) {
                QuestionEditor(question: QuizQuestion(), title: "⚡ Quick question") { q in
                    link.runQuiz = SavedQuiz(name: "", questions: [q])
                    link.runIndex = 0
                    link.sendQuestion(0)
                    dismiss()
                }
            }
        }
    }
}

/// The controls while a question is live.
struct QuizBar: View {
    @ObservedObject var link: Link

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if link.quizLeft >= 0 { Text("⏱ \(link.quizLeft)").font(.callout.monospacedDigit()) }
                Text("👥 \(link.quizPlayers)  ·  ✍️ \(link.quizTotal)").font(.callout)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if !link.quizReveal {
                        Button("📊 Show results") { link.send(["c": "quiz", "a": "reveal"]) }.tint(.blue)
                    } else if link.runIndex + 1 < (link.runQuiz?.questions.count ?? 0) {
                        Button("▶ Next question") { link.sendQuestion(link.runIndex + 1) }.tint(.blue)
                    }
                    Text("✓").font(.caption)
                    ForEach(0..<max(2, link.quizOptions), id: \.self) { i in
                        Button(String(UnicodeScalar(65 + i)!)) { link.send(["c": "quiz", "a": "correct", "v": i]) }
                            .tint(link.quizCorrect == i ? .green : .gray)
                    }
                    Button("🏆 Scores") { link.send(["c": "quiz", "a": "scores"]) }.tint(.gray)
                    Button("♻️") { link.send(["c": "quiz", "a": "reset"]) }.tint(.gray)
                    Button("✕") { link.send(["c": "quiz", "a": "close"]) }.tint(.gray)
                }.font(.caption).buttonStyle(.bordered)
            }
            if !link.quizTop.isEmpty {
                Text(link.quizTop.prefix(3).enumerated().map { i, t in "\(["🥇","🥈","🥉"][i]) \(t.name) \(t.score)" }.joined(separator: "   "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// ── the quiz itself ───────────────────────────────────────────────────
struct QuizQuestion: Codable, Identifiable, Hashable {
    var id = UUID()
    var text = ""
    var options: [String] = ["", "", "", ""]
    var correct = 0
    var seconds = 0
}

struct SavedQuiz: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var questions: [QuizQuestion]

    static func load() -> [SavedQuiz] {
        guard let d = UserDefaults.standard.data(forKey: "quizzes"),
              let list = try? JSONDecoder().decode([SavedQuiz].self, from: d) else { return [] }
        return list
    }
    static func save(_ list: [SavedQuiz]) {
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: "quizzes") }
    }
}

struct QuizEditor: View {
    @State var quiz: SavedQuiz
    let onSave: (SavedQuiz) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: QuizQuestion?

    var body: some View {
        NavigationStack {
            Form {
                Section("Quiz name") { TextField("Morphology – week 4", text: $quiz.name) }
                Section("Questions") {
                    ForEach(quiz.questions) { q in
                        Button {
                            editing = q
                        } label: {
                            VStack(alignment: .leading) {
                                Text(q.text.isEmpty ? "—" : q.text).lineLimit(2)
                                Text(q.seconds > 0 ? "⏱ \(q.seconds)s" : "no time limit")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { quiz.questions.remove(atOffsets: $0) }
                    Button("➕ Add question") { editing = QuizQuestion() }
                }
            }
            .navigationTitle("Edit quiz")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(quiz); dismiss() } }
            }
            .sheet(item: $editing) { q in
                QuestionEditor(question: q, title: "Question") { saved in
                    if let i = quiz.questions.firstIndex(where: { $0.id == saved.id }) { quiz.questions[i] = saved }
                    else { quiz.questions.append(saved) }
                }
            }
        }
    }
}

struct QuestionEditor: View {
    @State var question: QuizQuestion
    let title: String
    let onSave: (QuizQuestion) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") { TextField("Which word has a bound morpheme?", text: $question.text, axis: .vertical) }
                Section("Answers — write them and tick the right one") {
                    ForEach(0..<6, id: \.self) { i in
                        HStack {
                            Text(String(UnicodeScalar(65 + i)!)).bold()
                            TextField(i < 2 ? "Answer" : "Answer (optional)", text: binding(i))
                            Button {
                                question.correct = i
                            } label: {
                                Image(systemName: question.correct == i ? "checkmark.circle.fill" : "circle")
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                Section("⏱ Time limit for this question") {
                    Picker("", selection: $question.seconds) {
                        Text("No limit").tag(0)
                        ForEach([10, 20, 30, 60], id: \.self) { Text("\($0)s").tag($0) }
                    }.pickerStyle(.segmented)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var q = question
                        while q.options.count < 6 { q.options.append("") }
                        var used = q.options.map { $0.trimmingCharacters(in: .whitespaces) }
                        while used.count > 2, used.last?.isEmpty == true { used.removeLast() }
                        q.options = used
                        q.correct = min(q.correct, used.count - 1)
                        onSave(q); dismiss()
                    }
                }
            }
        }
    }

    private func binding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < question.options.count ? question.options[i] : "" },
            set: { v in
                while question.options.count <= i { question.options.append("") }
                question.options[i] = v
            })
    }
}
