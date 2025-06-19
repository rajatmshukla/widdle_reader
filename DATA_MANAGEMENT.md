# Widdle Reader - Data Management System

## Overview
Widdle Reader v1.0.4 includes a completely overhauled data management system with comprehensive backup and restore functionality, corruption detection, automatic recovery, and real-time health monitoring for all user data including tags, favorites, progress, and preferences.

## What's Included in Backups

### Audiobook Data
- Audiobook library paths
- Custom book titles  
- Reading progress percentages
- Last played positions (chapter + timestamp)
- Play timestamps
- Completed books list

### Tags & Favorites System
- All custom tags created by user with rename/delete functionality
- Bulletproof Favorites tag (cannot be deleted or renamed - always protected)
- Tag assignments to books with full consistency maintenance
- Tag metadata (creation dates, usage statistics, integrity data)
- Favorites assignments with automatic fallback mechanisms
- Tag rename operations with complete data integrity preservation

### Bookmarks & Preferences
- Custom bookmarks with positions
- Theme and UI preferences
- App settings and configurations

## Features

### Automatic Backups
- On app start with integrity verification
- Every 2 minutes (cache persistence with validation)
- Before any data import or modification operations
- Continuous data health monitoring and statistics
- Automatic corruption detection during save operations

### Manual Export/Import
- JSON format backup files with enhanced metadata
- Advanced version compatibility checking and migration
- Timestamped file names with corruption detection signatures
- Complete data restoration with fallback mechanisms
- Backup validation before import operations

### Data Protection & Recovery
- Multi-layer corruption detection using checksums and validation
- Automatic recovery with multiple fallback strategies
- Version migration support with backward compatibility
- Comprehensive error handling with detailed reporting
- Data consistency checks across all operations
- Bulletproof system tag protection (Favorites cannot be corrupted)

## Usage

Access via Settings → Data Management:
- **Backup User Data**: Export all data to JSON file with corruption detection
- **Restore from Backup**: Import data from backup file with validation and recovery
- **Check Data Health**: Comprehensive data integrity verification with statistics
- **Tag Management**: View tag statistics, usage data, and system health
- **Data Recovery**: Automatic and manual recovery options for corrupted data

## Technical Details

Backup files contain:
- Progress records with integrity checksums
- Position data with validation metadata
- Bookmarks with timestamp verification
- Tag definitions including system tag protection flags
- Tag assignments with consistency validation
- Completed books with progress correlation
- Custom titles with metadata preservation
- Timestamps and version information
- Data integrity signatures and validation checksums
- Tag usage statistics and health monitoring data
- Bulletproof Favorites tag protection metadata

## New in v1.0.4

### Enhanced Tag System
- **Tag Rename Functionality**: Rename any custom tag while preserving all assignments
- **Bulletproof Favorites**: System-protected tag that cannot be deleted or renamed
- **Tag Statistics**: View usage data and health metrics for all tags
- **Enhanced UI**: Dialog-based tag management for better user experience

### Advanced Data Protection
- **Corruption Detection**: Multi-layer validation with automatic recovery
- **Data Health Dashboard**: Real-time monitoring of data integrity
- **Enhanced Backup System**: Improved reliability with fallback mechanisms
- **Version Migration**: Seamless updates with backward compatibility

All data is stored locally with enhanced user control over backup/restore operations and comprehensive data protection. 