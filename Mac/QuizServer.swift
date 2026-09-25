import Foundation

/// 🗳️ The live quiz, the same as on Windows: students open a page in their phone
/// browser, type their name and answer. Faster correct answers score more.
/// A tiny web server on plain sockets — no extra libraries.
final class QuizServer {
    private(set) var port: UInt16 = 0
    var onChange: (() -> Void)?

    private var fd: Int32 = -1
    private var running = false
    private let lock = NSLock()

    private final class Player {
        var name = ""
        var score = 0
        var last = 0
        var lastCorrect = false
    }
    private var players: [String: Player] = [:]
    private var answers: [String: (choice: Int, at: TimeInterval)] = [:]
    private var askedAt = Date().timeIntervalSince1970

    private(set) var qid = ""
    private(set) var question = ""
    private(set) var options: [String] = []
    private(set) var correct = -1
    private(set) var isOpen = false
    private(set) var reveal = false
    private(set) var seconds = 0
    private(set) var qIndex = 0
    private(set) var qCount = 0

    var optionCount: Int { max(2, options.count) }
    var total: Int { lock.lock(); defer { lock.unlock() }; return answers.count }
    var playerCount: Int { lock.lock(); defer { lock.unlock() }; return players.count }
    var left: Int {
        guard seconds > 0 else { return -1 }
        return max(0, seconds - Int(Date().timeIntervalSince1970 - askedAt))
    }

    // ── server ─────────────────────────────────────────────────────────
    @discardableResult
    func start() -> Bool {
        if running { return true }
        for p in UInt16(8088)...UInt16(8095) where listen(on: p) { port = p; running = true; accept(); return true }
        return false
    }

    private func listen(on p: UInt16) -> Bool {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var yes: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = p.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if bound != 0 || Darwin.listen(s, 64) != 0 { close(s); return false }
        fd = s
        return true
    }

