# Push Praxis to GitHub

Your SSH key is already registered on GitHub as **MrMehulKhanna** (verified: `ssh -T git@github.com`
greets you by name). Nothing more to authenticate — you just need the repo to exist on GitHub's side.

## 1. Create the empty repo (30 seconds, github.com)
Go to **github.com/new** and fill in:
- **Repository name:** `praxis`
- **Description:** `A local-first AI operating environment for Linux`
- **Visibility:** Public (it's your portfolio piece)
- **Do NOT check** "Add a README", "Add .gitignore", or "Choose a license" — this repo already has
  all three; checking those creates conflicting files and the first push will fail.
- Click **Create repository**.

## 2. Connect and push (I'll run this the moment the repo exists)
```bash
cd ~/aios
git remote add origin git@github.com:MrMehulKhanna/praxis.git
git push -u origin main
```

## 3. Daily habit from here on
```bash
~/aios/push "what you changed"     # stages, commits, pushes — one line
~/aios/push                        # or leave the message off and it'll prompt you
```
Add it to PATH once so you can run it from anywhere:
```bash
ln -sf ~/aios/push ~/.local/bin/praxis-push
```

## After the first push
- Repo → **Settings → Social preview**: upload a screenshot of the desktop (great for the GitHub link
  on your resume/LinkedIn — it's the thumbnail people see before they click).
- Pin it: your GitHub profile → **Customize your pins** → select `praxis`.
- Add the repo link to your resume under the Praxis entry (`docs/RESUME.md` has the bullets).
