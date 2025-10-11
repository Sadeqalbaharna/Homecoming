# Avatar Assets

## Missing GIF Files

The following GIF animation files are required for the app to function properly:

- `idle.gif` - Default idle animation (was ~55MB)
- `attention.gif` - Attention-getting animation (was ~52MB) 
- `thinking.gif` - Thinking/processing animation (was ~52MB)
- `speaking.gif` - Speaking animation (was ~110MB)

## Why Are They Missing?

These files exceeded GitHub's file size limits (100MB max, 50MB recommended). 

## Solutions:

### Option 1: Use Git LFS (Large File Storage)
GitHub supports Git LFS for large files, but requires setup.

### Option 2: Optimize Assets
Reduce GIF file sizes through:
- Lower resolution
- Reduced frame rate
- Shorter animation loops
- Better compression

### Option 3: Use Placeholder Assets
Create smaller placeholder GIFs for development/testing.

### Option 4: External Asset Hosting
Host large assets on cloud storage and download at runtime.

## Temporary Workaround

For now, you can:
1. Create simple placeholder GIFs
2. Use static images instead of animations
3. Download the original assets from the developer

## Original Asset Locations

If you have access to the original development environment, the assets were located at:
```
assets/avatar/idle.gif (54.87 MB)
assets/avatar/attention.gif (52.28 MB)  
assets/avatar/thinking.gif (52.49 MB)
assets/avatar/speaking.gif (109.81 MB)
```

## App Functionality

The app will still run without these assets, but avatar animations will not display properly. Consider implementing fallback behavior or placeholder images.