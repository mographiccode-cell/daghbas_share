const puppeteer = require('puppeteer-core');

(async () => {
  const chrome = process.env.CHROME_BIN;
  const browser = await puppeteer.launch({executablePath: chrome, headless: true, args:['--no-sandbox','--disable-dev-shm-usage']});
  const page = await browser.newPage();
  await page.setViewport({width:430,height:900,deviceScaleFactor:1});
  const sleep = ms => new Promise(r=>setTimeout(r,ms));
  const shot = async name => { await sleep(1100); await page.screenshot({path:`screens/${name}.png`}); };
  await page.goto('http://127.0.0.1:8080',{waitUntil:'networkidle0'});
  await sleep(5000);
  await shot('01_login');

  // Sign in -> Discover
  await page.mouse.click(215,650); await sleep(1700); await shot('02_discover');

  // Filters panel
  await page.mouse.click(369,208); await sleep(1000); await shot('03_filters');
  await page.mouse.click(369,208); await sleep(600); // collapse

  // Manual location sheet
  await page.mouse.click(345,305); await sleep(1000); await shot('04_location');
  await page.keyboard.press('Escape'); await sleep(600);

  // Save and compare first place from Discover
  await page.mouse.click(378,460); await sleep(500);
  await page.mouse.click(370,679); await sleep(500);

  // Details
  await page.mouse.click(190,679); await sleep(1100); await shot('05_details');

  // Write review sheet
  await page.mouse.click(350,619); await sleep(1000); await shot('06_write_review');
  await page.keyboard.press('Escape'); await sleep(600);

  // Map through details
  await page.mouse.click(110,415); await sleep(1100); await shot('07_map');

  // Favorites should include saved first place
  await page.mouse.click(270,860); await sleep(1000); await shot('08_favorites');

  // Settings
  await page.mouse.click(375,860); await sleep(900); await shot('09_settings');

  // Preferences sheet via trailing arrow
  await page.mouse.click(370,196); await sleep(1100); await shot('10_preferences');
  await page.keyboard.press('Escape'); await sleep(600);

  // Compare sheet
  await page.mouse.click(370,277); await sleep(1100); await shot('11_compare');
  await page.keyboard.press('Escape'); await sleep(600);

  // AI status sheet
  await page.mouse.click(370,358); await sleep(1100); await shot('12_ai_status');
  await page.keyboard.press('Escape'); await sleep(600);

  // Arabic secondary language
  await page.mouse.click(370,116); await sleep(1000); await shot('13_arabic_settings');

  await browser.close();
})();
