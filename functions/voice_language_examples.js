const MAX_FILE_BYTES = 16384;
const MAX_EXAMPLES = 50;
const WORDS = new Set([
  "shilingi", "senti", "sifuri", "moja", "mbili", "tatu", "nne", "tano",
  "sita", "saba", "nane", "tisa", "kumi", "ishirini", "thelathini",
  "arobaini", "hamsini", "sitini", "sabini", "themanini", "tisini",
  "mia", "elfu", "laki", "milioni", "bilioni", "trilioni", "na", "hasi",
  "nukta", "asilimia",
]);

function parseCsv(input) {
  if (typeof input !== "string" || Buffer.byteLength(input, "utf8") > MAX_FILE_BYTES) {
    throw new Error("CSV must be UTF-8 and at most 16 KB.");
  }
  const rows = [];
  let row = [], field = "", quoted = false, closedQuote = false;
  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (quoted) {
      if (ch === '"' && input[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') { quoted = false; closedQuote = true; }
      else field += ch;
    } else if (ch === '"') {
      if (field || closedQuote) throw new Error("Invalid CSV quoting.");
      quoted = true;
    } else if (ch === "," || ch === "\n" || ch === "\r") {
      row.push(field); field = ""; closedQuote = false;
      if (ch !== ",") {
        if (ch === "\r" && input[i + 1] === "\n") i++;
        if (row.some((cell) => cell.trim())) rows.push(row);
        row = [];
      }
    } else {
      if (closedQuote) throw new Error("Invalid CSV quoting.");
      field += ch;
    }
  }
  if (quoted) throw new Error("Unclosed CSV quote.");
  if (field || row.length || closedQuote) {
    row.push(field);
    if (row.some((cell) => cell.trim())) rows.push(row);
  }
  if (rows.length < 2 || rows.length > MAX_EXAMPLES + 1 ||
      rows[0].length !== 2 ||
      rows[0][0].replace(/^\uFEFF/, "").trim().toLowerCase() !== "number" ||
      rows[0][1].trim().toLowerCase() !== "spoken") {
    throw new Error("CSV needs number,spoken headers and 1 to 50 examples.");
  }
  const seen = new Set();
  return rows.slice(1).map((cells, index) => {
    if (cells.length !== 2) throw new Error(`Row ${index + 2} must have exactly two columns.`);
    const number = cells[0].trim();
    const spoken = cells[1].trim().replace(/\s+/g, " ").toLowerCase();
    if (!/^-?(?:0|[1-9]\d{0,14})(?:\.\d{1,4})?%?$/.test(number)) {
      throw new Error(`Row ${index + 2} has an invalid number. Do not use thousands separators.`);
    }
    if (!spoken || spoken.length > 200 ||
        !spoken.split(" ").every((word) => WORDS.has(word))) {
      throw new Error(`Row ${index + 2} must contain only supported Swahili number words.`);
    }
    if (seen.has(number)) throw new Error(`Row ${index + 2} repeats a number.`);
    seen.add(number);
    return { number, spoken };
  });
}

function validateExamples(examples) {
  if (!Array.isArray(examples) || examples.length === 0 || examples.length > MAX_EXAMPLES) {
    throw new Error("Invalid examples.");
  }
  const csv = "number,spoken\n" + examples.map((item) => {
    if (!item || typeof item.number !== "string" || typeof item.spoken !== "string" ||
        /[,\r\n]/.test(item.number) || /[,\r\n]/.test(item.spoken)) throw new Error("Invalid example.");
    return `${item.number},${item.spoken}`;
  }).join("\n");
  return parseCsv(csv);
}

module.exports = { MAX_FILE_BYTES, parseCsv, validateExamples };
