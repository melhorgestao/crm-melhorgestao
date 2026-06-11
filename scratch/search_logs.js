import fs from 'fs';
import readline from 'readline';

async function search() {
  const filePath = 'C:\\Users\\victo\\.gemini\\antigravity\\brain\\e82098a5-53f4-4751-b6a7-eec1bd8af634\\.system_generated\\logs\\transcript.jsonl';
  
  const fileStream = fs.createReadStream(filePath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  console.log("Searching logs for passwords or database details...");
  let lineNum = 0;
  for await (const line of rl) {
    lineNum++;
    if (line.toLowerCase().includes('senha') || line.toLowerCase().includes('password') || line.toLowerCase().includes('pass') || line.toLowerCase().includes('db_') || line.toLowerCase().includes('db-')) {
      console.log(`[Line ${lineNum}] Match found:`);
      console.log(line.substring(0, 500) + (line.length > 500 ? '...' : ''));
    }
  }
  console.log("Search complete.");
}

search().catch(err => console.error(err));
