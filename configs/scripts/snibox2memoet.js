const puppeteer = require('puppeteer-core');
const { exec } = require('child_process');
const request = require('request');

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

            const content = await page.evaluate(() => document.getElementById("jsonFormatterRaw").querySelector("pre").innerText);
            // this is required because of the beautify JSON browser extension that I happen to use
            processSnippetsAsNotes(content)
            page.close();

            await browser.close();
            console.log("Job done, disconnected from Chrome");
        } catch (error) {
            console.error(`Interaction error with Chrome via Puppeteer: ${error}`);
        }
    }, 5000);
});

// this holds just the card data structure, stuff only required for creating the card on Memoet
class MemoetNoteCard {
    constructor(title, description, content) {
        this.title = title;
        this.description = description;
        this.content = content;
    }
}

// this holds additional information, like the SHA256 of the card data, this will help in evaluating whether or not an update is required
class MemoetNote {
    constructor(noteCard, hash) {
        this.card = noteCard;
        this.hash = hash;
    }
}

// this function transforms the Snibox output to corresponding Note data structure
function processSnippetsAsNotes(rawJsonContents) {
    const jsonContent = JSON.parse(rawJsonContents)
    
    jsonContent.snippets.forEach(snippet => {
        const note = constructNote(snippet);
        publishNote(note);
    });
}

function constructNote(snippet) {
    let content = ""
    snippet.snippetFiles.forEach(file => {
        // we'll make sure to put the filename before pasting the contents of the file
        if (file.language == "markdown") {
            // markdown should be pasted directly
            content += `_${file.title}_\n${file.content}\n---\n`;
        } else {
            // everything else should be enclosed in triple-backticks code block
            content += `_${file.title}_\n\`\`\`${file.language}\n${file.content}\n\`\`\`\n---\n`;
        }
    });
    const title = `${snippet.id}-${snippet.label.name}: ${snippet.title}`
    const card = new MemoetNoteCard(title, snippet.description, content);
    const note = new MemoetNote(card, simpleHash(content));
    return note;
}

function simpleHash(str) {
    let hash = 5381;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) + hash) + char;
    }
    return (hash >>> 0).toString();
}

function publishNote(note) {
    var options = {
    'method': 'POST',
    'url': 'http://localhost:4000/api/decks/b98f032d-e3b1-474b-a0d7-f197953042cd/notes',
    'headers': {
        'Authorization': '65edf454-5b02-4aa2-8496-052b11a5bc1f',
        'Content-Type': 'application/json'
    },
    body: JSON.stringify({
        "note": {
            "title": note.card.title,
            "content": note.card.description,
            "type": "flash_card",
            "hint": note.card.content
        }
    })

    };
    request(options, function (error, response) {
        if (error) throw new Error(error);
            console.log(response.body);
    });
}
