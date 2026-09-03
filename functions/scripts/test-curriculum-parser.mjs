import {readFileSync} from "fs";
import {createRequire} from "module";

const require = createRequire(import.meta.url);
const {parseCurriculumText} = require("../lib/curriculumPdfParser.js");

const samples = [
  {
    name: "inline",
    text: `
수업일자 일수 교과목 내용
2026년 6월 16일 화요일 1 프로그래밍과 데이터 기초 Python
2026년 6월 17일 수요일 2 프로그래밍과 데이터 기초 변수와 자료형
`,
  },
  {
    name: "tab-separated",
    text: `
수업일자\t일수\t교과목\t내용
2026년 6월 16일 화요일\t1\t프로그래밍과 데이터 기초\tPython
2026년 6월 17일 수요일\t2\t프로그래밍과 데이터 기초\t변수와 자료형
`,
  },
  {
    name: "stacked-cells",
    text: `
수업일자
일수
교과목
내용
2026년 6월 16일 화요일
1
프로그래밍과 데이터 기초
Python
2026년 6월 17일 수요일
2
프로그래밍과 데이터 기초
변수와 자료형
`,
  },
  {
    name: "fragmented-date",
    text: `
2026년
6월
16일
화요일
1
프로그래밍과 데이터 기초
Python
2026년
6월
17일
수요일
2
프로그래밍과 데이터 기초
변수와 자료형
`,
  },
];

let failed = 0;
for (const sample of samples) {
  const days = parseCurriculumText(sample.text);
  const ok = days.length === 2 && days[0].dayNumber === 1 && days[1].subject;
  console.log(`${ok ? "OK" : "FAIL"} ${sample.name}: ${days.length} days`, days);
  if (!ok) failed++;
}

if (process.argv[2]) {
  const pdfPath = process.argv[2];
  const pdfParse = require("pdf-parse");
  const buffer = readFileSync(pdfPath);
  pdfParse(buffer).then((parsed) => {
    console.log("\n--- extracted text preview ---");
    console.log(parsed.text.slice(0, 2000));
    const days = parseCurriculumText(parsed.text);
    console.log(`\nParsed ${days.length} days`);
    console.log(days.slice(0, 5));
    process.exit(days.length > 0 ? 0 : 1);
  });
} else {
  process.exit(failed > 0 ? 1 : 0);
}
