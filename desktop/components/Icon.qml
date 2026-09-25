import QtQuick

// Stroke-style vector icons on a 24-unit grid. Crisp at any scale, tinted
// with any colour, no icon theme required.
Canvas {
    id: c
    property string name: "sparkle"
    property color  color: "white"
    property real   size: 18
    property real   level: 1.0          // battery fill 0..1
    property bool   charging: false
    property real   stroke: 1.8

    width: size; height: size
    antialiasing: true
    renderTarget: Canvas.Image

    onNameChanged: requestPaint()
    onColorChanged: requestPaint()
    onLevelChanged: requestPaint()
    onChargingChanged: requestPaint()
    onSizeChanged: requestPaint()

    function arc(ctx, x, y, r, a0, a1) { ctx.beginPath(); ctx.arc(x, y, r, a0, a1); ctx.stroke() }
    function line(ctx, x0, y0, x1, y1) { ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke() }
    function poly(ctx, pts, close) {
        ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1])
        for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
        if (close) ctx.closePath()
        ctx.stroke()
    }
    function fillPoly(ctx, pts) {
        ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1])
        for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
        ctx.closePath(); ctx.fill()
    }
    function rr(ctx, x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r)
        ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
        ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r)
        ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r); ctx.closePath()
    }
    function dot(ctx, x, y, r) { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill() }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        ctx.save()
        ctx.scale(width / 24, height / 24)
        ctx.strokeStyle = color; ctx.fillStyle = color
        ctx.lineWidth = stroke; ctx.lineCap = "round"; ctx.lineJoin = "round"
        const P = Math.PI
        switch (name) {
        case "wifi":
            arc(ctx, 12, 18, 11, -P * 0.78, -P * 0.22)
            arc(ctx, 12, 18, 7.2, -P * 0.75, -P * 0.25)
            arc(ctx, 12, 18, 3.4, -P * 0.72, -P * 0.28)
            dot(ctx, 12, 18.6, 1.4); break
        case "wifi-off":
            arc(ctx, 12, 18, 11, -P * 0.78, -P * 0.22)
            arc(ctx, 12, 18, 7.2, -P * 0.75, -P * 0.25)
            dot(ctx, 12, 18.6, 1.4)
            line(ctx, 3, 3, 21, 21); break
        case "ethernet":
            rr(ctx, 5, 9, 14, 8, 2); ctx.stroke(); line(ctx, 12, 4, 12, 9); line(ctx, 8, 17, 8, 20); line(ctx, 16, 17, 16, 20); break
        case "bluetooth":
            poly(ctx, [[6, 7], [17, 16.5], [12, 21], [12, 3], [17, 7.5], [6, 17]], false); break
        case "volume": case "volume-high": case "volume-mid": case "volume-low": case "volume-mute": {
            poly(ctx, [[4, 9.5], [8, 9.5], [13, 5], [13, 19], [8, 14.5], [4, 14.5]], true)
            if (name === "volume-mute") { line(ctx, 17, 9.5, 22, 14.5); line(ctx, 22, 9.5, 17, 14.5) }
            else {
                if (name !== "volume-low") arc(ctx, 13, 12, 5, -P * 0.3, P * 0.3)
                if (name === "volume-high" || name === "volume") arc(ctx, 13, 12, 8.5, -P * 0.3, P * 0.3)
                if (name === "volume-low") arc(ctx, 13, 12, 4, -P * 0.3, P * 0.3)
            }
            break }
        case "mic":
            rr(ctx, 9, 3, 6, 11, 3); ctx.stroke()
            arc(ctx, 12, 12, 6.5, P * 0.05, P * 0.95)
            line(ctx, 12, 18.5, 12, 21); line(ctx, 9, 21, 15, 21); break
        case "battery": {
            rr(ctx, 2.5, 7.5, 17, 9, 2.2); ctx.stroke()
            line(ctx, 21.5, 10.5, 21.5, 13.5)
            const w = Math.max(0.6, 13.6 * Math.max(0, Math.min(1, level)))
            rr(ctx, 4.2, 9.2, w, 5.6, 1); ctx.fill()
            if (charging) {
                ctx.strokeStyle = "#0b0d12"; ctx.lineWidth = 3.2
                poly(ctx, [[12.5, 7], [9.5, 12.5], [12.5, 12.5], [11, 17]], false)
                ctx.strokeStyle = color; ctx.lineWidth = 1.6
                poly(ctx, [[12.5, 7], [9.5, 12.5], [12.5, 12.5], [11, 17]], false)
            }
            break }
        case "bell":
            ctx.beginPath(); ctx.moveTo(6, 16); ctx.lineTo(6, 11); ctx.arc(12, 11, 6, P, 0); ctx.lineTo(18, 16); ctx.lineTo(19.5, 18); ctx.lineTo(4.5, 18); ctx.closePath(); ctx.stroke()
            arc(ctx, 12, 19.5, 2.2, 0.15 * P, 0.85 * P); line(ctx, 12, 3, 12, 5); break
        case "bell-off":
            ctx.beginPath(); ctx.moveTo(6, 16); ctx.lineTo(6, 11); ctx.arc(12, 11, 6, P, 0); ctx.lineTo(18, 16); ctx.lineTo(19.5, 18); ctx.lineTo(4.5, 18); ctx.closePath(); ctx.stroke()
            line(ctx, 4, 4, 20, 20); break
        case "sparkle":
            fillPoly(ctx, [[12, 2.5], [14.2, 9.8], [21.5, 12], [14.2, 14.2], [12, 21.5], [9.8, 14.2], [2.5, 12], [9.8, 9.8]])
            fillPoly(ctx, [[19, 2.5], [19.9, 5.1], [22.5, 6], [19.9, 6.9], [19, 9.5], [18.1, 6.9], [15.5, 6], [18.1, 5.1]]); break
        case "grid":
            for (const x of [4, 10.25, 16.5]) for (const y of [4, 10.25, 16.5]) { rr(ctx, x, y, 3.5, 3.5, 1); ctx.fill() }
            break
        case "search":
            arc(ctx, 10.5, 10.5, 6.5, 0, 2 * P); line(ctx, 15.5, 15.5, 21, 21); break
        case "sliders":
            line(ctx, 4, 7, 20, 7); line(ctx, 4, 12, 20, 12); line(ctx, 4, 17, 20, 17)
            ctx.fillStyle = "#0b0d12"
            for (const [x, y] of [[15, 7], [8, 12], [13, 17]]) { dot(ctx, x, y, 2.6); }
            ctx.fillStyle = color
            for (const [x, y] of [[15, 7], [8, 12], [13, 17]]) { ctx.beginPath(); ctx.arc(x, y, 2.4, 0, 2 * P); ctx.stroke() }
            break
        case "gear":
            arc(ctx, 12, 12, 3.2, 0, 2 * P)
            for (let i = 0; i < 8; i++) { const a = i * P / 4; line(ctx, 12 + Math.cos(a) * 6.5, 12 + Math.sin(a) * 6.5, 12 + Math.cos(a) * 9.5, 12 + Math.sin(a) * 9.5) }
            arc(ctx, 12, 12, 6.5, 0, 2 * P); break
        case "power":
            arc(ctx, 12, 13, 8, -P * 0.32, P * 1.32); line(ctx, 12, 3, 12, 11); break
        case "lock":
            rr(ctx, 5, 11, 14, 10, 2.5); ctx.stroke(); arc(ctx, 12, 11, 4.5, P, 2 * P); dot(ctx, 12, 16, 1.4); break
        case "moon":
            ctx.beginPath(); ctx.arc(12, 12, 8.5, P * 0.25, P * 1.75); ctx.arc(15.5, 8.5, 7, P * 1.2, P * 0.55, true); ctx.closePath(); ctx.stroke(); break
        case "sun":
            arc(ctx, 12, 12, 4.2, 0, 2 * P)
            for (let i = 0; i < 8; i++) { const a = i * P / 4; line(ctx, 12 + Math.cos(a) * 7, 12 + Math.sin(a) * 7, 12 + Math.cos(a) * 9.8, 12 + Math.sin(a) * 9.8) }
            break
        case "play":  fillPoly(ctx, [[7, 4.5], [19.5, 12], [7, 19.5]]); break
        case "pause": rr(ctx, 6, 4.5, 4, 15, 1); ctx.fill(); rr(ctx, 14, 4.5, 4, 15, 1); ctx.fill(); break
        case "next":  fillPoly(ctx, [[5, 5], [15, 12], [5, 19]]); rr(ctx, 17, 5, 2.4, 14, 1); ctx.fill(); break
        case "prev":  fillPoly(ctx, [[19, 5], [9, 12], [19, 19]]); rr(ctx, 4.6, 5, 2.4, 14, 1); ctx.fill(); break
        case "cpu":
            rr(ctx, 6, 6, 12, 12, 2); ctx.stroke(); rr(ctx, 9.5, 9.5, 5, 5, 1); ctx.stroke()
            for (const v of [9, 15]) { line(ctx, v, 2.5, v, 6); line(ctx, v, 18, v, 21.5); line(ctx, 2.5, v, 6, v); line(ctx, 18, v, 21.5, v) }
            break
        case "gpu":
            rr(ctx, 3, 7, 18, 11, 2); ctx.stroke(); arc(ctx, 10, 12.5, 3, 0, 2 * P); line(ctx, 16, 10, 18, 10); line(ctx, 16, 14, 18, 14); line(ctx, 6, 18, 6, 21); line(ctx, 10, 18, 10, 21); break
        case "memory":
            rr(ctx, 3, 8, 18, 9, 1.5); ctx.stroke(); for (const x of [7, 11, 15]) rr(ctx, x, 11, 2.5, 3.5, 0.6), ctx.fill(); line(ctx, 3, 19.5, 21, 19.5); break
        case "chevron-down": poly(ctx, [[7, 10], [12, 15], [17, 10]], false); break
        case "chevron-right": poly(ctx, [[10, 7], [15, 12], [10, 17]], false); break
        case "chevron-left": poly(ctx, [[14, 7], [9, 12], [14, 17]], false); break
        case "x": line(ctx, 6.5, 6.5, 17.5, 17.5); line(ctx, 17.5, 6.5, 6.5, 17.5); break
        case "check": poly(ctx, [[5, 12.5], [10, 17.5], [19.5, 7]], false); break
        case "plus": line(ctx, 12, 5, 12, 19); line(ctx, 5, 12, 19, 12); break
        case "refresh":
            arc(ctx, 12, 12, 7.5, -P * 0.15, P * 1.55); poly(ctx, [[8.5, 3.5], [12.2, 5.6], [10.2, 9.3]], false); break
        case "monitor":
            rr(ctx, 3, 4.5, 18, 12.5, 2); ctx.stroke(); line(ctx, 8.5, 20.5, 15.5, 20.5); line(ctx, 12, 17, 12, 20.5); break
        case "image":
            rr(ctx, 3.5, 4.5, 17, 15, 2); ctx.stroke(); poly(ctx, [[3.5, 16], [9, 11], [13, 15], [16, 12.5], [20.5, 16.5]], false); dot(ctx, 15.5, 8.5, 1.5); break
        case "user":
            arc(ctx, 12, 8.5, 4, 0, 2 * P); arc(ctx, 12, 22, 8, P * 1.15, P * 1.85); break
        case "bolt": poly(ctx, [[13.5, 2.5], [6, 13.5], [12, 13.5], [10.5, 21.5], [18, 10.5], [12, 10.5]], true); break
        case "leaf":
            ctx.beginPath(); ctx.moveTo(5, 19); ctx.quadraticCurveTo(5, 6, 19, 5); ctx.quadraticCurveTo(19, 18, 8, 19); ctx.closePath(); ctx.stroke(); line(ctx, 5, 19, 14, 10); break
        case "gauge":
            arc(ctx, 12, 14, 8.5, P * 0.85, P * 2.15); line(ctx, 12, 14, 16.5, 9); dot(ctx, 12, 14, 1.5); break
        case "terminal": poly(ctx, [[5, 7], [10, 12], [5, 17]], false); line(ctx, 12, 17, 19, 17); break
        case "trash":
            line(ctx, 4, 7, 20, 7); poly(ctx, [[6, 7], [7, 20], [17, 20], [18, 7]], false); line(ctx, 9.5, 4, 14.5, 4); line(ctx, 10, 11, 10, 17); line(ctx, 14, 11, 14, 17); break
        case "send": poly(ctx, [[4, 12], [20, 4], [14.5, 20], [12, 13], [4, 12]], true); line(ctx, 12, 13, 20, 4); break
        case "brain":
            ctx.beginPath(); ctx.arc(9, 9, 4.5, P * 0.5, P * 1.5); ctx.arc(9, 15, 4.5, P * 1.5, P * 0.5); ctx.stroke()
            ctx.beginPath(); ctx.arc(15, 9, 4.5, P * 1.5, P * 0.5); ctx.arc(15, 15, 4.5, P * 0.5, P * 1.5); ctx.stroke(); line(ctx, 12, 5, 12, 19); break
        case "arrow": line(ctx, 7, 17, 17, 7); poly(ctx, [[9, 7], [17, 7], [17, 15]], false); break
        case "info": arc(ctx, 12, 12, 9, 0, 2 * P); line(ctx, 12, 11, 12, 16.5); dot(ctx, 12, 8, 1.2); break
        case "keyboard":
            rr(ctx, 2.5, 6.5, 19, 11, 2); ctx.stroke(); for (const x of [6, 9.5, 13, 16.5]) dot(ctx, x, 10, 0.9); for (const x of [7.5, 11, 14.5]) dot(ctx, x, 13.5, 0.9); line(ctx, 8, 15, 16, 15); break
        case "dnd": arc(ctx, 12, 12, 9, 0, 2 * P); line(ctx, 7.5, 12, 16.5, 12); break
        case "eye": ctx.beginPath(); ctx.moveTo(2.5, 12); ctx.quadraticCurveTo(12, 1.5, 21.5, 12); ctx.quadraticCurveTo(12, 22.5, 2.5, 12); ctx.stroke(); arc(ctx, 12, 12, 3.2, 0, 2 * P); break
        case "layers": poly(ctx, [[12, 3.5], [21, 8], [12, 12.5], [3, 8]], true); poly(ctx, [[3, 12.5], [12, 17], [21, 12.5]], false); poly(ctx, [[3, 17], [12, 21.5], [21, 17]], false); break
        case "dock": rr(ctx, 3, 15, 18, 5, 2); ctx.stroke(); for (const x of [6.5, 11, 15.5]) { rr(ctx, x, 16.3, 2.4, 2.4, 0.6); ctx.fill() } rr(ctx, 6, 4, 12, 8, 1.5); ctx.stroke(); break
        case "cloud": ctx.beginPath(); ctx.arc(9, 14, 5, P * 0.5, P * 1.5); ctx.arc(12, 9.5, 5, P * 1.1, P * 1.95); ctx.arc(17, 14, 4, P * 1.5, P * 0.5); ctx.closePath(); ctx.stroke(); break
        case "chip": rr(ctx, 4, 4, 16, 16, 3); ctx.stroke(); rr(ctx, 9, 9, 6, 6, 1); ctx.fill(); break
        case "pulse":
            // activity waveform — distinct silhouette so it never reads as "eye"
            ctx.lineWidth = stroke * 1.15
            poly(ctx, [[2, 12], [7.5, 12], [10, 5.5], [14, 18.5], [16.5, 12], [22, 12]], false)
            ctx.lineWidth = stroke; break
        case "moon-filled":
            ctx.beginPath(); ctx.arc(12, 12, 8.5, P * 0.25, P * 1.75)
            ctx.arc(15.5, 8.5, 7, P * 1.2, P * 0.55, true); ctx.closePath(); ctx.fill(); break
        default: arc(ctx, 12, 12, 8, 0, 2 * P)
        }
        ctx.restore()
    }
}
