# GitHub Push Commands

## After creating your GitHub repository, run these commands:

# 1. Add the GitHub repository as remote origin
# Replace 'yourusername' with your actual GitHub username
git remote add origin https://github.com/yourusername/homecoming-ai-avatar.git

# 2. Rename the default branch to 'main' (GitHub standard)
git branch -M main

# 3. Push your code to GitHub
git push -u origin main

## Alternative: If you prefer SSH (after setting up SSH keys)
# git remote add origin git@github.com:yourusername/homecoming-ai-avatar.git
# git branch -M main
# git push -u origin main

## Verify the push worked
# git remote -v

## Future commits can be pushed with just:
# git push