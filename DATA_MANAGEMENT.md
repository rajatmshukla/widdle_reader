# Widdle Reader - Data Management System

## Overview
Widdle Reader includes comprehensive data management with backup and restore functionality for all user data including tags, favorites, progress, and preferences.

## What's Included in Backups

### Audiobook Data
- Audiobook library paths
- Custom book titles  
- Reading progress percentages
- Last played positions (chapter + timestamp)
- Play timestamps
- Completed books list

### Tags & Favorites System
- All custom tags created by user
- Protected Favorites tag (always included)
- Tag assignments to books
- Tag metadata (creation dates, usage)
- Favorites assignments

### Bookmarks & Preferences
- Custom bookmarks with positions
- Theme and UI preferences
- App settings and configurations

## Features

### Automatic Backups
- On app start
- Every 2 minutes (cache persistence)
- Before data import
- Data health monitoring

### Manual Export/Import
- JSON format backup files
- Version compatibility checking
- Timestamped file names
- Complete data restoration

### Data Protection
- Corruption detection
- Automatic recovery
- Version migration support
- Error handling

## Usage

Access via Settings → Data Management:
- **Backup User Data**: Export all data to JSON file
- **Restore from Backup**: Import data from backup file
- **Check Data Health**: Verify data integrity

## Technical Details

Backup files contain:
- Progress records
- Position data
- Bookmarks
- Tag definitions
- Tag assignments
- Completed books
- Custom titles
- Timestamps

All data is stored locally with user control over backup/restore operations. 