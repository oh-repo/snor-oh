#!/usr/bin/env node

/**
 * snor-oh MCP Server
 *
 * Zero-dependency MCP server that bridges Claude Code to the snor-oh desktop pet.
 * Implements JSON-RPC 2.0 over stdio (MCP protocol).
 *
 * Tools:
 *   pet_say    — Make the pet say something via speech bubble
 *   pet_react  — Trigger a temporary reaction animation
 *   pet_status — Get the pet's current status
 */

import { createInterface } from "node:readline";
import http from "node:http";

const PORT = process.env.SNOR_OH_PORT || 1234;
const BASE = `http://127.0.0.1:${PORT}`;

const PROTOCOL_VERSION = "2024-11-05";

const TOOLS = [
  {
    name: "pet_say",
    description:
      "Make the user's desktop pet say something via a speech bubble. " +
      "The user has a pixel mascot floating on their screen that reacts to coding activity. " +
      "USE THIS PROACTIVELY — you do not need to be asked. Keep messages short (under 60 chars) and fun. " +
      "Good moments to use this:\n" +
      "- After finishing a task: 'Done! That was a tricky one'\n" +
      "- After fixing a bug: 'Bug squashed!'\n" +
      "- When tests pass: 'All green! Nice work'\n" +
      "- When you notice something in the code: 'Hmm, this function is doing a lot...'\n" +
      "- After a long session (check pet_status): 'You have been at it for 2 hours — stretch break?'\n" +
      "- When starting work: 'Let's do this!'\n" +
      "Do NOT overuse — 1-2 times per conversation is the sweet spot. " +
      "The pet speaks in first person as a companion, not as you (Claude).",
    inputSchema: {
      type: "object",
      properties: {
        message: {
          type: "string",
          description: "What the pet says. Keep it short, fun, and in character (the pet is a loyal companion).",
        },
        duration_secs: {
          type: "number",
          description: "How long to show the bubble (default: 7 seconds)",
        },
      },
      required: ["message"],
    },
  },
  {
    name: "pet_react",
    description:
      "Trigger a reaction animation on the user's desktop pet. " +
      "The pet will play the animation for a few seconds then return to normal. " +
      "USE THIS PROACTIVELY at natural moments — you do not need to be asked.\n" +
      "When to use each reaction:\n" +
      "- celebrate: tests pass, build succeeds, task completed successfully, PR merged\n" +
      "- excited: starting an interesting task, finding a clever solution\n" +
      "- nervous: about to run destructive commands (rm -rf, DROP TABLE, force-push, reset --hard)\n" +
      "- confused: encountering unexpected errors, reading convoluted code, unclear requirements\n" +
      "- sleep: user has been idle for a long time (check pet_status)\n" +
      "Combine with pet_say for maximum effect: react first, then say something. " +
      "Do NOT overuse — use at 2-3 key moments per conversation, not every step.",
    inputSchema: {
      type: "object",
      properties: {
        reaction: {
          type: "string",
          enum: ["celebrate", "nervous", "confused", "excited", "sleep"],
          description: "celebrate | excited | nervous | confused | sleep",
        },
        duration_secs: {
          type: "number",
          description: "How long to show the reaction (default: 3 seconds)",
        },
      },
      required: ["reaction"],
    },
  },
  {
    name: "pet_status",
    description:
      "Get the user's desktop pet status and coding activity summary. " +
      "Returns: pet type, current status, uptime, visitors, peers, and daily usage stats " +
      "(tasks completed today, total coding minutes, longest task, last task duration). " +
      "Check this when:\n" +
      "- Starting a conversation (to greet contextually)\n" +
      "- After completing a big task (to comment on the user's productivity)\n" +
      "- When usage_today.total_busy_mins is high, suggest a break via pet_say\n" +
      "- When tasks_completed is a milestone (10, 25, 50...), celebrate via pet_react\n" +
      "The data helps you make contextual, caring comments about the user's work session.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
];

// --- HTTP helpers ---

function httpPost(path, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE);
    const data = JSON.stringify(body);
    const opts = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(data),
      },
    };
    const req = http.request(opts, (res) => {
      let buf = "";
      res.on("data", (chunk) => (buf += chunk));
      res.on("end", () => resolve({ status: res.statusCode, body: buf }));
    });
    req.on("error", reject);
    req.write(data);
    req.end();
  });
}

function httpGet(path) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE);
    http
      .get(url, (res) => {
        let buf = "";
        res.on("data", (chunk) => (buf += chunk));
        res.on("end", () => resolve({ status: res.statusCode, body: buf }));
      })
      .on("error", reject);
  });
}

