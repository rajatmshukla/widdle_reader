📱 **Enhanced Library Screen UI Definition**

Overall Layout Structure

┌─────────────────────────────────────┐
│ App Bar (Fixed, Non-Collapsing)    │
│ ├─ Logo + "Widdle Reader" Title     │
│ ├─ Sleep Timer Icon                 │
│ ├─ Refresh Button                   │
│ └─ Settings Icon                    │
├─────────────────────────────────────┤
│ Toggle Bar (Always Visible)        │
│ [Library] [Tags] - Pill Style      │
├─────────────────────────────────────┤
│                                     │
│ Main Content Area (Scrollable)     │
│ ├─ Library Mode: Audiobook Grid    │
│ └─ Tags Mode: Tag List/Books       │
│                                     │
└─────────────────────────────────────┘
│ Floating Action Button             │
└─────────────────────────────────────┘

Toggle Design Specifications
- **Style**: YouTube Music-inspired pill toggle
- **Position**: Fixed below app bar, always visible
- **Size**: Compact 12x6px padding per button
- **Colors**: 
  - Background: `surfaceContainerHighest` with 50% alpha
  - Selected: `primary` color
  - Unselected: `onSurfaceVariant` color
- **Typography**: 13px font, medium weight
- **Shape**: 16px rounded container, 12px rounded buttons
- **No Icons**: Text-only for clean appearance

### **Content Layout**
- **Padding**: 4px horizontal (wider tiles)
- **Grid**: Responsive (2-4 columns based on screen width)
- **Animations**: Fade-in transitions, scale effects
- **Empty States**: Illustrated with icons and helpful text

---

## 🏷️ **Comprehensive Tagging Feature Definition**

### **Core Tagging System**

#### **Tag Model Structure**
```dart
class Tag {
  String name;           // Unique tag identifier
  DateTime createdAt;    // Creation timestamp
  DateTime lastUsedAt;   // Last usage for sorting
  int bookCount;         // Number of books with this tag
  bool isFavorites;      // Special "Favorites" tag flag
}
```

#### **Audiobook Tag Integration**
```dart
class Audiobook {
  Set<String> tags;      // Multiple tags per book
  bool isFavorited;      // Quick favorites access
  
  // Methods:
  hasTag(String tagName)
  addTag(String tagName)
  removeTag(String tagName)
  toggleFavorite()
}
```

### **Tag Management Features**

#### **1. Favorites System**
- **Special Tag**: "Favorites" always appears first
- **Visual**: Red heart icon (filled/outlined states)
- **Quick Access**: Heart button on each audiobook tile
- **Persistence**: Stored as both tag and boolean flag

#### **2. Custom Tags**
- **Creation**: On-demand via dialog or FAB
- **Validation**: Unique names, no duplicates
- **Assignment**: Multiple tags per audiobook
- **Removal**: Individual tag deletion (except Favorites)

#### **3. Tag Sorting Options**
- **Alphabetical (A-Z)**: Standard alphabetical order
- **Reverse Alphabetical (Z-A)**: Reverse order
- **Recently Used**: Based on `lastUsedAt` timestamp
- **Recently Created**: Based on `createdAt` timestamp
- **Favorites Priority**: Always pinned first regardless of sort

### **User Interface Components**

#### **1. Tag List View**
```
┌─────────────────────────────────────┐
│ Sort Dropdown: [A-Z ▼]             │
├─────────────────────────────────────┤
│ ❤️ Favorites (5 books)    >        │
│ 📚 Fiction (12 books)     >        │
│ 🎓 Educational (8 books)  >        │
│ 📖 Biography (3 books)    >        │
└─────────────────────────────────────┘
```

#### **2. Tag Assignment Dialog**
```
┌─────────────────────────────────────┐
│ Manage Tags for "Book Title"       │
├─────────────────────────────────────┤
│ ☑️ Favorites                       │
│ ☑️ Fiction                         │
│ ☐ Educational                      │
│ ☐ Biography                        │
├─────────────────────────────────────┤
│ [+ Create New Tag]                  │
│ [Cancel] [Save]                     │
└─────────────────────────────────────┘
```

#### **3. Audiobook Tile Integration**
```
┌─────────────────────────────────────┐
│ [Cover] Book Title                  │
│         Author Name                 │
│         Progress: 45%               │
│         ❤️ 🏷️                      │
└─────────────────────────────────────┘
```

### **State Management Architecture**

#### **Riverpod Tag Provider**
```dart
class TagProvider extends StateNotifier<AsyncValue<List<Tag>>> {
  // Core Operations:
  loadTags()
  createTag(String name)
  deleteTag(String name)
  updateTagUsage(String name)
  setSortOption(TagSortOption option)
  
  // Computed Properties:
  sortedTags
  currentSortOption
}
```

#### **Provider Integration**
```dart
class AudiobookProvider extends ChangeNotifier {
  // Tag Operations:
  addTagToAudiobook(String audiobookId, String tagName)
  removeTagFromAudiobook(String audiobookId, String tagName)
  toggleFavorite(String audiobookId)
  getAudiobooksByTag(String tagName)
  getAllTags()
}
```

### **Data Persistence**

#### **Storage Structure**
```json
{
  "tags": [
    {
      "name": "Favorites",
      "createdAt": "2024-01-01T00:00:00Z",
      "lastUsedAt": "2024-01-15T10:30:00Z",
      "bookCount": 5,
      "isFavorites": true
    }
  ],
  "audiobook_tags": {
    "audiobook_id_1": ["Favorites", "Fiction"],
    "audiobook_id_2": ["Educational", "Biography"]
  }
}
```

### **Navigation Flow**

#### **User Journey**
1. **Library View**: See all audiobooks with tag indicators
2. **Toggle to Tags**: Switch to tag management mode
3. **Tag Selection**: Tap tag to see filtered books
4. **Tag Management**: Long-press or button to manage tags
5. **Book Tagging**: Use heart icon or tag button on tiles

#### **Empty States**
- **No Tags**: Illustrated prompt to create first tag
- **No Tagged Books**: Helpful message to add tags to books
- **Empty Library**: Standard empty library with add books prompt

### **Error Handling & Edge Cases**
- **Duplicate Tags**: Prevention with user feedback
- **Tag Deletion**: Confirmation dialog for non-empty tags
- **Data Corruption**: Automatic cleanup and recovery
- **Performance**: Lazy loading for large tag collections
- **Sync Issues**: Conflict resolution for concurrent edits

This comprehensive tagging system provides intuitive organization while maintaining the app's existing design language and user experience patterns.