    private func accept() {
        let server = fd
        Thread {
            while self.running {
                let client = Darwin.accept(server, nil, nil)
                if client < 0 { if self.running { usleep(100_000) }; continue }
                Thread { self.serve(client) }.start()
            }
        }.start()
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = recv(client, &buf, buf.count, 0)
        guard n > 0, let head = String(bytes: buf[0..<n], encoding: .utf8) else { return }
        let parts = head.split(separator: " ")
        guard parts.count >= 2 else { return }
        let target = String(parts[1])
        var path = target, query = ""
        if let q = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<q])
            query = String(target[target.index(after: q)...])
        }
        let args = QuizServer.parse(query)
        switch path {
        case "/", "/index.html": reply(client, type: "text/html; charset=utf-8", body: QuizServer.studentPage)
        case "/state": reply(client, type: "application/json", body: stateJson(id: args["id"] ?? ""))
        case "/join": reply(client, type: "application/json", body: join(args))
        case "/vote": reply(client, type: "application/json", body: vote(args))
        default: reply(client, type: "text/plain", body: "not found", code: 404)
        }
    }

    private func reply(_ client: Int32, type: String, body: String, code: Int = 200) {
        let data = Array(body.utf8)
        let header = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Not Found")\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        _ = Array(header.utf8).withUnsafeBufferPointer { send(client, $0.baseAddress, $0.count, 0) }
        _ = data.withUnsafeBufferPointer { send(client, $0.baseAddress, $0.count, 0) }
    }

    private static func parse(_ q: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            let value = kv.count > 1 ? (String(kv[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "") : ""
            out[key] = value
        }
        return out
    }

    // ── the teacher's side ─────────────────────────────────────────────
    func newQuestion(_ text: String, options list: [String], correct c: Int, index: Int, count: Int, seconds secs: Int) {
        lock.lock()
        qid = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).description
        question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        options = list.count >= 2 ? list : ["", ""]
        correct = (c >= 0 && c < options.count) ? c : -1
        qIndex = index; qCount = count
        self.seconds = max(0, min(secs, 600))
        answers.removeAll()
        isOpen = true; reveal = false
        askedAt = Date().timeIntervalSince1970
        lock.unlock()
        if self.seconds > 0 {
            let mine = qid
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(self.seconds)) { [weak self] in
                guard let self, self.qid == mine, self.isOpen else { return }
                self.showResults()
            }
            DispatchQueue.global().async { [weak self] in
                while let self, self.qid == mine, self.isOpen {
                    Thread.sleep(forTimeInterval: 1)
                    DispatchQueue.main.async { self.onChange?() }
                }
            }
        }
        DispatchQueue.main.async { self.onChange?() }
    }

    /// Show the answers and give points — faster correct answers score more.
    func showResults() {
        lock.lock()
        if !reveal {
            reveal = true; isOpen = false
            let span = Double(seconds > 0 ? seconds : 30)
            for (id, a) in answers {
                guard let p = players[id] else { continue }
                p.lastCorrect = correct >= 0 && a.choice == correct
                p.last = 0
                if p.lastCorrect {
                    let secs = max(0, a.at - askedAt)
                    p.last = Int((1000 * (1 - min(1, secs / span) / 2)).rounded())
                    p.score += p.last
                }
            }
        }
        lock.unlock()
        DispatchQueue.main.async { self.onChange?() }
    }

    func setCorrect(_ i: Int) {
        lock.lock(); correct = (i >= 0 && i < optionCount) ? i : -1; lock.unlock()
        showResults()
    }
    func closeQuestion() { lock.lock(); isOpen = false; lock.unlock(); DispatchQueue.main.async { self.onChange?() } }
    func resetScores() {
        lock.lock(); for p in players.values { p.score = 0; p.last = 0 }; lock.unlock()
        DispatchQueue.main.async { self.onChange?() }
    }

    func counts() -> [Int] {
        lock.lock(); defer { lock.unlock() }
        var c = [Int](repeating: 0, count: optionCount)
        for a in answers.values where a.choice >= 0 && a.choice < c.count { c[a.choice] += 1 }
        return c
    }

    /// Best students so far: (name, score, points just won)
    func top(_ n: Int) -> [(name: String, score: Int, last: Int)] {
        lock.lock(); defer { lock.unlock() }
        return players.values.filter { !$0.name.isEmpty }
            .sorted { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }
            .prefix(n).map { ($0.name, $0.score, $0.last) }
    }

    /// The address students open in their browser.
    func bestUrl() -> String {
        let ips = Net.addresses()
        let ip = ips.first { $0.hasPrefix("192.168.") } ?? ips.first { $0.hasPrefix("10.") || $0.hasPrefix("172.") } ?? ips.first ?? "127.0.0.1"
        return "http://\(ip):\(port)"
    }

    func stop() { running = false; if fd >= 0 { close(fd); fd = -1 } }

    // ── what the students' phones read ─────────────────────────────────
    private func join(_ a: [String: String]) -> String {
        guard let id = a["id"], id.count > 3, var name = a["name"]?.trimmingCharacters(in: .whitespaces), !name.isEmpty
        else { return "{\"ok\":false}" }
        if name.count > 24 { name = String(name.prefix(24)) }
        lock.lock()
        let p = players[id] ?? Player()
        p.name = name
        players[id] = p
        lock.unlock()
        DispatchQueue.main.async { self.onChange?() }
        return "{\"ok\":true}"
    }

    private func vote(_ a: [String: String]) -> String {
        guard let id = a["id"], let q = a["q"], let c = Int(a["c"] ?? "") else { return "{\"ok\":false}" }
        lock.lock()
        var ok = false
        if isOpen, q == qid, c >= 0, c < optionCount, answers[id] == nil {
            if players[id] == nil { players[id] = Player() }
            answers[id] = (c, Date().timeIntervalSince1970)     // the first answer counts — speed matters
            ok = true
        }
        lock.unlock()
        if ok { DispatchQueue.main.async { self.onChange?() } }
        return ok ? "{\"ok\":true}" : "{\"ok\":false}"
    }

    private func stateJson(id: String) -> String {
        lock.lock()
        var c = [Int](repeating: 0, count: optionCount)
        for a in answers.values where a.choice >= 0 && a.choice < c.count { c[a.choice] += 1 }
        let me = players[id]
        let order = players.values.filter { !$0.name.isEmpty }.sorted { $0.score > $1.score }
        let rank = me == nil ? 0 : (order.firstIndex { $0 === me! }.map { $0 + 1 } ?? 0)
        let mine = answers[id]?.choice
        // JSON needs one type per value, so these two are prepared first
        let countsValue: Any = reveal ? c : NSNull()
        let mineValue: Any = mine ?? NSNull()
        let topValue: [[String: Any]] = order.prefix(5).map { ["name": $0.name, "score": $0.score] }
        let payload: [String: Any] = [
            "qid": qid, "q": question, "opts": options, "n": optionCount, "open": isOpen, "reveal": reveal,
            "correct": reveal ? correct : -1, "total": answers.count, "counts": countsValue,
            "qi": qIndex, "qn": qCount, "secs": seconds, "left": left,
            "joined": me != nil, "name": me?.name ?? "", "score": me?.score ?? 0, "last": me?.last ?? 0,
            "ok": me?.lastCorrect ?? false, "rank": rank, "players": order.count,
            "mine": mineValue, "top": topValue
        ]
        lock.unlock()
        guard let d = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    /// The page students see — the same one the Windows app serves.
    private static let studentPage = #"""
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Quiz</title><style>
*{box-sizing:border-box}body{margin:0;font-family:system-ui,Segoe UI,Tahoma,sans-serif;background:#0f1117;color:#e8eaf0;min-height:100vh}
.wrap{padding:16px;max-width:680px;margin:0 auto}
h1{font-size:21px;margin:8px 0 4px;line-height:1.35}.sub{color:#8a90a2;font-size:14px}
input{width:100%;padding:16px;font-size:20px;border-radius:14px;border:0;margin:14px 0}
.go{width:100%;padding:16px;font-size:20px;font-weight:800;border:0;border-radius:14px;background:#4f8cff;color:#fff}
.opts{display:grid;gap:12px;grid-template-columns:1fr 1fr;margin-top:14px}
.opt{border:0;border-radius:18px;color:#fff;min-height:104px;padding:12px;box-shadow:0 6px 0 rgba(0,0,0,.35);text-align:left;font-size:17px;font-weight:700}
.opt b{display:block;font-size:30px;font-weight:900}
.opt:active{transform:translateY(3px);box-shadow:0 3px 0 rgba(0,0,0,.35)}
.opt.sel{outline:5px solid #fff}.opt.dim{opacity:.35}
.pill{display:inline-block;background:#1a1d27;border-radius:999px;padding:6px 14px;font-size:14px;color:#c8ccd8;margin-top:8px}
#st{text-align:center;font-size:18px;margin-top:16px;min-height:26px}
.big{font-size:42px;font-weight:900;text-align:center;margin-top:14px}
.tiny{font-size:13px;color:#8a90a2;text-align:center;margin-top:6px}
table{width:100%;margin-top:14px;font-size:16px}td{padding:6px 4px;border-bottom:1px solid #22262f}td:last-child{text-align:right;color:#fbbf24;font-weight:700}
</style></head><body><div class="wrap">
<div id="join"><div class="sub">Quiz · تاقیکردنەوە</div><h1>Your name · ناوت</h1>
 <input id="nm" maxlength="24" autocomplete="off" placeholder="Sara"><button class="go" onclick="join()">Join · بەشداربوون</button></div>
<div id="game" style="display:none">
 <div class="sub"><span id="who"></span> <span class="pill" id="sc">0</span> <span class="pill" id="clock" style="display:none">⏱ 0</span></div>
 <h1 id="q"></h1><div id="opts" class="opts"></div><div id="st"></div>
 <div id="res"></div>
</div></div>
<script>
const C=['#ef4444','#3b82f6','#eab308','#22c55e','#a855f7','#f97316'];
let id=localStorage.getItem('remcoId');if(!id){id=Math.random().toString(36).slice(2)+Date.now().toString(36);localStorage.setItem('remcoId',id);}
let S=null,mine=null,name=localStorage.getItem('remcoName')||'';
async function join(){const v=document.getElementById('nm').value.trim();if(!v)return;
 name=v;localStorage.setItem('remcoName',v);
 await fetch('/join?id='+encodeURIComponent(id)+'&name='+encodeURIComponent(v),{cache:'no-store'});poll();}
function draw(){if(!S)return;
 document.getElementById('join').style.display=S.joined?'none':'block';
 document.getElementById('game').style.display=S.joined?'block':'none';
 if(!S.joined)return;
 document.getElementById('who').textContent=S.name;
 document.getElementById('sc').textContent='⭐ '+S.score;
 const ck=document.getElementById('clock');
 if(S.left>=0&&S.open){ck.style.display='';ck.textContent='⏱ '+S.left;ck.style.background=S.left<=5?'#ef4444':'#1a1d27';}else ck.style.display='none';
 document.getElementById('q').textContent=(S.qn>1?('('+S.qi+'/'+S.qn+') '):'')+(S.q||'');
 const o=document.getElementById('opts');
 if(o.dataset.qid!==S.qid||o.childElementCount!==S.n){o.innerHTML='';o.dataset.qid=S.qid;
  for(let i=0;i<S.n;i++){const b=document.createElement('button');b.className='opt';b.style.background=C[i];b.onclick=()=>vote(i);o.appendChild(b);}}
 [...o.children].forEach((b,i)=>{const t=(S.opts&&S.opts[i])?S.opts[i]:'';
  let extra='';if(S.reveal&&S.counts){const tot=S.counts.reduce((a,b)=>a+b,0)||1;extra=' — '+S.counts[i]+' · '+Math.round(S.counts[i]*100/tot)+'%'+(S.correct===i?' ✓':'');}
  b.innerHTML='<b>'+String.fromCharCode(65+i)+'</b>'+(t||'')+extra;
  b.className='opt'+(mine===i?' sel':'')+(S.reveal&&S.correct>=0&&S.correct!==i?' dim':'');b.disabled=!S.open;});
 const st=document.getElementById('st'),res=document.getElementById('res');res.innerHTML='';
 if(S.reveal){st.textContent='';
  res.innerHTML='<div class="big">'+(S.correct<0?'📊 Results':(S.ok?'✅ +'+S.last:'❌ 0'))+'</div>'+
   '<div class="tiny">'+(S.ok?'Correct · ڕاستە':(mine===null?'No answer · وەڵامت نەدا':'Not this time · هەڵەیە'))+
   ' — ⭐ '+S.score+' · #'+S.rank+' of '+S.players+'</div>'+
   (S.top&&S.top.length?'<table>'+S.top.map((t,i)=>'<tr><td>'+['🥇','🥈','🥉','4.','5.'][i]+' '+t.name+'</td><td>'+t.score+'</td></tr>').join('')+'</table>':'');}
 else if(!S.open)st.textContent='⏸ Waiting for the teacher · چاوەڕێی مامۆستا';
 else st.textContent=mine===null?'Tap your answer · وەڵامەکەت هەڵبژێرە':'✓ Sent · نێردرا';}
async function poll(){try{const r=await fetch('/state?id='+encodeURIComponent(id),{cache:'no-store'});const s=await r.json();
 if(!S||s.qid!==S.qid)mine=(s.mine===null||s.mine===undefined)?null:s.mine; else if(s.mine!==null&&s.mine!==undefined)mine=s.mine;
 S=s;draw();}catch(e){}}
async function vote(i){if(!S||!S.open||mine!==null)return;mine=i;draw();
 try{await fetch('/vote?id='+encodeURIComponent(id)+'&c='+i+'&q='+S.qid,{cache:'no-store'});}catch(e){}}
if(name){document.getElementById('nm').value=name;fetch('/join?id='+encodeURIComponent(id)+'&name='+encodeURIComponent(name),{cache:'no-store'});}
poll();setInterval(poll,1200);
</script></body></html>
"""#
}
