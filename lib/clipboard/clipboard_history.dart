import '../data/models/clipboard_entry.dart';

class ClipboardHistory {
  final List<ClipboardEntry> _entries = [];
  final int _maxLimit = 500;

  Future<void> addEntry(ClipboardEntry entry) async {
    // Basic deduplication if consecutive
    if (_entries.isNotEmpty && _entries.first.contentHash == entry.contentHash) {
      return;
    }
    
    // Auto increment id for in-memory
    final newEntry = entry.copyWith(id: _entries.length + 1);
    _entries.insert(0, newEntry);
    
    if (_entries.length > _maxLimit) {
      _entries.removeRange(_maxLimit, _entries.length);
    }
  }

  Future<List<ClipboardEntry>> getHistory({int limit = 50, int offset = 0}) async {
    if (offset >= _entries.length) return [];
    
    final end = (offset + limit < _entries.length) ? offset + limit : _entries.length;
    return _entries.sublist(offset, end);
  }

  Future<List<ClipboardEntry>> search(String query) async {
    final lowerQuery = query.toLowerCase();
    return _entries.where((e) => e.content.toLowerCase().contains(lowerQuery)).toList();
  }

  Future<void> deleteEntry(int id) async {
    _entries.removeWhere((e) => e.id == id);
  }

  Future<void> clearHistory() async {
    _entries.clear();
  }

  Future<int> getEntryCount() async {
    return _entries.length;
  }
}
