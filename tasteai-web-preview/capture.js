const puppeteer = require('puppeteer-core');
const fs = require('fs');

(async () => {
  const chrome = process.env.CHROME_BIN;
  const browser = await puppeteer.launch({executablePath: chrome, headless: true, args:['--no-sandbox','--disable-dev-shm-usage']});
  const page = await browser.newPage();
  await page.setViewport({width:430,height:900,deviceScaleFactor:1});
  const sleep = ms => new Promise(r=>setTimeout(r,ms));
  const shot = async name => { await sleep(900); await page.screenshot({path:`screens/${name}.png`}); };
  await page.goto('http://127.0.0.1:8080',{waitUntil:'networkidle0'});
  await sleep(5000);
  await shot('01_login');

  // Sign in
  await page.mouse.click(215,650); await sleep(1800); await shot('02_discover');

  // Search/filter controls
  await page.mouse.click(375,280); await sleep(900); await shot('03_filters');

  // Map bottom navigation
  await page.mouse.click(160,860); await sleep(1000); await shot('04_map');

  // Back to Discover and open first place
  await page.mouse.click(55,860); await sleep(700);
  await page.mouse.click(215,620); await sleep(1000); await shot('05_details');

  // Back, save first place, then favorites
  await page.mouse.click(32,32); await sleep(700);
  await page.mouse.click(378,555); await sleep(600);
  await page.mouse.click(270,860); await sleep(900); await shot('06_favorites');

  // Settings
  await page.mouse.click(375,860); await sleep(900); await shot('07_settings');

  // Preferences bottom sheet
  await page.mouse.click(215,180); await sleep(900); await shot('08_preferences');
  await page.keyboard.press('Escape'); await sleep(500);

  // Compare bottom sheet
  await page.mouse.click(215,260); await sleep(900); await shot('09_compare');
  await page.keyboard.press('Escape'); await sleep(500);

  // AI status
  await page.mouse.click(215,340); await sleep(900); await shot('10_ai_status');
  await page.keyboard.press('Escape');

  // Arabic switch in Settings
  await page.mouse.click(215,105); await sleep(900); await shot('11_arabic_settings');

  await browser.close();
})();
