import * as cheerio from "cheerio";
import fetch from "node-fetch";
import pdf from "pdf-parse";
import fs from "fs-extra";
import dayjs from "dayjs";

const ELM_URL = "https://www.eastlondonmosque.org.uk/prayer-times";
const MI_PAGE = "https://www.masjidibrahim.co.uk/prayer-timetable/";

const DATA_DIR = "web/data";
const UA = "MyPrayerTimes/1.0 (personal, non-commercial)";
const pad = n => n < 10 ? `0${n}` : `${n}`;

// ---------- Fetch Helpers ----------
async function fetchText(url) {
  const r = await fetch(url, { headers: { "User-Agent": UA } });
  if (!r.ok) throw new Error(`Fetch ${r.status} ${url}`);
  return r.text();
}

async function fetchBuffer(url) {
  const r = await fetch(url, { headers: { "User-Agent": UA } });
  if (!r.ok) throw new Error(`Fetch ${r.status} ${url}`);
  const ab = await r.arrayBuffer();
  return Buffer.from(ab);
}

// ---------- ELM START TIMES ----------
async function buildElmYear(year) {
  const html = await fetchText(ELM_URL);
  const lines = html.split(/\r?\n/).map(s => s.trim());

  const rowRe = new RegExp(`\\b\\d{2}/\\d{2}/${year}\\b.*`, "i");
  const timeRe = /\b\d{1,2}:\d{2}\b/g;

  const months = Array.from({ length: 12 }, (_, i) => pad(i + 1));
  const monthData = Object.fromEntries(
    months.map(m => [m, { source: "ELM", year, month: m, days: {} }])
  );

  for (const line of lines) {
    if (!rowRe.test(line)) continue;

    const dateMatch = line.match(/\d{2}\/\d{2}\/\d{4}/);
    if (!dateMatch) continue;
    const [dd, mm] = dateMatch[0].split("/");

    const times = line.match(timeRe) || [];
    if (times.length < 11) continue;

    monthData[mm].days[dd] = {
      sunrise: times[0],
      fajr: times[1],
      zuhr: times[3],
      asr_mithl1: times[5],
      asr_mithl2: times[6],
      maghrib: times[8],
      isha: times[10]
    };
  }

  await fs.ensureDir(DATA_DIR);
  for (const mm of months) {
    await fs.writeJson(`${DATA_DIR}/elm-${year}-${mm}.json`, monthData[mm], { spaces: 2 });
  }
}

// ---------- MI IQAMAH (PDF) ----------
function monthName(m) {
  return dayjs().month(m - 1).format("MMMM");
}

async function findMiPdf(year, month) {
  const html = await fetchText(MI_PAGE);
  const $ = cheerio.load(html);

  const links = $("a[href$='.pdf']")
    .map((_, el) => $(el).attr("href"))
    .get();

  const targetName = `PrayerTimetable${monthName(month)}${year}.pdf`.toLowerCase();
  let found = links.find(h => (h || "").toLowerCase().includes(targetName));

  if (!found) found = links.find(h => (h || "").toLowerCase().includes(monthName(month).toLowerCase()));
  if (!found) found = links[0];
  if (!found) throw new Error("No MI PDF link found");

  if (!found.startsWith("http")) found = new URL(found, MI_PAGE).href;
  return found;
}

async function buildMiMonth(year, month) {
  const pdfUrl = await findMiPdf(year, month);
  const buff = await fetchBuffer(pdfUrl);
  const parsed = await pdf(buff);

  const lines = parsed.text.split("\n").map(s => s.trim()).filter(Boolean);
  const rowRe = /^(\d{1,2})\s+\S+\s+\w{3}\s+(.+)$/;
  const timeRe = /\b\d{1,2}:\d{2}\b/g;

  const days = {};

  for (const line of lines) {
    const m = line.match(rowRe);
    if (!m) continue;

    const day = pad(parseInt(m[1], 10));
    const times = m[2].match(timeRe) || [];

    if (times.length >= 11) {
      days[day] = {
        fajr: times[1],
        zuhr: times[4],
        asr: times[7],
        maghrib: times[8],
        isha: times[10]
      };
    }
  }

  await fs.ensureDir(DATA_DIR);
  await fs.writeJson(`${DATA_DIR}/mi-${year}-${pad(month)}.json`, {
    source: "UKIM Masjid Ibrahim",
    year,
    month: pad(month),
    days
  }, { spaces: 2 });
}

// ---------- MAIN ----------
async function main() {
  const today = dayjs();
  const year = today.year();

  await buildElmYear(year);

  await buildMiMonth(year, today.month() + 1);
  await buildMiMonth(year, today.add(1, "month").month() + 1);

  console.log("✔ Updated ELM + MI monthly JSON files.");
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
