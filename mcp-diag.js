import { spawn } from 'child_process';

const server = spawn('node', ['/Users/gunnarhostetler/.npm/_npx/2e5266eea15d0ccd/node_modules/.bin/notion-mcp-server'], {
  env: {
    ...process.env,
    NOTION_API_KEY: '[REDACTED_SECRET]'
  }
});

let messageId = 1;
let buffer = '';

server.stdout.on('data', (data) => {
  buffer += data.toString();
  const messages = buffer.split('\n');
  buffer = messages.pop(); // keep incomplete part
  for (const msg of messages) {
    if (!msg) continue;
    try {
      const parsed = JSON.parse(msg);
      console.log("RECEIVED:", JSON.stringify(parsed).substring(0, 500));
      if (parsed.id === 2) {
        console.log("Tool call response received!");
        process.exit(0);
      }
    } catch (e) {
      console.log("Parse error:", e.message);
    }
  }
});

server.stderr.on('data', (data) => {
  console.error(`STDERR: ${data.toString()}`);
});

server.on('exit', (code) => {
  console.log(`Server exited with code ${code}`);
  process.exit(code);
});

const initMsg = {
  jsonrpc: "2.0",
  id: messageId++,
  method: "initialize",
  params: {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "test", version: "1.0.0" }
  }
};
server.stdin.write(JSON.stringify(initMsg) + '\n');

setTimeout(() => {
  const callMsg = {
    jsonrpc: "2.0",
    id: messageId++,
    method: "tools/call",
    params: {
      name: "API-post-search",
      arguments: { query: "OpenIntelligence" }
    }
  };
  server.stdin.write(JSON.stringify(callMsg) + '\n');
}, 1000);

setTimeout(() => {
  console.log("Timeout");
  process.exit(1);
}, 5000);
