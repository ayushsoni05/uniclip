import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/clipboard_providers.dart';
import '../../data/models/clipboard_entry.dart';

/// History screen showing real clipboard entries with search and copy-on-tap.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allHistory = ref.watch(clipboardHistoryListProvider);

    final filteredHistory = _query.isEmpty
        ? allHistory
        : allHistory
            .where((e) =>
                e.content.toLowerCase().contains(_query) ||
                e.sourceDeviceName.toLowerCase().contains(_query))
            .toList();

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Clipboard History'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('Clear All',
                  style: TextStyle(color: CupertinoColors.destructiveRed)),
              onPressed: () {
                _showClearAllDialog(context);
              },
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              await ref.read(clipboardHistoryListProvider.notifier).refresh();
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Search history',
              ),
            ),
          ),
          if (filteredHistory.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.doc_text_search,
                      size: 64,
                      color: CupertinoColors.systemGrey3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _query.isEmpty
                          ? 'No clipboard history yet'
                          : 'No results for "$_query"',
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = filteredHistory[index];
                    return _buildHistoryCard(context, entry);
                  },
                  childCount: filteredHistory.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, ClipboardEntry entry) {
    final timeStr = _formatTimestamp(entry.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: CupertinoButton(
          padding: const EdgeInsets.all(16.0),
          onPressed: () async {
            final service = ref.read(clipboardServiceProvider);
            await service.setText(entry.content);
            if (!context.mounted) return;
            _showCopiedToast(context);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CupertinoColors.label,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        entry.isLocal
                            ? CupertinoIcons.device_laptop
                            : CupertinoIcons.device_phone_portrait,
                        size: 14,
                        color: CupertinoColors.activeBlue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        entry.sourceDeviceName,
                        style: const TextStyle(
                          color: CupertinoColors.secondaryLabel,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: CupertinoColors.tertiaryLabel,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCopiedToast(BuildContext ctx) {
    showCupertinoDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (dialogCtx) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
            Navigator.of(dialogCtx).pop();
          }
        });
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.check_mark_circled, color: CupertinoColors.white, size: 36),
                SizedBox(height: 8),
                Text(
                  'Copied to Clipboard',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day}';
  }

  void _showClearAllDialog(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (dialogCtx) {
        return CupertinoAlertDialog(
          title: const Text('Clear Clipboard History'),
          content: const Text('Are you sure you want to clear all history? This cannot be undone.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Clear All'),
              onPressed: () async {
                final nav = Navigator.of(dialogCtx);
                await ref.read(clipboardHistoryListProvider.notifier).clear();
                nav.pop();
              },
            ),
          ],
        );
      },
    );
  }
}
