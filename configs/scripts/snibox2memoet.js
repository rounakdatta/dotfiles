const puppeteer = require('puppeteer-core');
const { exec } = require('child_process');

// Copy the existing user directory to a temporary directory
// (this is so that we preserve the cookies from our existing logged in session)
const sourcePath = '~/Library/Application\\ Support/Google/Chrome/Default';
let randomSeedString = Math.random().toString(36).substring(2, 7)
const destinationPath = `/tmp/chromy-${randomSeedString}`;
const chromeDebuggingPort = 9222

const userDirectorySetupCommand = `mkdir -p ${destinationPath}/Default; cp -R ${sourcePath} ${destinationPath}/Default`;

console.log("Creating a temp directory and starting to copy user data directory...")
exec(userDirectorySetupCommand, (err) => {
    if (err) {
        console.error(`User data directory copy command exec error: ${err}`);
        return;
    }
    console.log(`Finished setting up the users data directory at ${destinationPath}!`);

	// launch chrome instance with remote debugging port enabled (for puppeteer to connect)
    const chromeLaunchCommand = `/Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --headless=new --remote-debugging-port=${chromeDebuggingPort} --user-data-dir=${destinationPath}/Default`;

    console.log("Starting to launch Chrome instance...")
    exec(chromeLaunchCommand, (err) => {
        if (err) {
            console.error(`Chrome launch command exec error: ${err}`);
            return;
        }
    });
    console.log("Successfully launched Chrome instance with existing user data!");

	// wait for the instance to start up, and then connect using puppeteer to perform programmatic browser interactions
    setTimeout(async () => {
        try {
            console.log(`Attempting to connect to remote debugging port ${chromeDebuggingPort} ...`);
            const browser = await puppeteer.connect({
                browserURL: `http://localhost:${chromeDebuggingPort}`,
            });

            const page = await browser.newPage();
            await page.goto('https://snibox.taptappers.club/api/v1/data/default-state');

            const content = await page.evaluate(() => document.body.innerText);
            console.log(content);
            page.close();

            await browser.close();
            console.log("Job done, disconnected from Chrome");
        } catch (error) {
            console.error(`Interaction error with Chrome via Puppeteer: ${error}`);
        }
    }, 5000);
});
