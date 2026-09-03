#!/usr/bin/env node
// receiver.mjs —— (可选)迷你报告接收器: 模拟 Phase 4 后端, 把收到的 JSON 落盘并打印
// 用法: AIOPS_REPORT_WEBHOOK=http://127.0.0.1:8899/reports node receiver.mjs 8899
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const port = Number(process.argv[2] || 8899);
const outDir = process.argv[3] || path.join(__dirname, "..", ".data", "reports");
fs.mkdirSync(outDir, { recursive: true });

http
  .createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      try {
        const report = JSON.parse(body);
        const name = `${report.incidentId || "unknown"}.report.json`;
        fs.writeFileSync(path.join(outDir, name), JSON.stringify(report, null, 2));
        console.log(`[${new Date().toISOString()}] 收到报告 ${name} (${report.agent || "?"}/${report.model || "?"})`);
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: true, file: name }));
      } catch (e) {
        console.error("[receiver] 解析失败:", e.message);
        res.writeHead(400);
        res.end(JSON.stringify({ ok: false, error: e.message }));
      }
    });
  })
  .listen(port, () => console.log(`receiver 监听 http://127.0.0.1:${port}, 报告落盘目录: ${outDir}`));