// --- JSON-RPC helpers ---

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

function result(id, res) {
  send({ jsonrpc: "2.0", id, result: res });
}

function rpcError(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

// --- Tool handlers ---

async function callTool(name, args) {
  switch (name) {
    case "pet_say": {
      const res = await httpPost("/mcp/say", {
        message: args.message,
        duration_secs: args.duration_secs ?? 7,
      });
      if (res.status === 200) {
        return {
          content: [
            { type: "text", text: `Pet says: "${args.message}"` },
          ],
        };
      }
      return {
        content: [{ type: "text", text: `Failed (${res.status}): ${res.body}` }],
        isError: true,
      };
    }

    case "pet_react": {
      const res = await httpPost("/mcp/react", {
        reaction: args.reaction,
        duration_secs: args.duration_secs ?? 3,
      });
      if (res.status === 200) {
        return {
          content: [
            { type: "text", text: `Pet is reacting: ${args.reaction}` },
          ],
        };
      }
      return {
        content: [{ type: "text", text: `Failed (${res.status}): ${res.body}` }],
        isError: true,
      };
    }

    case "pet_status": {
      const res = await httpGet("/mcp/pet-status");
      if (res.status === 200) {
        try {
          const data = JSON.parse(res.body);
          const usage = data.usage_today || {};
          const tasks = usage.tasks_completed || 0;
          const codingMins = usage.total_busy_mins || 0;
          const busyNow = data.current_busy_secs > 0;
          const busyMins = Math.floor(data.current_busy_secs / 60);
          const uptimeMins = Math.floor(data.uptime_secs / 60);

          // Build a natural summary Claude can act on
          let status;
          if (data.sleeping) {
            status = "User is away (pet sleeping).";
          } else if (busyNow) {
            status = `User is working right now (${busyMins > 0 ? busyMins + " min into current task" : "just started"}).`;
          } else {
            status = "User is idle — between tasks.";
          }

          let activity;
          if (tasks === 0) {
            activity = "No tasks completed yet today.";
          } else {
            activity = `Today: ${tasks} task${tasks > 1 ? "s" : ""} done, ${codingMins} min of active coding.`;
          }

          const parts = [status, activity];

          if (codingMins >= 120) {
            parts.push(`Note: ${codingMins} min of coding today — consider suggesting a break.`);
          } else if (busyNow && busyMins >= 45) {
            parts.push(`Note: current task running ${busyMins} min — a long one.`);
          }

          if (data.visitors && data.visitors.length > 0) {
            parts.push(`Visitors on screen: ${data.visitors.map((v) => v.nickname).join(", ")}.`);
          }
          if (data.peers_nearby > 0) {
            parts.push(`${data.peers_nearby} peer${data.peers_nearby > 1 ? "s" : ""} nearby on LAN.`);
          }

          return {
            content: [{ type: "text", text: parts.join(" ") }],
          };
        } catch {
          return { content: [{ type: "text", text: res.body }] };
        }
      }
      return {
        content: [{ type: "text", text: `Failed (${res.status}): ${res.body}` }],
        isError: true,
      };
    }

    default:
      return {
        content: [{ type: "text", text: `Unknown tool: ${name}` }],
        isError: true,
      };
  }
}

// --- Message dispatcher ---

async function handleMessage(msg) {
  // Notifications (no id) — just acknowledge
  if (msg.id === undefined) return;

  switch (msg.method) {
    case "initialize":
      result(msg.id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "snor-oh", version: "1.0.0" },
      });
      break;

    case "ping":
      result(msg.id, {});
      break;

    case "tools/list":
      result(msg.id, { tools: TOOLS });
      break;

    case "tools/call":
      try {
        const res = await callTool(
          msg.params.name,
          msg.params.arguments || {}
        );
        result(msg.id, res);
      } catch (err) {
        result(msg.id, {
          content: [
            {
              type: "text",
              text: `Error: ${err.message}. Is snor-oh running?`,
            },
          ],
          isError: true,
        });
      }
      break;

    default:
      rpcError(msg.id, -32601, `Method not found: ${msg.method}`);
  }
}

// --- Main: read stdin line by line ---

const rl = createInterface({ input: process.stdin, terminal: false });

rl.on("line", async (line) => {
  if (!line.trim()) return;
  try {
    const msg = JSON.parse(line);
    await handleMessage(msg);
  } catch (err) {
    process.stderr.write(`[snor-oh-mcp] parse error: ${err.message}\n`);
  }
});

// Graceful shutdown
process.on("SIGINT", () => process.exit(0));
process.on("SIGTERM", () => process.exit(0));
