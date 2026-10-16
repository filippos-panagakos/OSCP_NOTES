

1. Account Takeover via IDOR Logic Flaw (`/reset-password`)


- **Vulnerability:** Broken Authentication / Insecure Direct Object Reference (IDOR).
- **Root Cause:** The application validated that the reset token existed and was unexpired, but it failed to verify that the `token` actually belonged to the `email` submitted in the request payload.
- **Exploitation:** An attacker requests a legitimate password reset token for their own account (`test@email.htb`), then submits that valid token alongside the target email (`admin@armaxis.htb`) to rewrite the admin account password


```
// 1. It fetches the reset record using ONLY the token
const reset = await getPasswordReset(token);
if (!reset) return res.status(400).send("Invalid or expired token.");

// 2. It fetches the target user using ONLY the email parameter from the request body
const user = await getUserByEmail(email);
if (!user) return res.status(404).send("User not found.");

// 3. It resets the password for 'user' without verifying if reset.email === email
await updateUserPassword(user.id, newPassword);

```


## LFI


Looking at `markdown.js`:

JavaScript

```
content.replace(/\!\[.*?\]\((.*?)\)/g, (match, url) => {
    try {
        const fileContent = execSync(`curl -s ${url}`);
        const base64Content = Buffer.from(fileContent).toString("base64");
        return `<img src="data:image/*;base64,${base64Content}" alt="Embedded Image">`;
    } catch (err) {
        ...
    }
})
```

### Key Takeaways

1. **Unsanitized Command Execution (`execSync`):** The application takes the extraction group inside the markdown image parenthesis `(url)` and passes it directly into a system command string (`curl -s ${url}`) executed via `execSync`.

2. **File Protocol Support in `curl`:** Because the underlying shell command uses `curl`, it inherits all of `curl`'s default protocol handlers. Beyond standard `http://` or `https://` schemas, `curl` natively supports fetching local system files using the `file://` protocol (e.g., `file:///path/to/file`).

3. **Base64 Rendering:** Instead of displaying the image directly, the backend reads the raw STDOUT output returned by `curl`, encodes it into Base64, and embeds it directly inside an HTML `<img>` tag standard data URI

When `curl` reads a plain text file via `file:///`, the text contents get converted into Base64 and embedded into the page source/response. Inspecting the resulting element or decoding the Base64 string allows the retrieved content to be viewed