pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bridge to the AIOS backend (FastAPI on 127.0.0.1:8778).
// Chat, PC control, model selection and budget all go through the same
// endpoints the browser UI, the CLI and voice use — one ecosystem.
Singleton {
    id: root

    readonly property string base: "http://127.0.0.1:8778"

    property bool   online: false
    property string loadedModel: ""
    property string selectedModel: ""
    property string budgetMode: "ZERO_COST"
    property var    budgetModes: ["ZERO_COST", "LOCAL_ONLY", "APPROVAL", "UNRESTRICTED"]
    property bool   thinking: false
    property int    memoryObjects: 0
    property int    runs: 0
    property var    models: []          // from /api/models
    property int    refreshWanted: 0    // consumers bump while visible → faster polling
    property var    jobs: []            // live backend jobs
    property var    providers: []
    property var    preferCloudFor: []
    property bool   autoRouting: false
    property bool   netOnline: true
    property var    lastRoute: ({})     // {model, mode, task, reason} of the last reply

    // chat state
    property bool   streaming: false
    property var    lastMeta: ({})
    property string conversationId: "shell-" + Math.floor(Date.now() / 1000)
    readonly property ListModel messages: ListModel {}

    // PC-control state
    property var    pending: null       // {cmd, tier, reason, token}
    property bool   controlBusy: false

    readonly property var selectedInfo: {
        for (const m of models) if (m.id === selectedModel) return m
        return null
    }
    readonly property string selectedLabel: autoRouting ? "Auto" : (selectedInfo ? selectedInfo.label : selectedModel)
    readonly property var loadedInfo: {
        for (const m of models) if (m.id === loadedModel) return m
        return null
    }

    // ── polling ────────────────────────────────────────────────────────
    Timer {
        interval: root.refreshWanted > 0 ? 5000 : 30000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }
    function refresh() { if (!statusProc.running) statusProc.running = true }

    Process {
        id: statusProc
        command: ["bash", "-c",
            `curl -sf -m 3 ${root.base}/api/status && echo && curl -sf -m 3 ${root.base}/api/models && echo && curl -sf -m 3 ${root.base}/api/settings && echo && curl -sf -m 3 ${root.base}/api/providers`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(l => l.trim())
                if (lines.length < 3) { root.online = false; return }
                try {
                    const st = JSON.parse(lines[0]), ms = JSON.parse(lines[1]), se = JSON.parse(lines[2])
                    root.online = true
                    root.loadedModel = st.loaded || ""
                    root.memoryObjects = st.objects || 0
                    root.runs = st.runs || 0
                    root.models = ms
                    root.selectedModel = se.selected_model
                    root.autoRouting = !!se.auto
                    root.preferCloudFor = se.prefer_cloud_for || []
                    root.budgetMode = se.budget_mode
                    root.budgetModes = se.budget_modes || root.budgetModes
                    root.thinking = !!se.thinking
                    root.jobs = st.jobs || []
                    root.netOnline = st.online !== false
                    if (lines.length >= 4) { try { root.providers = JSON.parse(lines[3]) } catch (e) {} }
                } catch (e) { root.online = false }
            }
        }
    }

    // ── settings ───────────────────────────────────────────────────────
    function patch(obj) {
        settingsProc.command = ["curl", "-sf", "-m", "5", "-X", "POST", root.base + "/api/settings",
                                "-H", "Content-Type: application/json", "-d", JSON.stringify(obj)]
        settingsProc.running = true
    }
    function selectModel(id)  { patch({ selected_model: id }) }
    function setBudget(mode)  { patch({ budget_mode: mode }) }
    function setThinking(on)  { patch({ thinking: !!on }) }
    function setCloudFor(list) { patch({ prefer_cloud_for: list }) }
    function unload() {
        Quickshell.execDetached(["curl", "-sf", "-m", "5", "-X", "POST", root.base + "/api/unload"])
        root.refresh()
    }
    function downloadModel(id) {
        const cleanId = id.trim().replace(/^local-/, "")
        Quickshell.execDetached(["kitty", "--class", "praxis-model-dl", "--title", "Download & Verify Model", "-e", "bash", "-c", `praxis-models download "${cleanId}"; echo; read -p "Press Enter to finish..."`])
    }

    Process {
        id: settingsProc
        stdout: StdioCollector { onStreamFinished: root.refresh() }
    }

    // ── chat (SSE over curl) ───────────────────────────────────────────
    function parseSse(block) {
        let event = "message", data = []
        for (const line of block.split("\n")) {
            if (line.startsWith("event: ")) event = line.slice(7).trim()
            else if (line.startsWith("data: ")) data.push(line.slice(6))
        }
        return data.length ? { event, data: data.join("\n") } : null
    }
    property int   _aiIndex: -1

    // job id of the answer being streamed (from its "meta" event)
    property string currentJob: ""

    // Stop a running AI job: the backend cancels the generation, which also
    // stops the model server from computing (frees the GPU at once).
    function cancelJob(id) {
        if (id) Quickshell.execDetached(["curl", "-s", "-m", "5", "-X", "POST", root.base + "/api/jobs/" + id + "/cancel"])
    }
    function stopAnswer() {
        if (!streaming) return
        if (currentJob) cancelJob(currentJob)
        else chatProc.running = false           // no id yet: dropping the connection stops it too
    }

    // every message carries the same roles — a ListModel fixes them on the
    // first append. images/files: one path per line ("" when none).
    function addMessage(role, text, meta, images, files) {
        messages.append({ role: role, text: text, meta: meta || "",
                          images: (images || []).join("\n"), files: (files || []).join("\n") })
    }

    // text: what the user typed; images: paths sent to a vision model;
    // files: other attachments (shown as chips); extra: their readable
    // contents, sent to the model but kept out of the bubble.
    function send(text, images, files, extra) {
        const msg = text ? text.trim() : ""
        const imgs = Array.isArray(images) ? images : []
        const docs = Array.isArray(files) ? files : []
        if ((!msg && !imgs.length && !docs.length) || streaming) return
        currentJob = ""
        addMessage("user", msg, "", imgs, docs)
        addMessage("ai", "", "")
        _aiIndex = messages.count - 1
        streaming = true
        const prompt = extra ? (msg || "Look at the attached file(s).") + "\n\n" + extra : msg
        chatProc.command = ["curl", "-sN", "-X", "POST", root.base + "/api/ask",
                            "-H", "Content-Type: application/json",
                            "-d", JSON.stringify({ message: prompt, conversation_id: conversationId, model: "auto", images: imgs })]
        chatProc.running = true
    }
    function clearChat() {
        messages.clear()
        conversationId = "shell-" + Math.floor(Date.now() / 1000)
    }

    // Forget stored conversations through the backend (settings, permission
    // grants, audit trail and usage ledger are kept). Replaces a shell script
    // that deleted the live SQLite file out from under the running backend.
    function forgetConversations() {
        if (!forgetProc.running) forgetProc.running = true
        clearChat()
    }
    Process {
        id: forgetProc
        command: ["curl", "-sf", "--max-time", "10", "-X", "POST", root.base + "/api/memory/forget",
                  "-H", "Content-Type: application/json", "-d", "{\"scope\":\"conversations\"}"]
        onExited: code => Notifs.notify(code === 0 ? "Memory cleared" : "Memory not cleared",
                                        code === 0 ? "Stored conversations were forgotten."
                                                   : "The AIOS backend is not reachable, so nothing was deleted.")
    }

    Process {
        id: chatProc
        // Quickshell 0.3.1's SplitParser drops the first line after a blank line, which
        // is exactly what SSE emits between events — so split on whole events instead.
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: block => {
                const ev = root.parseSse(block)
                if (!ev || ev.data === "{}" || root._aiIndex < 0) return
                let v; try { v = JSON.parse(ev.data) } catch (e) { return }
                if (ev.event === "meta") {
                    root.lastMeta = v
                    root.currentJob = v.job || ""
                    root.lastRoute = { model: v.model, mode: v.mode, task: v.task, reason: v.reason }
                    const lbl = (root.models.find(m => m.id === v.model) || {}).label || v.model
                    root.messages.setProperty(root._aiIndex, "meta",
                        `${v.mode || "LOCAL"} · ${lbl}` + (v.task ? ` · ${v.task}` : "") + (v.auto && v.reason ? ` · ${v.reason}` : "")
                        + (v.context_tokens !== undefined ? ` · ${v.context_tokens} ctx tok · ${v.retrieved} recalled` : ""))
                } else if (ev.event === "step") {
                    const cur = root.messages.get(root._aiIndex).text
                    root.messages.setProperty(root._aiIndex, "text", cur + (cur.length ? "\n" : "") + "↳ " + v.stage + ": " + v.msg + "\n")
                } else if (ev.event === "pending") {
                    root.pending = v
                } else if (ev.event === "error") {
                    root.messages.setProperty(root._aiIndex, "text", "⚠ " + v)
                } else if (ev.event === "done") {
                    // handled on exit
                } else {
                    const cur = root.messages.get(root._aiIndex).text
                    root.messages.setProperty(root._aiIndex, "text", cur + v)
                }
            }
        }
        onExited: (code, status) => {
            root.streaming = false
            root.currentJob = ""
            if (root._aiIndex >= 0 && root.messages.get(root._aiIndex).text === "")
                root.messages.setProperty(root._aiIndex, "text",
                    root.online ? "⚠ No reply (model may still be loading — try again)." : "⚠ AIOS backend is offline.")
            root._aiIndex = -1
            root.refresh()
        }
    }

    // ── PC control: propose → confirm → execute ────────────────────────
    function control(text) {
        const req = text.trim()
        if (!req || controlBusy) return
        controlBusy = true
        pending = null
        addMessage("user", "! " + req, "")
        proposeProc.command = ["curl", "-s", "-m", "180", "-X", "POST", root.base + "/api/tool/propose",
                               "-H", "Content-Type: application/json", "-d", JSON.stringify({ request: req })]
        proposeProc.running = true
    }
    Process {
        id: proposeProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.controlBusy = false
                let r; try { r = JSON.parse(this.text) } catch (e) {
                    root.addMessage("sys", "⚠ Backend unreachable.", ""); return }
                if (r.tier === "noop")      root.addMessage("sys", r.reason, "")
                else if (r.tier === "error") root.addMessage("sys", "⚠ " + r.reason, "")
                else if (r.tier === "forbidden")
                    root.addMessage("sys", "✗ Refused — " + r.reason, "$ " + r.cmd)
                else if (r.tier === "auto")
                    root.addMessage("sys", "✓ Ran" + (r.output ? "\n" + r.output : ""), "$ " + r.cmd)
                else root.pending = r   // confirm tier → UI shows a card with Run / Cancel
            }
        }
    }
    function confirmPending() {
        if (!pending) return
        execProc.command = ["curl", "-s", "-m", "60", "-X", "POST", root.base + "/api/tool/exec",
                            "-H", "Content-Type: application/json", "-d", JSON.stringify({ token: pending.token })]
        execProc.running = true
        addMessage("sys", "…", "$ " + pending.cmd)
        pending = null
    }
    function cancelPending() {
        if (!pending) return
        Quickshell.execDetached(["curl", "-s", "-X", "POST", root.base + "/api/tool/cancel",
                                 "-H", "Content-Type: application/json", "-d", JSON.stringify({ token: pending.token })])
        addMessage("sys", "Cancelled.", "$ " + pending.cmd)
        pending = null
    }
    Process {
        id: execProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r; try { r = JSON.parse(this.text) } catch (e) { return }
                const i = root.messages.count - 1
                root.messages.setProperty(i, "text", (r.executed ? "✓ Ran" : "⚠ " + r.output) + (r.executed && r.output ? "\n" + r.output : ""))
            }
        }
    }
}
